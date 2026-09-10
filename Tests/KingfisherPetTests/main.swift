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

        // MARK: - 结果
        print("== \(passed) passed, \(failures) failed ==")
        if failures > 0 { exit(1) }
    }
}
