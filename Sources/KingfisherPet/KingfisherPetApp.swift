import AppKit
import ServiceManagement
import Foundation
import QuartzCore

/// 诊断日志:append 到 /tmp/kf_debug.log(睡眠唤醒卡死排查用)。CACurrentMediaTime 打时间戳。
func kfLog(_ msg: String) {
    let line = String(format: "%.2f %@\n", CACurrentMediaTime(), msg)
    let url = URL(fileURLWithPath: "/tmp/kf_debug.log")
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        if let d = line.data(using: .utf8) { h.write(d) }
        try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

@main
enum KingfisherPetApp {
    static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)   // 不在 Dock 露脸
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var petController: PetWindowController!
    private var soundMenuItem: NSMenuItem!
    private var autoLoginMenuItem: NSMenuItem!
    private var shadowCtl: ShadowController!
    private var branchCtl: BranchController!
    private var crackCtl: CrackController!
    private var poopCtl: PoopController!
    private var settingsWindowController: SettingsWindowController?

    private static let kAutoLogin = "kingfisher.autoLogin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 加载资源(默认 flat);如保存的主题不是 flat,切过去
        let s = Settings.shared
        if s.theme != SpriteLibrary.shared.currentTheme {
            SpriteLibrary.shared.reload(theme: s.theme)
        }
        SpriteLibrary.shared.soundOn = s.soundOn

        // 设置变化 → 应用到各子系统
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged(_:)),
            name: Settings.didChangeNotification, object: nil)

        // 开机自启
        if UserDefaults.standard.bool(forKey: Self.kAutoLogin) {
            try? SMAppService.mainApp.register()
        }

        // 菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()

        // 宠物
        petController = PetWindowController()
        petController.show()

        // 地面阴影(随太阳)+ 树枝(高处停靠)
        if let win = petController.window {
            shadowCtl = ShadowController(bird: win)
            shadowCtl.start()
            petController.behavior.shadow = shadowCtl
            branchCtl = BranchController(bird: win, behavior: petController.behavior)
            branchCtl.start()
            petController.behavior.branch = branchCtl
            crackCtl = CrackController()
            crackCtl.start()
            crackCtl.bird = win
            petController.behavior.crack = crackCtl
            poopCtl = PoopController()
            poopCtl.start()
            poopCtl.bird = win
            petController.behavior.poopCtl = poopCtl
            // 主题切换:阴影/树枝贴图跟随换主题
            SpriteLibrary.shared.observeThemeChanged { [weak self] in
                self?.shadowCtl.reloadTheme()
                self?.branchCtl.reloadTheme()
            }
        }

        // 多屏:屏幕布局变化(插拔外接屏、分辨率变更)时,裂纹重定位 + 鸟钳制回当前屏
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParamsChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // 系统睡眠/唤醒:睡眠前停掉一切定时器和特效(防止 asyncAfter 回调积压,唤醒时补发堆积卡死);
        // 唤醒时干净重启。
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        // 锁屏/解锁:用户离开 → 鸟睡觉;回来 → 赖床醒来(进程不挂起,走分布式通知)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenLocked),
                        name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlocked),
                        name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)

        if ProcessInfo.processInfo.environment["KF_SNAPSHOT"] != nil {
            writeDebugSnapshot()
        }
        if ProcessInfo.processInfo.environment["KF_DEMO"] != nil {
            // 调试:2.5s 后自动拉一坨,便于截图看下落/落地
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.petController.behavior.startPoop()
            }
        }
    }

    /// 调试:把当前视图渲染成 PNG 并记录窗口信息(不经过屏幕录制权限)
    private func writeDebugSnapshot() {
        let view = petController.petView
        let lib = SpriteLibrary.shared
        let info = """
        帧数 = \(lib.frames.count)
        序列 = \(lib.manifest.sequences.keys.sorted().joined(separator: ","))
        窗口 frame = \(petController.window?.frame ?? .zero)
        屏幕 frame = \(NSScreen.main?.frame ?? .zero)
        可见 frame = \(NSScreen.main?.visibleFrame ?? .zero)
        视图 bounds = \(view.bounds)
        """
        try? info.write(toFile: "/tmp/kf_debug.log", atomically: true, encoding: .utf8)

        let w = Int(view.bounds.width), h = Int(view.bounds.height)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: max(w, 1), pixelsHigh: max(h, 1),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/kf_snapshot.png"))
        }
    }

    // MARK: - 菜单栏
    private func configureStatusItem() {
        let button = statusItem.button
        let icon = SpriteLibrary.shared.frame("idle_0")?.image
        if let icon = icon {
            let sized = NSImage(size: NSSize(width: 18, height: 18))
            sized.lockFocus()
            icon.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18),
                      from: .zero, operation: .sourceOver, fraction: 1)
            sized.unlockFocus()
            sized.isTemplate = false
            button?.image = sized
        }
        button?.toolTip = NSLocalizedString("statusitem.tooltip", comment: "")
        button?.setAccessibilityLabel(NSLocalizedString("ax.tooltip", comment: ""))

        let menu = NSMenu()
        menu.addItem(item(NSLocalizedString("menu.callOver", comment: ""), action: #selector(callOver)))
        menu.addItem(item(NSLocalizedString("menu.fish", comment: ""), action: #selector(doFish)))
        menu.addItem(item(NSLocalizedString("menu.sing", comment: ""), action: #selector(doSing)))
        menu.addItem(item(NSLocalizedString("menu.perch", comment: ""), action: #selector(doPerch)))
        menu.addItem(item(NSLocalizedString("menu.peck", comment: ""), action: #selector(doPeck)))
        menu.addItem(item(NSLocalizedString("menu.toggleVisibility", comment: ""), action: #selector(toggleVisibility)))
        menu.addItem(.separator())
        soundMenuItem = item(NSLocalizedString("menu.soundOn", comment: ""), action: #selector(toggleSound))
        menu.addItem(soundMenuItem)
        autoLoginMenuItem = item(NSLocalizedString("menu.autoLogin", comment: ""), action: #selector(toggleAutoLogin))
        menu.addItem(autoLoginMenuItem)
        menu.addItem(item(NSLocalizedString("menu.repairScreen", comment: ""), action: #selector(repairScreen)))
        menu.addItem(item(NSLocalizedString("menu.settings", comment: ""), action: #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(item(NSLocalizedString("menu.about", comment: ""), action: #selector(showAbout)))
        menu.addItem(item(NSLocalizedString("menu.quit", comment: ""), action: #selector(quit)))
        statusItem.menu = menu
        refreshMenuState()
    }

    private func refreshMenuState() {
        soundMenuItem.title = NSLocalizedString(
            Settings.shared.soundOn ? "menu.soundOn" : "menu.soundOff", comment: "")
        let on = UserDefaults.standard.bool(forKey: Self.kAutoLogin)
        autoLoginMenuItem.state = on ? .on : .off
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: action, keyEquivalent: "")
        m.target = self
        return m
    }

    // MARK: - 动作
    @objc private func callOver() {
        petController.behavior.callOver()
    }

    @objc private func doFish() {
        petController.behavior.startFish()
    }

    @objc private func doSing() {
        petController.behavior.startSing()
    }

    @objc private func doPerch() {
        petController.behavior.startPerchWindow()
    }

    @objc private func doPeck() {
        petController.behavior.startPeck()
    }

    @objc private func repairScreen() {
        crackCtl?.clear()
    }

    @objc private func toggleVisibility() {
        petController.behavior.toggleVisibility()
    }

    @objc private func toggleSound() {
        Settings.shared.soundOn.toggle()
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.show()
    }

    /// 屏幕布局变化(插拔屏/分辨率):重定位裂纹覆盖层,把鸟钳回当前可见区。
    @objc private func screenParamsChanged() {
        crackCtl?.relocate()
        petController?.behavior.clampToCurrentScreen()
    }

    /// 系统睡眠前:鸟入睡 + 停所有常驻 timer(逐帧/屎/树枝,防唤醒补发堆积卡死)+ 清场 + 隐藏裂纹。
    @objc private func systemWillSleep() {
        kfLog("willSleep effects=\(Effect.active.count)")
        petController?.behavior.sleepForUserAbsence(systemSleep: true)
        petController?.petView.suspendAnimation()
        poopCtl?.suspend()
        branchCtl?.suspend()
        Effects.clearAll()                     // 清所有特效窗口(太阳/水花/zzz/音符)
        crackCtl?.setVisible(false)            // 裂纹覆盖层也隐藏
        kfLog("willSleep done effects=\(Effect.active.count)")
    }

    /// 系统唤醒:清场(保险)+ 显示裂纹 + 恢复常驻 timer + 鸟赖床 2–4 秒后醒来。
    @objc private func systemDidWake() {
        kfLog("didWake effects=\(Effect.active.count)")
        Effects.clearAll()
        crackCtl?.setVisible(true)
        petController?.petView.resumeAnimation()
        poopCtl?.resume()
        branchCtl?.resume()
        petController?.behavior.wakeFromUserAbsence()
        kfLog("didWake done effects=\(Effect.active.count)")
    }

    /// 锁屏:鸟入睡(进程不挂起,自然 sleep + zzz + 禁声)。不清场,特效自然到期。
    @objc private func screenLocked() {
        kfLog("screenLocked effects=\(Effect.active.count)")
        petController?.behavior.sleepForUserAbsence(systemSleep: false)
        petController?.petView.suspendAnimation()   // 锁屏屏幕黑:停所有常驻 timer,防长时间高 CPU 发烫卡死
        poopCtl?.suspend()
        branchCtl?.suspend()
    }

    /// 解锁:鸟赖床 2–4 秒后醒来。
    @objc private func screenUnlocked() {
        kfLog("screenUnlocked effects=\(Effect.active.count)")
        petController?.petView.resumeAnimation()
        poopCtl?.resume()
        branchCtl?.resume()
        petController?.behavior.wakeFromUserAbsence()
    }

    /// 设置变化:应用到各子系统 + 同步菜单
    @objc private func settingsChanged(_ n: Notification) {
        let key = (n.userInfo?["key"] as? String) ?? ""
        switch key {
        case "kingfisher.settings.soundOn":
            SpriteLibrary.shared.soundOn = Settings.shared.soundOn
            soundMenuItem.title = NSLocalizedString(
                Settings.shared.soundOn ? "menu.soundOn" : "menu.soundOff", comment: "")
        case "kingfisher.settings.theme":
            SpriteLibrary.shared.reload(theme: Settings.shared.theme)
        default: break
        }
    }

    @objc private func toggleAutoLogin() {
        let key = Self.kAutoLogin
        let on = UserDefaults.standard.bool(forKey: key)
        if on {
            try? SMAppService.mainApp.unregister()
            UserDefaults.standard.set(false, forKey: key)
        } else {
            do {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: key)
            } catch {
                // 注册失败(用户未在系统设置允许等):不持久化
            }
        }
        autoLoginMenuItem.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
    }

    func applicationWillTerminate(_ notification: Notification) {
        petController?.behavior.savePosition()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("about.title", comment: "")
        alert.informativeText = NSLocalizedString("about.body", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("about.github", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("about.ok", comment: ""))
        if let img = SpriteLibrary.shared.frame("idle_0")?.image {
            alert.icon = img
        }
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/hizml")!)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
