import AppKit
import Foundation

/// 天气联动(v1.5.0 天气批 B):双数据源(Open-Meteo 默认免 key / 和风天气用户填 Key)
/// → 归一化 11 档 → 30 分钟刷新 → NotificationCenter 广播,Behavior 订阅乘进权重带。
///
/// 纪律(硬约束,docs/PLAN-v1.5.0-batch1.md):
/// - 默认关;开启后才发首个网络请求(明示网络行为,设置界面文案写明)
/// - 失败/断网/key 无效(和风非 200)一律静默降级 = 无系数:不弹窗、不重试轰炸,
///   等下个 30min 周期自然重试;状态只在设置界面/托盘菜单标注(状态可见)
/// - Windows 侧对称实现 windows/src/weather.ts(同一映射表同一用例口径,任改一处必须同步)
public final class WeatherService {

    public static let shared = WeatherService()

    /// 快照更新通知(userInfo 无;读 WeatherService.shared 的 now/alerts)
    public static let didUpdate = Notification.Name("kingfisher.weather.didUpdate")

    /// 托盘菜单天气状态行(由 AppDelegate 建菜单后注入;服务自行刷新标题)
    weak var statusMenuItem: NSMenuItem?

    // MARK: - 状态(状态可见层)

    public enum Status: String { case off, ok, unavailable }

    /// 当前快照;nil = 无系数(未开启/查询失败静默降级中)
    public private(set) var now: WeatherNow?
    /// 生效中的预警(和风源专属;空 = 无)
    public private(set) var alerts: [WeatherAlert] = []
    public private(set) var status: Status = .off

    /// 预警生效中(行为侧整体活跃 ×0.3 用)
    public var alertActive: Bool { !alerts.isEmpty }

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 30 * 60   // 30 分钟

    // MARK: - 启停(由 AppDelegate 按设置驱动)

    func start() {
        stop()
        status = .ok
        refresh()   // 开启即发首个请求
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        kfLog("weather: 启动(源=\(Settings.shared.weatherProvider) 城市=\(Settings.shared.weatherCity.isEmpty ? "IP定位" : Settings.shared.weatherCity))")
    }

    func stop() {
        timer?.invalidate(); timer = nil
        let had = (now != nil || !alerts.isEmpty || status != .off)
        now = nil
        alerts = []
        status = .off
        updateMenuItem()
        if had {
            kfLog("weather: 停止,行为系数清零")
            NotificationCenter.default.post(name: Self.didUpdate, object: nil)
        }
    }

    /// 设置变化(provider/城市/key/host)→ 重启;关闭 → 停止
    func settingsChanged() {
        if Settings.shared.weatherEnabled { start() } else { stop() }
    }

    // MARK: - 刷新链(全部静默:任何失败只降级不弹窗)

    private func refresh() {
        let s = Settings.shared
        if s.weatherProvider == "qweather" {
            refreshQWeather()
        } else {
            refreshOpenMeteo()
        }
    }

    private func fail(_ why: String) {
        // 静默降级 = 无系数:清快照、标不可用、发通知(行为回无天气),不弹窗不重试
        now = nil
        alerts = []
        status = .unavailable
        updateMenuItem()
        kfLog("weather: 降级(\(why))")
        NotificationCenter.default.post(name: Self.didUpdate, object: nil)
    }

    private func succeed(now: WeatherNow, alerts: [WeatherAlert]) {
        self.now = now
        self.alerts = alerts
        status = .ok
        updateMenuItem()
        kfLog("weather: ok \(now.raw) 预警=\(alerts.count)")
        NotificationCenter.default.post(name: Self.didUpdate, object: nil)
    }

    // MARK: - Open-Meteo(默认源,免 key)

