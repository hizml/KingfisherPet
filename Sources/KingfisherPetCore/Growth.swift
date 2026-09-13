import Foundation

/// 成长系统轻量版(v1.5.x batch2;2026-09-13 经济重调):亲密度 0–100 + 档位 + 喂鱼/抚摸冷却
/// + 每日获取上限 + 满级孵化(可重复:孵化后回落「熟悉」再养成)。
/// 纯逻辑与行为解耦:加分入口分散在点击/喂鱼/召唤/捕鱼/天气彩蛋;亲密度不改
/// thinkBands 权重带(昼夜/天气双层公式已冻结进双端单测),只通过「主动来访概率」
/// 影响互动频率。Windows 侧 growth.mjs 对称实现(同一公式同一用例口径)。
public final class Growth {

    public static let shared = Growth()

    /// 值变化通知(菜单状态行刷新用)
    public static let didChangeNotification = Notification.Name("kingfisher.growth.didChange")

    // MARK: - 档位(纯函数,单测直打)

    public enum Stage: Int, CaseIterable {
        case stranger = 0      // 0–19 陌生
        case acquainted = 1    // 20–39 相识
        case familiar = 2      // 40–59 熟悉
        case close = 3         // 60–79 亲近
        case intimate = 4      // 80–99 亲密
        case bonded = 5        // 100 缘定一生

        public static func of(intimacy: Int) -> Stage {
            switch intimacy {
            case ..<20: return .stranger
            case ..<40: return .acquainted
            case ..<60: return .familiar
            case ..<80: return .close
            case ..<100: return .intimate
            default: return .bonded
            }
        }

        /// 主动来访概率(think 每拍):亲密度影响互动频率的落点——
        /// 档位越高,鸟越会自己飞来看你一眼
        public var affectionChance: Double {
            switch self {
            case .stranger:  return 0
            case .acquainted: return 0.004
            case .familiar:  return 0.008
            case .close:     return 0.012
            case .intimate:  return 0.018
            case .bonded:    return 0.025
            }
        }

        public var langKey: String { "growth.stage.\(self)" }
    }

    // MARK: - 状态

    private static let kIntimacy = "kingfisher.growth.intimacy"
    private static let kHatchCount = "kingfisher.growth.hatchCount"
    private static let kHatched = "kingfisher.growth.hatched"          // 旧版一次性标志(迁移源)
    private static let kLastFeedAt = "kingfisher.growth.lastFeedAt"
    private static let kLastPetAt = "kingfisher.growth.lastPetAt"
    private static let kDayStamp = "kingfisher.growth.dayStamp"        // "yyyy-MM-dd"
    private static let kDayGain = "kingfisher.growth.dayGain"

