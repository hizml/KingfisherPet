import AppKit
import ApplicationServices

/// 勿扰监控:其他应用全屏(视频/游戏)→ 鸟隐身+静音,绝不盖在视频上。
/// 从 AppDelegate 拆分的独立类型(评审待办:AppDelegate 拆分)。
/// AX 全屏检测在后台串行队列执行(评审待办:AX 挪后台)——AXUIElementCopyAttributeValue
/// 对无响应的前台 App 可能阻塞,此前同步在主线程 3s 一拍地查,前台卡则鸟也卡;
/// 挪后台后最多延迟一拍应用结果,串行队列保序、streak 语义不变。
final class DndMonitor {

    /// 行为层入口(拆分后不持有 AppDelegate,由闭包供给)
    var behaviorProvider: () -> Behavior? = { nil }

    private var timer: Timer?
    private var fsOnStreak = 0, fsOffStreak = 0
    private var dndSkipLast = ""
    private var dndDiagTick = 0
    private var axFailStreak = 0
    private var axPromptShown = false
    /// AX 查询串行队列(保序:结果按拍次顺序回主线程应用)
    private let axQueue = DispatchQueue(label: "kf.dnd.ax", qos: .utility)

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func dndSkip(_ why: String) {
        if why != dndSkipLast { if !why.isEmpty { kfLog("dndCheck 跳过: \(why)") }; dndSkipLast = why }
    }