    private func refreshOpenMeteo() {
        locate { lat, lon in
            var comp = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            comp.queryItems = [
                URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
                URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
                URLQueryItem(name: "current", value: "weather_code,temperature_2m,wind_speed_10m"),
                URLQueryItem(name: "timezone", value: "auto"),
            ]
            Self.getJSON(comp.url!) { obj in
                guard let cur = obj?["current"] as? [String: Any],
                      let code = (cur["weather_code"] as? NSNumber)?.intValue else {
                    self.fail("open-meteo 响应缺 current/weather_code"); return
                }
                let temp = (cur["temperature_2m"] as? NSNumber)?.doubleValue
                let wind = (cur["wind_speed_10m"] as? NSNumber)?.doubleValue ?? 0
                let main = Self.mainFromOpenMeteo(code: code, windSpeed: wind)
                guard let main else { self.fail("open-meteo 未知码 \(code)"); return }
                let (hot, cold) = Self.tempFlags(tempC: temp)
                self.succeed(now: WeatherNow(main: main, hot: hot, cold: cold,
                                             tempC: temp,
                                             raw: "OM#\(code) v\(String(format: "%.0f", wind))m/s t\(temp.map { String(format: "%.0f", $0) } ?? "?")°"),
                             alerts: [])   // Open-Meteo 无预警数据
            }
        }
    }

    // MARK: - 和风天气(专属口子:Key + Host,含预警)

    private func qweatherHost() -> String {
        let h = Settings.shared.weatherHost.trimmingCharacters(in: .whitespaces)
        return h.isEmpty ? "devapi.qweather.com" : h   // 以控制台分配的专属 Host 为准
    }

    private func refreshQWeather() {
        let key = Settings.shared.weatherKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { fail("和风未填 Key"); return }
        let host = qweatherHost()
        locate { [weak self] lat, lon in
            guard let self else { return }
            let loc = String(format: "%.2f,%.2f", lon, lat)   // 和风 location = 经,纬
            // 天气 + 预警同一周期同查(预警是和风口子专属福利)
            Self.getJSON(Self.qwURL(host: host, path: "/v7/weather/now", loc: loc, key: key)) { wobj in
                guard let wobj, (wobj["code"] as? String) == "200",
                      let n = wobj["now"] as? [String: Any],
                      let codeStr = n["code"] as? String, let code = Int(codeStr) else {
                    self.fail("和风天气不可用(code/key)"); return
                }
                let temp = (n["temp"] as? String).flatMap(Double.init)
                let windScale = (n["windScale"] as? String).flatMap { Int($0) } ?? 0
                let main = Self.mainFromQWeather(code: code, windScale: windScale)
                guard let main else { self.fail("和风未知码 \(code)"); return }
                let (hot, cold) = Self.tempFlags(tempC: temp)
                Self.getJSON(Self.qwURL(host: host, path: "/v7/warning/now", loc: loc, key: key)) { aobj in
                    // 预警查询失败不拖垮天气本身:预警置空、天气照常
                    var alerts: [WeatherAlert] = []
                    if let aobj, (aobj["code"] as? String) == "200",
                       let list = aobj["warning"] as? [[String: Any]] {
                        alerts = list.compactMap { w in
                            guard let id = w["id"] as? String else { return nil }
                            return WeatherAlert(id: id,
                                                type: (w["typeName"] as? String) ?? "",
                                                level: (w["level"] as? String) ?? "")
                        }
                    }
                    self.succeed(now: WeatherNow(main: main, hot: hot, cold: cold,
                                                 tempC: temp,
                                                 raw: "QW#\(code) wind\(windScale) t\(temp.map { String(format: "%.0f", $0) } ?? "?")°"),
                                 alerts: alerts)
                }
            }
        }
    }

    private static func qwURL(host: String, path: String, loc: String, key: String) -> URL {
        var comp = URLComponents(string: "https://\(host)\(path)")!
        comp.queryItems = [URLQueryItem(name: "location", value: loc),
                           URLQueryItem(name: "key", value: key)]
        return comp.url!
    }

    // MARK: - 定位(城市名 → 各源 geocoding;留空 → ipapi.co IP 粗定位)

