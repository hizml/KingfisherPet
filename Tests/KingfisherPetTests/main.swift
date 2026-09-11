import Foundation
import KingfisherPetCore

/// 零依赖测试 runner(CLT 无 XCTest/swift-testing):swift run kf-tests
/// 断言失败打印定位并 exit 1;全过 exit 0。CI 与本地通用。
// swiftlint:disable:next force_unwrapping
var failures = 0
var passed = 0

func expect(_ name: String, _ cond: Bool, _ detail: @autoclosure () -> String = "") {
    if cond {
        passed += 1
        print("  ✔ \(name)")
    } else {
        failures += 1
        print("  ✘ \(name)  \(detail())")
    }
}

@main
enum TestMain {
    static func main() {
        print("== kf-tests 核心纯逻辑(正常流正确、边界态也要正确)==")

        // MARK: - 版本比较(UpdateService.isNewer)
        print("[版本比较]")
        expect("新版提示 v1.4.64 > 1.4.63", UpdateService.isNewer("v1.4.64", than: "1.4.63"))
        expect("大版本 v1.5.0 > 1.4.99", UpdateService.isNewer("v1.5.0", than: "1.4.99"))
        expect("同版本不提示", !UpdateService.isNewer("v1.4.63", than: "1.4.63"))
        // N5105 实锤场景:本地装未发布的 1.4.63,线上 latest 是 v1.4.59 → 不得误报
        expect("本地比线上新不误报(实锤场景 v1.4.59 vs 1.4.63)",
               !UpdateService.isNewer("v1.4.59", than: "1.4.63"))
        expect("明显旧版不提示", !UpdateService.isNewer("v1.4.0", than: "1.4.63"))
        expect("逐段数值:10 > 9(字典序会判反)", UpdateService.isNewer("v1.4.10", than: "1.4.9"))
        expect("段数不齐 v2.0 > 1.9.9", UpdateService.isNewer("v2.0", than: "1.9.9"))
        expect("畸形 tag 保守不更新", !UpdateService.isNewer("garbage", than: "1.4.63"))
        expect("空串保守不更新", !UpdateService.isNewer("", than: "1.4.63"))

        // MARK: - Settings clamp(写入/读取/NaN)
        print("[Settings clamp]")
        Settings.shared.activity = 5
        expect("activity 上钳 5→1", Settings.shared.activity == 1.0)
        Settings.shared.activity = -3
        expect("activity 下钳 -3→0", Settings.shared.activity == 0.0)
        Settings.shared.speed = 99
        expect("speed 上钳 99→1.5", Settings.shared.speed == 1.5)
        Settings.shared.activity = .nan
        expect("activity NaN→默认0.5", Settings.shared.activity == 0.5)
        Settings.shared.speed = .infinity
        expect("speed Inf→默认1.0", Settings.shared.speed == 1.0)
        // 脏存储:getter 也必须钳(直接塞 UserDefaults 模拟脏 plist)
        UserDefaults.standard.set(Double.nan, forKey: "kingfisher.settings.activity")
        expect("脏存储 NaN 读取钳制", Settings.shared.activity == 0.5)
        UserDefaults.standard.set(42.0, forKey: "kingfisher.settings.speed")
        expect("脏存储越界读取钳制 42→1.5", Settings.shared.speed == 1.5)
        // 还原,别污染宿主机设置
        Settings.shared.activity = 0.5
        Settings.shared.speed = 1.0

        // MARK: - Language 回退
        print("[Language 回退]")
        expect("未知键回退键名本身", Language.t("no.such.key") == "no.such.key")
        expect("已知键命中", Language.t("menu.settings").contains("设置") || Language.t("menu.settings").contains("Settings"))

        // MARK: - 放音勿扰探针判定 v4.1(rate + 双路活性)
        print("[探针判定 v4.1]")
        let sw = SpriteLibrary.shouldSwallowChirp
        expect("在播且时间戳新鲜 → 吞", sw(1, 5, false))
        expect("倍速在播(rate=2)且新鲜 → 吞", sw(2, 10, false))
        expect("暂停(rate=0)→ 照叫", !sw(0, 5, true))
        expect("无会话(age=nil)→ 照叫", !sw(1, nil, false))
        expect("时间戳恰好当前(age=0 合法新鲜)→ 吞", sw(1, 0, false))
        expect("僵尸会话(ts 过期且快照没动)→ 照叫(咪咕实锤)", !sw(1, 3600, false))
        expect("临界:恰好 180s → 吞(闭区间)", sw(1, 180, false))
        expect("负 age(时钟异常)→ 照叫", !sw(1, -3, false))
        expect("活性②路:ts 过期但跨探针快照变了 → 吞(慢刷新播放器)", sw(1, 600, true))
        expect("双路皆死且暂停 → 照叫", !sw(0, 9999, false))
        expect("无时间戳但快照在推进 → 吞(活性②路独立成立)", sw(1, nil, true))

        // MARK: - 昼夜节律(DayRhythm;Windows tests/dayrhythm.test.mjs 同一用例口径)
        print("[昼夜节律]")
        let day = DayRhythm.thinkBands(activity: 0.5, hour: 12)
        expect("白天基准 idleBand=11", day.idleBand == 11, "got \(day.idleBand)")
        expect("白天基准 walkEnd=21", day.walkEnd == 21, "got \(day.walkEnd)")
        expect("白天 k≈1.177(原归一公式不变)", abs(day.k - 73.0 / 62.0) < 1e-9, "got \(day.k)")
        expect("白天 sleep 兜底≈7.2(原公式原语义:带宽和 61,/62 余量进兜底)",
               abs(day.sleepShare - (100.0 - 21.0 - 61.0 * 73.0 / 62.0)) < 1e-9, "got \(day.sleepShare)")
        let deep = DayRhythm.thinkBands(activity: 0.5, hour: 3)
        expect("深夜 sing/fish/dart 带归零", deep.widths[1...3].allSatisfy { $0 == 0 })
        expect("深夜 k=白天×0.35", abs(deep.k - day.k * 0.35) < 1e-9)
        expect("深夜 sleep 份额>50(节律压过活跃度)", deep.sleepShare > 50, "got \(deep.sleepShare)")
        let dawn = DayRhythm.thinkBands(activity: 0.5, hour: 7)
        expect("清晨晨鸣 sing×1.5", abs(dawn.widths[2] - 7 * 1.5) < 1e-9)
        let dusk = DayRhythm.thinkBands(activity: 0.5, hour: 19)
        expect("黄昏 k=白天×0.85", abs(dusk.k - day.k * 0.85) < 1e-9)
        expect("黄昏晒夕阳 sun×1.3", abs(dusk.widths[5] - 7 * 1.3) < 1e-9)
        let night23 = DayRhythm.thinkBands(activity: 0.5, hour: 23)
        expect("夜 k=白天×0.5", abs(night23.k - day.k * 0.5) < 1e-9)
        // 边界小时落段(5 深夜/6、8 清晨/9、16 白天/17、21 黄昏/22、23 夜)
        expect("h5 落深夜", DayRhythm.factors(hour: 5).overall == 0.35)
        expect("h6 落清晨", DayRhythm.factors(hour: 6).sing == 1.5)
        expect("h8 落清晨", DayRhythm.factors(hour: 8).sing == 1.5)
        expect("h9 落白天", DayRhythm.factors(hour: 9) == DayRhythm.Factors.base)
        expect("h16 落白天", DayRhythm.factors(hour: 16) == DayRhythm.Factors.base)
        expect("h17 落黄昏", DayRhythm.factors(hour: 17).overall == 0.85)
        expect("h21 落黄昏", DayRhythm.factors(hour: 21).overall == 0.85)
        expect("h22 落夜", DayRhythm.factors(hour: 22).overall == 0.5)
        expect("h23 落夜", DayRhythm.factors(hour: 23).overall == 0.5)
        // sleep 份额排序:深夜 > 夜 > 黄昏 > 白天(越夜越困);清晨最精神(晨鸣吃掉 doze)
        let seg = { (h: Int) in DayRhythm.thinkBands(activity: 0.5, hour: h).sleepShare }
        expect("sleep 份额 深夜>夜>黄昏>白天", seg(3) > seg(23) && seg(23) > seg(19) && seg(19) > seg(12),
               "deep=\(seg(3)) n23=\(seg(23)) dusk=\(seg(19)) day=\(seg(12))")
        expect("清晨最精神(sleep<白天)", seg(7) < seg(12), "dawn=\(seg(7)) day=\(seg(12))")
        // 24h × 3 活跃度全扫:布局守恒(idle/walk 并入 walkEnd + 动作带×k + sleep = 100)
        var conserveOK = true
        for h in 0...23 {
            for a in [0.2, 0.5, 0.8] {
                let p = DayRhythm.thinkBands(activity: a, hour: h)
                let actionTotal: Double = p.widths.reduce(0.0, +) * p.k
                let total = Double(p.walkEnd) + actionTotal + p.sleepShare
                if abs(total - 100) > 0.01 { conserveOK = false }
            }
        }
        expect("24h×3 活跃度布局守恒(和=100)", conserveOK)

        // MARK: - 天气归一化(WeatherService;Windows tests/weather.test.mjs 同一映射同一用例口径)
        print("[天气归一化]")
        // Open-Meteo WMO 码表(逐码断言;未知码→nil)
        expect("OM 0/1/2 晴", [0, 1, 2].allSatisfy { WeatherService.mainFromOpenMeteo(code: $0, windSpeed: 0) == .sunny })
        expect("OM 3 阴", WeatherService.mainFromOpenMeteo(code: 3, windSpeed: 0) == .overcast)
        expect("OM 45/48 雾", [45, 48].allSatisfy { WeatherService.mainFromOpenMeteo(code: $0, windSpeed: 0) == .fog })
        expect("OM 毛雨/冻毛雨/小雨/阵雨轻 → 小雨",
               [51, 53, 56, 57, 61, 80].allSatisfy { WeatherService.mainFromOpenMeteo(code: $0, windSpeed: 0) == .rainLight })
        expect("OM 密毛雨/中大雨/冻雨/阵雨强 → 大雨",
               [55, 63, 65, 66, 67, 81, 82].allSatisfy { WeatherService.mainFromOpenMeteo(code: $0, windSpeed: 0) == .rainHeavy })
        expect("OM 95/96/99 雷暴", [95, 96, 99].allSatisfy { WeatherService.mainFromOpenMeteo(code: $0, windSpeed: 0) == .thunder })
        expect("OM 71/77/85 小雪", [71, 77, 85].allSatisfy { WeatherService.mainFromOpenMeteo(code: $0, windSpeed: 0) == .snowLight })
        expect("OM 73/75/86 大雪", [73, 75, 86].allSatisfy { WeatherService.mainFromOpenMeteo(code: $0, windSpeed: 0) == .snowHeavy })
        expect("OM 未知码 nil", WeatherService.mainFromOpenMeteo(code: 42, windSpeed: 0) == nil)
        // 风速并档:>10.8 m/s → wind,与码位主档取更凶
        expect("OM 风 10.9 覆盖晴", WeatherService.mainFromOpenMeteo(code: 0, windSpeed: 10.9) == .wind)
        expect("OM 风 10.8 边界不触发", WeatherService.mainFromOpenMeteo(code: 0, windSpeed: 10.8) == .sunny)
        expect("OM 雷暴压过风", WeatherService.mainFromOpenMeteo(code: 95, windSpeed: 30) == .thunder)
        expect("OM 大雨压过风", WeatherService.mainFromOpenMeteo(code: 63, windSpeed: 20) == .rainHeavy)
        expect("OM 阴+风 → 风", WeatherService.mainFromOpenMeteo(code: 3, windSpeed: 15) == .wind)
        // 和风码表(v7 官方对照;302–304 才是雷阵雨,313 是冻雨)
        expect("QW 100–103,150–153 晴",
               ([Int](100...103) + [Int](150...153)).allSatisfy { WeatherService.mainFromQWeather(code: $0, windScale: 0) == .sunny })
        expect("QW 104 阴", WeatherService.mainFromQWeather(code: 104, windScale: 0) == .overcast)
        expect("QW 500–515 雾霾沙 → fog(能见度类)",
               [502, 507, 515].allSatisfy { WeatherService.mainFromQWeather(code: $0, windScale: 0) == .fog })
        expect("QW 阵雨/小中雨/毛毛雨/夜阵雨 → 小雨",
               [300, 301, 305, 306, 309, 350, 351].allSatisfy { WeatherService.mainFromQWeather(code: $0, windScale: 0) == .rainLight })
        expect("QW 大/暴/特大暴雨/跨级雨/冻雨 → 大雨",
               [307, 308, 310, 311, 312, 313, 314, 316, 318].allSatisfy { WeatherService.mainFromQWeather(code: $0, windScale: 0) == .rainHeavy })
        expect("QW 302/303/304 雷阵雨 → 雷暴", [302, 303, 304].allSatisfy { WeatherService.mainFromQWeather(code: $0, windScale: 0) == .thunder })
        expect("QW 小中雪/雨夹雪/阵雪/夜阵雪 → 小雪",
               [400, 401, 404, 405, 406, 407, 408, 457].allSatisfy { WeatherService.mainFromQWeather(code: $0, windScale: 0) == .snowLight })
        expect("QW 大雪/暴雪/跨级雪 → 大雪",
               [402, 403, 409, 410, 456].allSatisfy { WeatherService.mainFromQWeather(code: $0, windScale: 0) == .snowHeavy })
        expect("QW 399 未知雨保守轻档", WeatherService.mainFromQWeather(code: 399, windScale: 0) == .rainLight)
        expect("QW 499 未知雪保守轻档", WeatherService.mainFromQWeather(code: 499, windScale: 0) == .snowLight)
        expect("QW 900 热归晴", WeatherService.mainFromQWeather(code: 900, windScale: 0) == .sunny)
        expect("QW 901 冷归阴", WeatherService.mainFromQWeather(code: 901, windScale: 0) == .overcast)
        expect("QW windScale≥6 → wind", WeatherService.mainFromQWeather(code: 100, windScale: 6) == .wind)
        expect("QW windScale=5 不触发", WeatherService.mainFromQWeather(code: 100, windScale: 5) == .sunny)
        expect("QW 雷暴压过风", WeatherService.mainFromQWeather(code: 304, windScale: 9) == .thunder)
        // 温度副档
        expect("温度 33→热", WeatherService.tempFlags(tempC: 33).hot && !WeatherService.tempFlags(tempC: 33).cold)
        expect("温度 32 边界不热", !WeatherService.tempFlags(tempC: 32).hot)
        expect("温度 4→冷", WeatherService.tempFlags(tempC: 4).cold && !WeatherService.tempFlags(tempC: 4).hot)
        expect("温度 5 边界不冷", !WeatherService.tempFlags(tempC: 5).cold)
        expect("温度 nil 双 false", { let f = WeatherService.tempFlags(tempC: nil); return !f.hot && !f.cold }())

        // MARK: - 天气权重表 + 昼夜×天气合成(PLAN-B 权重映射)
        print("[天气权重]")
        expect("sunny sun×1.6 watch×1.2", {
            let f = WeatherFactors.factors(main: .sunny, hot: false, cold: false)
            return f.sun == 1.6 && f.watch == 1.2 && f.overall == 1
        }())
        expect("overcast 全不干预", WeatherFactors.factors(main: .overcast, hot: false, cold: false) == .neutral)
        expect("rainLight 外出×0.7 栖窗×1.3", {
            let f = WeatherFactors.factors(main: .rainLight, hot: false, cold: false)
            return f.fly == 0.7 && f.fish == 0.7 && f.dart == 0.7 && f.perch == 1.3
        }())
        expect("rainHeavy 外出×0.3 栖窗×1.6", {
            let f = WeatherFactors.factors(main: .rainHeavy, hot: false, cold: false)
            return f.fly == 0.3 && f.perch == 1.6
        }())
        expect("thunder 整体×0.3 外出=0 watch 保留", {
            let f = WeatherFactors.factors(main: .thunder, hot: false, cold: false)
            return f.overall == 0.3 && f.fly == 0 && f.fish == 0 && f.dart == 0 && f.watch == 1
        }())
        expect("snowLight walk×0.8 watch×1.5", {
            let f = WeatherFactors.factors(main: .snowLight, hot: false, cold: false)
            return f.walk == 0.8 && f.watch == 1.5
        }())
        expect("snowHeavy 外出×0.4 栖窗/watch×1.5", {
            let f = WeatherFactors.factors(main: .snowHeavy, hot: false, cold: false)
            return f.fly == 0.4 && f.perch == 1.5 && f.watch == 1.5
        }())
        expect("fog fly×0.5 watch×1.5", {
            let f = WeatherFactors.factors(main: .fog, hot: false, cold: false)
            return f.fly == 0.5 && f.watch == 1.5
        }())
        expect("wind fly×0.3 栖窗×1.5", {
            let f = WeatherFactors.factors(main: .wind, hot: false, cold: false)
            return f.fly == 0.3 && f.perch == 1.5
        }())
        expect("hot 副档叠乘(sunny+hot: sun 1.6×0.5, fish×1.2)", {
            let f = WeatherFactors.factors(main: .sunny, hot: true, cold: false)
            return abs(f.sun - 0.8) < 1e-9 && abs(f.fish - 1.2) < 1e-9
        }())
        expect("cold 副档叠乘(sunny+cold: sun 1.6×1.6, fly×0.8)", {
            let f = WeatherFactors.factors(main: .sunny, hot: false, cold: true)
            return abs(f.sun - 2.56) < 1e-9 && abs(f.fly - 0.8) < 1e-9
        }())
        // 合成:昼夜 × 天气在同一 thinkBands 相乘
        let plainDay = DayRhythm.thinkBands(activity: 0.5, hour: 12)
        let thunderDay = DayRhythm.thinkBands(activity: 0.5, hour: 12,
                                              weather: WeatherFactors.factors(main: .thunder, hot: false, cold: false))
        expect("雷暴白天 k=×0.3 且外出带=0", abs(thunderDay.k - plainDay.k * 0.3) < 1e-9
               && thunderDay.widths[0] == 0 && thunderDay.widths[1] == 0 && thunderDay.widths[3] == 0)
        expect("雷暴白天 sleep 兜底 >50", thunderDay.sleepShare > 50, "got \(thunderDay.sleepShare)")
        let rainLightDay = DayRhythm.thinkBands(activity: 0.5, hour: 12,
                                                weather: WeatherFactors.factors(main: .rainLight, hot: false, cold: false))
        expect("小雨 fly带宽 7×0.7,栖窗带宽 6×1.3", abs(rainLightDay.widths[0] - 7 * 0.7) < 1e-9
               && abs(rainLightDay.widths[7] - 6 * 1.3) < 1e-9)
        let snowLightDay = DayRhythm.thinkBands(activity: 0.5, hour: 12,
                                                weather: WeatherFactors.factors(main: .snowLight, hot: false, cold: false))
        expect("小雪 walkEnd 收缩 21→19(walk×0.8)", snowLightDay.walkEnd == 19, "got \(snowLightDay.walkEnd)")
        var wxConserveOK = true
        for h in [3, 8, 12, 19, 23] {
            for main in [WeatherKind.sunny, .rainHeavy, .thunder, .snowLight, .wind, .fog] {
                let f = WeatherFactors.factors(main: main, hot: main == .sunny, cold: false)
                let p = DayRhythm.thinkBands(activity: 0.5, hour: h, weather: f)
                let actionTotal: Double = p.widths.reduce(0.0, +) * p.k
                let total = Double(p.walkEnd) + actionTotal + p.sleepShare
                // 守恒;唯一例外:增益叠加(清晨晨鸣×晴天等)带宽和超 100 → sleep 钳 0,
                // 尾部桶(poop)变不可达——结构无害,鸟只是那个时段特别精神
                if !(abs(total - 100) <= 0.01 || (p.sleepShare == 0 && total >= 100)) { wxConserveOK = false }
            }
        }
        expect("昼夜×天气 6 档×5 时段布局守恒(或增益叠加钳 0)", wxConserveOK)

        // MARK: - 成长系统(Growth;Windows tests/growth.test.mjs 同一用例口径)
        print("[成长系统]")
        expect("档位换算:19 陌生/20 相识/39 相识/40 熟悉/59 熟悉/60 亲近/80 亲密/100 缘定一生", {
            Growth.Stage.of(intimacy: 19) == .stranger && Growth.Stage.of(intimacy: 20) == .acquainted
            && Growth.Stage.of(intimacy: 39) == .acquainted && Growth.Stage.of(intimacy: 40) == .familiar
            && Growth.Stage.of(intimacy: 59) == .familiar && Growth.Stage.of(intimacy: 60) == .close
            && Growth.Stage.of(intimacy: 80) == .intimate && Growth.Stage.of(intimacy: 100) == .bonded
        }())
        expect("档位换算越界防御:-1/999", Growth.Stage.of(intimacy: -1) == .stranger
               && Growth.Stage.of(intimacy: 999) == .bonded)
        expect("来访概率单调升且 stranger=0", {
            let ps = [Growth.Stage.stranger, .acquainted, .familiar, .close, .intimate, .bonded].map { $0.affectionChance }
            return ps[0] == 0 && ps == ps.sorted() && ps.last! <= 0.05
        }())
        let gSaved = Growth.shared.intimacy
        let gHatched = Growth.shared.hatched
        Growth.shared.intimacy = 95
        expect("add 钳制到 100:95+8 → 100(实际生效 5)", Growth.shared.add(8) == 5 && Growth.shared.intimacy == 100)
        expect("shouldHatch:满级未孵化", Growth.shared.hatched == false && Growth.shared.shouldHatch == true)
        Growth.shared.markHatched()
        expect("markHatched 后 shouldHatch=false", Growth.shared.shouldHatch == false)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        expect("喂鱼冷却:首喂通过", Growth.shared.feedAllowed(now: t0) == true)
        expect("喂鱼冷却:t+9min 拒绝", Growth.shared.feedAllowed(now: t0.addingTimeInterval(9 * 60)) == false)
        expect("喂鱼冷却:t+10min01s 放行", Growth.shared.feedAllowed(now: t0.addingTimeInterval(601)) == true)
        // 还原(别污染宿主机设置)
        Growth.shared.intimacy = gSaved
        if !gHatched { UserDefaults.standard.removeObject(forKey: "kingfisher.growth.hatched") }
        UserDefaults.standard.removeObject(forKey: "kingfisher.growth.lastFeedAt")

        // MARK: - 结果
        print("== \(passed) passed, \(failures) failed ==")
        if failures > 0 { exit(1) }
    }
}