    private func check() {
        guard let behavior = behaviorProvider() else { return }
        // 鸟不在屏/睡着时仍要累计 streak(否则勿扰中隐藏鸟 → fsOffStreak 永不累计
        // → dndActive 永真 → hatchIn 拒绝复活 = 死锁,只能重启);只跳过 enter/exitDnd 副作用
        let active = behavior.isOnScreen && !behavior.isSleeping
        if !active { dndSkip(behavior.isOnScreen ? "sleeping" : "offscreen") } else { dndSkip("") }
        let screen = behavior.birdScreen
        dndDiagTick += 1
        let tick = dndDiagTick
        axQueue.async { [weak self] in
            let r = Self.queryFullscreen(screen)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // AX 失败记账(授权未生效):连续 5 拍 → 弹窗引导开辅助功能(用户要求:权限必须明示)
                self.axFailStreak = r.axErr != nil ? self.axFailStreak + 1 : 0
                if let err = r.axErr {
                    if self.axFailStreak % 5 == 1 { kfLog("ax: 取窗口失败 err=\(err) 连续\(self.axFailStreak)拍,前台=\(r.front ?? "nil")") }
                    if self.axFailStreak >= 5 { self.promptAccessibilityOnce() }
                }
                // 观测脚手架门控:排障期才开(生产每 30s 一次 AX 逐窗查询+日志是纯负载)
                if !r.fs && tick % 10 == 0 && ProcessInfo.processInfo.environment["KF_DND_DIAG"] == "1" {
                    self.axQueue.async {
                        let line = Self.fsDiagSnapshot()
                        DispatchQueue.main.async { kfLog(line) }
                    }
                }
                if r.fs { self.fsOnStreak += 1; self.fsOffStreak = 0 } else { self.fsOffStreak += 1; self.fsOnStreak = 0 }
                if behavior.dndActive != true && self.fsOnStreak >= 2 && active {
                    kfLog("dnd: 全屏应用,鸟隐身+静音")
                    behavior.enterDnd()
                } else if behavior.dndActive == true && self.fsOffStreak >= 2 {
                    kfLog("dnd: 全屏退出,恢复")
                    if active { behavior.exitDnd() }   // 鸟隐藏时只清标志,不强制显示(下次 hatchIn 自然复活)
                }
            }
        }
    }

    // MARK: - 全屏检测(纯查询,无状态;失败信息上报给调用方记账)

    /// 全屏应用检测 v4(最终方案):AX 辅助功能的 "AXFullScreen" 窗口属性。
    /// 几何法 v1-v3 全部失败(自机实验实锤:全屏窗在 CGWindowList 只剩 33px 条状残影,
    /// 任何基于窗口矩形的判定都不可能)。AX 是系统权威信号,Rectaangle/AltTab/System
    /// Events 同款;该属性不在公开 SDK 常量(仅运行时字符串"AXFullScreen")。
    /// 遍历前台 App 的【全部】窗口,任一全屏即判定(macOS 全屏=整个 App 独占 Space)。
    /// v5 混合判定:原生全屏(AXFullScreen)或自绘全屏(无边框窗口盖满整屏)。
    /// v6 前台来源改 NSWorkspace 取 pid + AXUIElementCreateApplication 直连:
    /// systemWide 的 focusedApplication 对 Chromium 系(Edge/Electron)实测恒返回
    /// -25212 NoValue(原生 App 正常)——用户全屏看片恰是浏览器,检测从未生效。
    private static func queryFullscreen(_ screen: NSScreen?) -> (fs: Bool, axErr: Int32?, front: String?) {
        let scrFrame = screen?.frame ?? NSScreen.main?.frame ?? .zero
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return (false, nil, nil) }
        let appEl = AXUIElementCreateApplication(frontApp.processIdentifier)
        var winsRef: CFTypeRef?
        let werr = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &winsRef)
        guard werr == .success, let wins = winsRef as? [AXUIElement] else {
            // 授权未生效时此查询失败(本机 macOS 26 表现 -25204/-25212,非教科书 -25211)
            return (false, werr.rawValue, frontApp.localizedName)
        }
        for win in wins {
            var fsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(win, "AXFullScreen" as CFString, &fsRef) == .success,
               let fs = fsRef, (fs as? Bool) == true {
                return (true, nil, frontApp.localizedName)   // ① 原生全屏
            }
            if let f = axFrame(win), scrFrame.width > 0,
               abs(f.origin.x - scrFrame.origin.x) <= 4, abs(f.origin.y - scrFrame.origin.y) <= 4,
               f.width >= scrFrame.width - 4, f.height >= scrFrame.height - 4 {
                return (true, nil, frontApp.localizedName)   // ② 自绘全屏:窗口盖满整屏
            }
        }
        return (false, nil, frontApp.localizedName)
    }

    /// AX 窗口矩形(kAXPosition + kAXSize,AXValue 解包)
    private static func axFrame(_ win: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?; var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let pr = posRef, let sr = sizeRef else { return nil }
        var p = CGPoint.zero; var sz = CGSize.zero
        guard AXValueGetValue(pr as! AXValue, .cgPoint, &p),
              AXValueGetValue(sr as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: p, size: sz)
    }

    /// 全屏检测诊断快照(低频):前台 App 名 + 每窗 AXFullScreen 的错误码/值。
    /// 纯函数返回日志行(在后台队列组装,主线程落日志)。
    private static func fsDiagSnapshot() -> String {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return "fsDiag: frontmostApplication=nil" }
        guard frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return "fsDiag: 前台=自己(忽略)" }
        let appEl = AXUIElementCreateApplication(frontApp.processIdentifier)
        let name = frontApp.localizedName ?? "pid:\(frontApp.processIdentifier)"
        var winsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &winsRef) == .success,
            let wins = winsRef as? [AXUIElement] else {
            return "fsDiag: 前台=\(name) 取窗口列表失败"
        }
        var parts: [String] = []
        for (i, win) in wins.enumerated() {
            var v: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(win, "AXFullScreen" as CFString, &v)
            let val = err == .success ? "\(v as? Bool ?? false)" : "err\(err.rawValue)"
            let fr = axFrame(win).map { String(format: "[%.0f,%.0f %.0fx%.0f]", $0.origin.x, $0.origin.y, $0.width, $0.height) } ?? "noFrame"
            parts.append("w\(i):fs=\(val) \(fr)")
        }
        return "fsDiag: 前台=\(name) 窗口\(wins.count)个 [\(parts.joined(separator: " "))]"
    }

    /// AX 持续失败(授权未生效)→ 弹窗引导用户开辅助功能(用户要求:需要权限必须明示)
    private func promptAccessibilityOnce() {
        guard !axPromptShown else { return }
        axPromptShown = true
        kfLog("ax: 弹窗引导开启辅助功能")
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.alertStyle = .informational
        a.messageText = "翡 需要辅助功能权限"
        let appPath = Bundle.main.bundleURL.path   // 发布版用户机器上路径各不相同,动态生成
        a.informativeText = "勿扰模式(全屏看片/放音时鸟自动隐身静音)依赖辅助功能。\n\n请到 系统设置 → 隐私与安全性 → 辅助功能,删除旧的「翡」后重新添加并勾选(选择:\(appPath))"
        a.addButton(withTitle: "打开系统设置")
        a.addButton(withTitle: "稍后")
        if a.runModal() == .alertFirstButtonReturn {
            // 新版系统设置的辅助功能深链;打不开则退到隐私面板
            let deep = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
            if !NSWorkspace.shared.open(deep) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }
}