    private func locate(done: @escaping (Double, Double) -> Void) {
        let city = Settings.shared.weatherCity.trimmingCharacters(in: .whitespaces)
        if city.isEmpty {
            // IP 粗定位(设置文案已明示「含 IP 粗略定位」)
            Self.getJSON(URL(string: "https://ipapi.co/json/")!) { obj in
                guard let obj,
                      let lat = (obj["latitude"] as? NSNumber)?.doubleValue,
                      let lon = (obj["longitude"] as? NSNumber)?.doubleValue else {
                    self.fail("IP 定位失败(断网?)"); return
                }
                done(lat, lon)
            }
            return
        }
        if Settings.shared.weatherProvider == "qweather" {
            var comp = URLComponents(string: "https://geoapi.qweather.com/v2/city/lookup")!
            comp.queryItems = [URLQueryItem(name: "location", value: city),
                               URLQueryItem(name: "key", value: Settings.shared.weatherKey.trimmingCharacters(in: .whitespaces))]
            Self.getJSON(comp.url!) { obj in
                guard let obj, (obj["code"] as? String) == "200",
                      let first = (obj["location"] as? [[String: Any]])?.first,
                      let lat = Double(first["lat"] as? String ?? ""),
                      let lon = Double(first["lon"] as? String ?? "") else {
                    self.fail("和风城市查找失败(名字/Key)"); return
                }
                done(lat, lon)
            }
        } else {
            var comp = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            comp.queryItems = [URLQueryItem(name: "name", value: city),
                               URLQueryItem(name: "count", value: "1"),
                               URLQueryItem(name: "language", value: "zh"),
                               URLQueryItem(name: "format", value: "json")]
            Self.getJSON(comp.url!) { obj in
                guard let obj,
                      let first = (obj["results"] as? [[String: Any]])?.first,
                      let lat = (first["latitude"] as? NSNumber)?.doubleValue,
                      let lon = (first["longitude"] as? NSNumber)?.doubleValue else {
                    self.fail("Open-Meteo 城市查找失败(名字?)"); return
                }
                done(lat, lon)
            }
        }
    }

