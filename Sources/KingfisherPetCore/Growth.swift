import Foundation

/// 成长系统轻量版(v1.5.x batch2):亲密度 0–100(不衰减)+ 档位 + 喂鱼冷却 + 满级孵化。
/// 纯逻辑与行为解耦:加分入口分散在点击/喂鱼/召唤/捕鱼/天气彩蛋;亲密度不改
/// thinkBands 权重带(昼夜/天气双层公式已冻结进双端单测),只通过「主动来访概率」
/// 影响互动频率。Windows 侧 growth.ts 对称实现(同一公式同一用例口径)。
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
    private static let kHatched = "kingfisher.growth.hatched"
    private static let kLastFeedAt = "kingfisher.growth.lastFeedAt"

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

    /// 满级孵化彩蛋未播(Behavior 在 think 里查,触发时机=下一个思考拍,不靠通知)
    public var shouldHatch: Bool { intimacy >= 100 && !hatched }

    /// 孵化已演过(一次性;由演出方在开演时标记)
    public private(set) var hatched: Bool

    public func markHatched() {
        hatched = true
        UserDefaults.standard.set(true, forKey: Self.kHatched)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    // MARK: - 加分(统一入口;返回实际生效分,方便调用方/测试核对)

    @discardableResult
    public func add(_ n: Int) -> Int {
        let before = intimacy
        intimacy = before + n
        return intimacy - before
    }

    // MARK: - 喂鱼冷却(10 分钟;入参注入可测)

    public static let feedCooldown: TimeInterval = 10 * 60

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

    // MARK: - 菜单状态行(状态可见纪律)

    public var menuTitle: String {
        let s = stage
        if s == .bonded {
            return "❤️ " + (hatched ? Language.t("growth.stage.bonded") + Language.t("growth.hatchedSuffix")
                                  : Language.t("growth.stage.bonded") + " · 100/100")
        }
        return "❤️ " + Language.t(s.langKey) + " · \(intimacy)/100"
    }

    init() {
        let d = UserDefaults.standard
        _intimacy = d.object(forKey: Self.kIntimacy) != nil
            ? min(100, max(0, d.integer(forKey: Self.kIntimacy))) : 0
        hatched = d.bool(forKey: Self.kHatched)
    }
}
