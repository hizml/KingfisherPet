import Foundation

/// 昼夜节律(v1.5.0 天气批 A):按本地小时给 think() 的动作桶乘系数,纯本地零网络。
/// 分段(初版参数,可调;docs/PLAN-v1.5.0-batch1.md):
/// 深夜 0–6 活跃×0.35 且唱/捕鱼/掠飞≈0 / 清晨 6–9 晨鸣 sing×1.5 / 白天 9–17 基准 /
/// 黄昏 17–22 ×0.85 且日光浴 sun×1.3 / 夜 22–24 ×0.5。
/// Windows 侧对称实现:windows/src/shared.mjs thinkBands(同一公式同一用例口径,
/// 任改一处必须同步另一端)。
public enum DayRhythm {

    /// 各桶系数(1 = 不干预)。overall 乘在 k 公式上——九动作带与 sleep 兜底份额
    /// 同步缩:overall<1 时动作带变窄、超出部分自然落进 sleep 兜底桶
    /// (深夜多睡不需要显式 sleep 桶,"超界进 sleep"的兜底语义原样保留)。
    public struct Factors: Equatable {
        public var overall = 1.0
        public var sing = 1.0
        public var fish = 1.0
        public var dart = 1.0
        public var sun = 1.0
        public static let base = Factors()
    }

    /// 测试/演示注入口:环境变量锁定小时(如 KF_HOUR_OVERRIDE=3 大白天看深夜行为)。
    /// 不设或值非法 → 走真实本地时。环境进程内恒定,读一次即可。
    public static let hourOverride: Int? = {
        guard let s = ProcessInfo.processInfo.environment["KF_HOUR_OVERRIDE"],
              let h = Int(s.trimmingCharacters(in: .whitespaces)),
              (0...23).contains(h) else { return nil }
        return h
    }()

    public static func currentHour() -> Int {
        hourOverride ?? Calendar.current.component(.hour, from: Date())
    }

    public static func factors(hour: Int) -> Factors {
        var f = Factors.base
        switch hour {
        case 0..<6:   f.overall = 0.35; f.sing = 0; f.fish = 0; f.dart = 0
        case 6..<9:   f.sing = 1.5
        case 17..<22: f.overall = 0.85; f.sun = 1.3
        case 22..<24: f.overall = 0.5
        default: break                                  // 9–17 白天基准
        }
        return f
    }

    /// think() 权重带布局(纯函数,kf-tests 直打这里——测试必须打真实现,不是复制品)。
    /// 把原先散在 Behavior.think() 的活跃度公式收拢于此,叠加昼夜系数。
    /// widths 顺序(未乘 k):fly/fish/sing/dart/watch/sun/peck/perch/poop。
    /// sleepShare = 兜底桶份额(walk + 带宽×k 之外余下的部分,恒 ≥ 0)。
    public static func thinkBands(activity: Double, hour: Int)
        -> (idleBand: Int, walkEnd: Int, k: Double, widths: [Double], sleepShare: Double) {
        let f = factors(hour: hour)
        let a = min(1, max(0, activity))
        let idleBand = Int(((1.0 - a) * 22).rounded())
        let walkEnd = idleBand + max(1, Int(((1.0 - a) * 20).rounded()))
        let k = max(0.5, (100.0 - Double(walkEnd) - 6.0) / 62.0) * f.overall
        let base: [Double] = [7, 8, 7, 7, 7, 7, 6, 6, 6]
        let mul: [Double] = [1, f.fish, f.sing, f.dart, 1, f.sun, 1, 1, 1]
        let widths = zip(base, mul).map(*)
        let sleepShare = max(0, 100.0 - Double(walkEnd) - widths.reduce(0, +) * k)
        return (idleBand, walkEnd, k, widths, sleepShare)
    }
}