    /// 统一 GET → JSON(回调恒主线程;失败 obj=nil)
    private static func getJSON(_ url: URL, done: @escaping ([String: Any]?) -> Void) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, resp, err in
            var obj: [String: Any]?
            if let data, (resp as? HTTPURLResponse)?.statusCode == 200 || resp == nil,
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                obj = parsed
            }
            if obj == nil { kfLog("weather: 请求失败 \(url.host ?? "?") \(err.map(String.init(describing:)) ?? "非200")") }
            DispatchQueue.main.async { done(obj) }
        }.resume()
    }

    // MARK: - 归一化(纯函数,kf-tests 直打;Windows weather.ts 同一映射同一用例口径)

    /// WMO 码表(Open-Meteo;官方 weather codes,逐项核对过):
    /// 0–2 晴 / 3 阴 / 45,48 雾 / 51,53 毛雨 56,57 冻毛雨 61,80 雨(轻) /
    /// 55 密毛雨 63,65 雨 66,67 冻雨 81,82 阵雨(强)→ 大雨档 /
    /// 95,96,99 雷暴(96/99 伴冰雹) / 71,77,85 雪(轻) / 73,75,86 雪(重)
    /// 风速 >10.8 m/s(6 级)→ wind 档,按恶劣度与码位主档取更凶者。
    public static func mainFromOpenMeteo(code: Int, windSpeed: Double) -> WeatherKind? {
        let byCode: WeatherKind?
        switch code {
        case 0, 1, 2:            byCode = .sunny
        case 3:                  byCode = .overcast
        case 45, 48:             byCode = .fog
        case 51, 53, 56, 57, 61, 80: byCode = .rainLight
        case 55, 63, 65, 66, 67, 81, 82: byCode = .rainHeavy
        case 95, 96, 99:         byCode = .thunder
        case 71, 77, 85:         byCode = .snowLight
        case 73, 75, 86:         byCode = .snowHeavy
        default:                 byCode = nil
        }
        let byWind: WeatherKind? = windSpeed > 10.8 ? .wind : nil
        return merge(byCode, byWind)
    }

    /// 和风码表(v7 官方对照,逐项核对过;Windows 同表):
    /// 100–103,150–153 晴 / 104 阴 / 500–515 雾霾沙尘(能见度类→fog 档) /
    /// 300,301,350,351 阵雨 305,306,309 小中雨毛雨 → 小雨档 /
    /// 307,308,310,311,312,314–318 大暴雨特大暴雨跨级雨 313 冻雨 → 大雨档 /
    /// 302,303,304 雷阵雨(伴冰雹) → 雷暴 /
    /// 400,401,404–408,457 小中雪雨夹雪阵雪 → 小雪档 / 402,403,409,410,456 大暴雪跨级雪 → 大雪档 /
    /// 399/499 未知强度雨雪 → 保守归轻档 / 900 热 901 冷(官方自带冷热码,主档归晴/阴)
    /// windScale ≥ 6(10.8+ m/s)→ wind 档,按恶劣度与码位主档取更凶者。
    public static func mainFromQWeather(code: Int, windScale: Int) -> WeatherKind? {
        let byCode: WeatherKind?
        switch code {
        case 100...103, 150...153: byCode = .sunny
        case 104:                  byCode = .overcast
        case 500...515:            byCode = .fog
        case 300, 301, 305, 306, 309, 350, 351: byCode = .rainLight
        case 307, 308, 310, 311, 312, 313, 314...318: byCode = .rainHeavy
        case 302, 303, 304:        byCode = .thunder
        case 400, 401, 404, 405, 406, 407, 408, 457: byCode = .snowLight
        case 402, 403, 409, 410, 456: byCode = .snowHeavy
        case 399:                  byCode = .rainLight   // 未知强度雨:保守轻档
        case 499:                  byCode = .snowLight   // 未知强度雪:保守轻档
        case 900:                  byCode = .sunny       // 热(主档晴,温度副档另算)
        case 901:                  byCode = .overcast    // 冷(主档阴,温度副档另算)
        default:                   byCode = nil
        }
        let byWind: WeatherKind? = windScale >= 6 ? .wind : nil
        return merge(byCode, byWind)
    }

    /// 主档互斥取最恶劣:thunder > rainHeavy > wind > snowHeavy > rainLight > snowLight > fog > overcast > sunny
    public static func merge(_ a: WeatherKind?, _ b: WeatherKind?) -> WeatherKind? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let x?, nil), (nil, let x?): return x
        case (let x?, let y?): return severity(x) >= severity(y) ? x : y
        }
    }

    public static func severity(_ k: WeatherKind) -> Int {
        switch k {
        case .thunder: return 9
        case .rainHeavy: return 8
        case .wind: return 7
        case .snowHeavy: return 6
        case .rainLight: return 5
        case .snowLight: return 4
        case .fog: return 3
        case .overcast: return 2
        case .sunny: return 1
        case .hot, .cold: return 0   // 副档不参与主档排序(防御)
        }
    }

    /// 温度副档:>32°C 热 / <5°C 冷(双源同规则;和风另有 900/901 显式码,也走 tempFlags 兜)
    public static func tempFlags(tempC: Double?) -> (hot: Bool, cold: Bool) {
        guard let t = tempC, t.isFinite else { return (false, false) }
        return (t > 32, t < 5)
    }

    // MARK: - 托盘菜单状态行

    /// 语言切换重建菜单后由 AppDelegate 调:重刷状态行标题
    func refreshMenuTitle() { updateMenuItem() }

    private func updateMenuItem() {
        guard let item = statusMenuItem else { return }
        switch status {
        case .off:
            item.isHidden = true
        case .unavailable:
            item.isHidden = false
            item.title = Language.t("weather.unavailable")
        case .ok:
            item.isHidden = false
            if let top = alerts.max(by: { $0.rank < $1.rank }) {
                item.title = String(format: Language.t("weather.alert.line"), top.type, top.levelSuffix)
            } else if let n = now {
                var title = "\(n.main.emoji) \(Language.t("weather.kind.\(n.main.rawValue)"))"
                if let t = n.tempC { title += String(format: " · %.0f°", t) }
                item.title = title
            } else {
                item.title = Language.t("weather.unavailable")
            }
        }
    }
}