    private var _intimacy: Int
    /// 亲密度 0–100(钳制;写入持久化并广播)
    public var intimacy: Int {
        get { _intimacy }
        set {
            let v = min(100, max(0, newValue))
            let changed = v != _intimacy
            _intimacy = v
            UserDefaults.standard.set(v, forKey: Self.kIntimacy)
            if changed {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
    }

    public var stage: Stage { Stage.of(intimacy: intimacy) }

    /// 满级孵化待演(Behavior 在 think 里查;孵化后亲密度回落,自然转 false)
    public var shouldHatch: Bool { intimacy >= 100 }

    /// 孵化次数(可重复彩蛋;每次孵化亲密度回落「熟悉」40 再养成)
    public private(set) var hatchCount: Int

    /// 孵化演出结算:计数 +1、亲密度回落「熟悉」(40)。彩蛋因此可重复,但每次都要重新养。
    public func markHatched() {
        hatchCount += 1
        UserDefaults.standard.set(hatchCount, forKey: Self.kHatchCount)
        intimacy = 40
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    // MARK: - 加分(统一入口;每日获取上限,超出不生效。返回实际生效分)

    /// 每日获取上限(所有来源合计;跨自然日清零)。【可调】
    /// 老板实测反馈"几小时就满"——原口径点击无冷却+喂鱼 8/10min,狂点半天即 100。
    /// 现口径:点击 +1/60s 冷却、喂鱼 +5/30min、召唤 +1、自发捕鱼 +1,封顶 30/天 ≈ 3–4 天满。
    public static let dailyCap = 30

    @discardableResult
    public func add(_ n: Int, bypassDailyCap: Bool = false, now: Date = Date()) -> Int {
        guard n > 0 else { return 0 }
        if !bypassDailyCap {
            rollDayIfNeeded(now: now)
            if dayGain >= Self.dailyCap { return 0 }
            let effective = min(n, Self.dailyCap - dayGain)
            dayGain += effective
            UserDefaults.standard.set(dayGain, forKey: Self.kDayGain)
            let before = intimacy
            intimacy = before + effective
            return intimacy - before
        }
        let before = intimacy
        intimacy = before + n
        return intimacy - before
    }

    private var dayGain: Int
    private func rollDayIfNeeded(now: Date) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: now)
        if today != dayStamp {
            dayStamp = today
            dayGain = 0
            UserDefaults.standard.set(today, forKey: Self.kDayStamp)
            UserDefaults.standard.set(0, forKey: Self.kDayGain)
        }
    }
    private var dayStamp: String

    // MARK: - 冷却(入参注入可测)

    /// 喂鱼冷却 30 分钟,+5 分。【可调】原 10 分钟 +8 太快
    public static let feedCooldown: TimeInterval = 30 * 60
    public static let feedGain = 5

    /// true=本次可喂(并占下冷却时刻);false=冷却中
    public func feedAllowed(now: Date = Date()) -> Bool {
        if let last = UserDefaults.standard.object(forKey: Self.kLastFeedAt) as? Date,
           now >= last,   // 评审 A9:时钟回拨(负 interval)不进冷却判定,否则回拨多久锁多久
           now.timeIntervalSince(last) < Self.feedCooldown {
            return false
        }
        UserDefaults.standard.set(now, forKey: Self.kLastFeedAt)
        return true
    }

    /// 抚摸(点击)冷却 60 秒(防狂点秒满)。【可调】
    public static let petCooldown: TimeInterval = 60

    /// true=本次点击计分(并占下冷却);false=冷却中
    public func petAllowed(now: Date = Date()) -> Bool {
        if let last = UserDefaults.standard.object(forKey: Self.kLastPetAt) as? Date,
           now >= last,
           now.timeIntervalSince(last) < Self.petCooldown {
            return false
        }
        UserDefaults.standard.set(now, forKey: Self.kLastPetAt)
        return true
    }

    // MARK: - 菜单状态行(状态可见纪律)

    public var menuTitle: String {
        var t = "❤️ " + Language.t(stage.langKey) + (stage == .bonded ? "" : " · \(intimacy)/100")
        if hatchCount > 0 {
            t += String(format: " " + Language.t("growth.hatchCountSuffix"), hatchCount)
        }
        return t
    }

    init() {
        let d = UserDefaults.standard
        _intimacy = d.object(forKey: Self.kIntimacy) != nil
            ? min(100, max(0, d.integer(forKey: Self.kIntimacy))) : 0
        // 旧版一次性标志迁移:已孵化过 → 计数 1
        if d.object(forKey: Self.kHatchCount) != nil {
            hatchCount = max(0, d.integer(forKey: Self.kHatchCount))
        } else {
            hatchCount = d.bool(forKey: Self.kHatched) ? 1 : 0
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        dayStamp = d.string(forKey: Self.kDayStamp) ?? ""
        dayGain = dayStamp == f.string(from: Date()) ? max(0, d.integer(forKey: Self.kDayGain)) : 0
        if dayStamp != f.string(from: Date()) { dayStamp = f.string(from: Date()) }
    }
}
