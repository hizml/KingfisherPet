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

        // MARK: - 放音勿扰探针判定(shouldSwallowChirp)
        print("[探针判定]")
        expect("在播(1)→吞", SpriteLibrary.shouldSwallowChirp(probeOutput: "1"))
        expect("没播(0)→照叫", !SpriteLibrary.shouldSwallowChirp(probeOutput: "0"))
        expect("无 now-playing(nil)→照叫", !SpriteLibrary.shouldSwallowChirp(probeOutput: "nil"))
        expect("带换行空白仍判在播", SpriteLibrary.shouldSwallowChirp(probeOutput: " 1\n"))
        expect("畸形输出照叫(fail-open)", !SpriteLibrary.shouldSwallowChirp(probeOutput: "garbage"))
        expect("空串照叫(fail-open)", !SpriteLibrary.shouldSwallowChirp(probeOutput: ""))
        expect("旧协议残留 rate=2 照叫(不再吞倍速,改由 flag 主判)",
               !SpriteLibrary.shouldSwallowChirp(probeOutput: "2"))

        // MARK: - 结果
        print("== \(passed) passed, \(failures) failed ==")
        if failures > 0 { exit(1) }
    }
}