// MARK: - 值类型

/// 归一化天气档(11;hot/cold 为温度副档,不作为主档出现)
public enum WeatherKind: String, CaseIterable {
    case sunny, overcast, rainLight, rainHeavy, thunder
    case snowLight, snowHeavy, fog, wind
    case hot, cold

    public var emoji: String {
        switch self {
        case .sunny: return "☀️"
        case .overcast: return "☁️"
        case .rainLight: return "🌦"
        case .rainHeavy: return "🌧"
        case .thunder: return "⛈"
        case .snowLight: return "🌨"
        case .snowHeavy: return "❄️"
        case .fog: return "🌫"
        case .wind: return "💨"
        case .hot: return "🥵"
        case .cold: return "🥶"
        }
    }
}

/// 归一化快照:主档 + 温度副档(可叠乘)
public struct WeatherNow {
    public let main: WeatherKind
    public let hot: Bool
    public let cold: Bool
    public let tempC: Double?     // 菜单展示用
    public let raw: String        // 原始码(日志/诊断)
}

/// 和风预警(按 ID 去重;展示取级别最高一条)
public struct WeatherAlert {
    public let id: String
    public let type: String       // 台风/暴雨/寒潮/高温…
    public let level: String      // 白/蓝/黄/橙/红
    /// 级别排序(红>橙>黄>蓝>白;未知 0)
    var rank: Int {
        switch level {
        case let l where l.contains("红"): return 5
        case let l where l.contains("橙"): return 4
        case let l where l.contains("黄"): return 3
        case let l where l.contains("蓝"): return 2
        case let l where l.contains("白"): return 1
        default: return 0
        }
    }
    /// 菜单后缀:「橙色预警」;未知级别原样带出
    var levelSuffix: String {
        rank > 0 ? level + "色预警" : level
    }
}

// MARK: - 权重系数(行为层;乘进 thinkBands,机制与昼夜节律同构)

/// 天气权重系数(全 1 = 不干预;表 = docs/PLAN-v1.5.0-batch1.md 权重映射,老板拍板版)
public struct WeatherFactors: Equatable {
    public var overall = 1.0   // 整体活跃(雷暴 ×0.3 → sleep 兜底自然放大,同深夜机制)
    public var fly = 1.0
    public var fish = 1.0
    public var sing = 1.0
    public var dart = 1.0
    public var watch = 1.0
    public var sun = 1.0
    public var perch = 1.0     // 栖窗
    public var walk = 1.0
    public static let neutral = WeatherFactors()

    /// 主档系数表 + 温度副档叠乘(纯函数,kf-tests 直打;Windows weather.ts 同表)
    public static func factors(main: WeatherKind, hot: Bool, cold: Bool) -> WeatherFactors {
        var f = WeatherFactors()
        switch main {
        case .sunny:    f.sun = 1.6; f.watch = 1.2
        case .overcast: break                                  // 不干预
        case .rainLight:  f.fly = 0.7; f.fish = 0.7; f.dart = 0.7; f.perch = 1.3
        case .rainHeavy:  f.fly = 0.3; f.fish = 0.3; f.dart = 0.3; f.perch = 1.6
        case .thunder:    f.overall = 0.3; f.fly = 0; f.fish = 0; f.dart = 0   // watch 保留(雷惊探头)
        case .snowLight:  f.walk = 0.8; f.watch = 1.5
        case .snowHeavy:  f.fly = 0.4; f.fish = 0.4; f.dart = 0.4; f.perch = 1.5; f.watch = 1.5
        case .fog:        f.fly = 0.5; f.watch = 1.5
        case .wind:       f.fly = 0.3; f.perch = 1.5
        case .hot, .cold: break                                 // 副档不作主档(防御)
        }
        if hot  { f.sun *= 0.5; f.fish *= 1.2 }   // 热:少晒太阳,戏水降温
        if cold { f.sun *= 1.6; f.fly *= 0.8 }    // 冷:取暖,少飞
        return f
    }
}
