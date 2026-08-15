import AppKit
import ServiceManagement
import Foundation
import QuartzCore

/// 诊断日志:append 到 /tmp/kf_debug.log(睡眠唤醒卡死排查用)。CACurrentMediaTime 打时间戳。
/// 用缓存的 FileHandle(不每次开关文件,避免高频 IO 吃 CPU)。超过 5MB 截断(防无限增长)。
private var _kfLogHandle: FileHandle?
private var _kfLogSize: Int = 0
func kfLog(_ msg: String) {
    let line = String(format: "%.2f %@\n", CACurrentMediaTime(), msg)
    let url = URL(fileURLWithPath: "/tmp/kf_debug.log")
    guard let d = line.data(using: .utf8) else { return }
    if _kfLogHandle == nil {
        // 首次:若旧日志超 5MB 从头写,否则追加
        var oldSize = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let n = attrs[.size] as? NSNumber {
            oldSize = n.intValue
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        _kfLogHandle = try? FileHandle(forWritingTo: url)
        if oldSize > 5_000_000 {
            try? _kfLogHandle?.truncate(atOffset: 0)   // 覆盖:截断旧日志
        } else {
            _kfLogHandle?.seekToEndOfFile()
        }
        _kfLogSize = min(oldSize, 5_000_000)
        _kfLogHandle?.write(d)
        _kfLogSize += d.count
        return
    }
    if _kfLogSize > 5_000_000 {
        try? _kfLogHandle?.truncate(atOffset: 0)   // 超限:清空重写(诊断日志只关心最近的事)
        _kfLogSize = 0
    }
    _kfLogHandle?.seekToEndOfFile()
    _kfLogHandle?.write(d)
    _kfLogSize += d.count
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

        // CPU 自监控:每 5 秒记录进程 CPU% + 线程数 + effect 数 + 当前状态,定位唤醒卡死
        startWatchdog()
    }

    /// 看门狗:定期记录资源占用。卡死时日志里有铁证。
    private func startWatchdog() {
        let pid = ProcessInfo.processInfo.processIdentifier
        var highCpuStreak = 0
        var watchdogBusy = false   // 防重入:上一个 ps 没完成不 fork 新的
        Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in   // 15s:熔断需 3 连击=45s,5s 的 fork 唤醒太频(省电)
            guard let self = self else { return }
            guard !watchdogBusy else { return }   // 上一个 ps 还没完(系统高负载时 ps 会慢),跳过
            watchdogBusy = true
            // ps 在后台线程跑,不阻塞主线程(主线程阻塞 = 丢帧 = 卡顿加剧)
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.launchPath = "/bin/ps"
                task.arguments = ["-p", "\(pid)", "-o", "%cpu,rss"]
                let pipe = Pipe()
                task.standardOutput = pipe
                do { try task.run() } catch { watchdogBusy = false; return }
                // 超时保护:3 秒 ps 不返回就强杀(唤醒后系统高负载时 ps 可能卡)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0) {
                    if task.isRunning { task.terminate() }
                }
                task.waitUntilExit()
                guard task.terminationStatus == 0 else {
                    DispatchQueue.main.async { watchdogBusy = false }
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                var cpu: Double = 0
                var rss: Double = 0
                if let s = String(data: data, encoding: .utf8) {
                    let lines = s.split(separator: "\n")
                    if lines.count > 1 {
                        let parts = lines[1].split(whereSeparator: { $0.isWhitespace }).filter { !$0.isEmpty }
                        if parts.count >= 2 {
                            cpu = Double(parts[0]) ?? 0
                            rss = (Double(parts[1]) ?? 0) / 1024
                        }
                    }
                }
                // 回主线程记日志 + 检查熔断
                DispatchQueue.main.async {
                    watchdogBusy = false
                    let state = self.petController?.behavior.currentStateForLog() ?? "?"
                    let onWin = self.petController?.behavior.onWindow ?? false
                    // 自己进程的窗口数(泄漏监控:CGWindowList 过滤本 pid)
                    var winCount = -1
                    if let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
                        let myPID = ProcessInfo.processInfo.processIdentifier
                        winCount = infos.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == myPID }.count
                    }
                    kfLog("WATCHDOG cpu=\(String(format: "%.1f", cpu))% rss=\(String(format: "%.0f", rss))MB effects=\(Effect.active.count) windows=\(winCount) state=\(state) onWindow=\(onWin)")
                    if cpu > 40 {
                        highCpuStreak += 1
                        if highCpuStreak >= 3 {
                            kfLog("⚠️ CIRCUIT BREAKER: cpu=\(cpu)% 持续 \(highCpuStreak*15)s → 熔断重置")
                            self.emergencyReset()
                            highCpuStreak = 0
                        }
                    } else {
                        highCpuStreak = 0
                    }
                }
            }
        }
    }

    /// 熔断重置:停一切 + 清一切 + 干净重启。不管根因是什么,保证不卡死系统。
    private func emergencyReset() {
        // 停所有 Behavior 定时器 + 代际 bump
        petController?.behavior.suspend()
        // 停所有常驻 timer
        petController?.petView.suspendAnimation()
        poopCtl?.suspend()
        branchCtl?.suspend()
        // 撤所有特效窗口
        Effects.clearAll()
        // 清裂纹 layer(保留裂纹数据,只移除 layer 树防 GPU 合成开销)
        crackCtl?.purgeLayers()
        // 短暂等待后干净恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.petController?.petView.resumeAnimation()
            self.poopCtl?.resume()
            self.branchCtl?.resume()
            self.petController?.behavior.forceIdle()
            kfLog("CIRCUIT BREAKER: 重置完成,恢复运行")
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
        button?.toolTip = Language.t("statusitem.tooltip")
        button?.setAccessibilityLabel(Language.t("ax.tooltip"))

        let menu = NSMenu()
        menu.addItem(item(Language.t("menu.callOver"), action: #selector(callOver)))
        menu.addItem(item(Language.t("menu.fish"), action: #selector(doFish)))
        menu.addItem(item(Language.t("menu.sing"), action: #selector(doSing)))
        menu.addItem(item(Language.t("menu.perch"), action: #selector(doPerch)))
        menu.addItem(item(Language.t("menu.peck"), action: #selector(doPeck)))
        menu.addItem(item(Language.t("menu.toggleVisibility"), action: #selector(toggleVisibility)))
        menu.addItem(.separator())
        soundMenuItem = item(Language.t("menu.soundOn"), action: #selector(toggleSound))
        menu.addItem(soundMenuItem)
        autoLoginMenuItem = item(Language.t("menu.autoLogin"), action: #selector(toggleAutoLogin))
        menu.addItem(autoLoginMenuItem)
        menu.addItem(item(Language.t("menu.repairScreen"), action: #selector(repairScreen)))
        menu.addItem(item(Language.t("menu.settings"), action: #selector(showSettings)))
        // 语言子菜单:跟随系统 / 中文 / English(切换即时生效)
        let langItem = NSMenuItem(title: Language.t("menu.language"), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for (c, key) in [(Language.Choice.system, "menu.lang.system"),
                         (Language.Choice.zh, "menu.lang.zh"),
                         (Language.Choice.en, "menu.lang.en")] {
            let mi = item(Language.t(key), action: #selector(switchLanguage(_:)))
            mi.representedObject = c.rawValue
            mi.state = (Language.choice == c) ? .on : .off
            langMenu.addItem(mi)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)
        menu.addItem(.separator())
        menu.addItem(item(Language.t("menu.about"), action: #selector(showAbout)))
        menu.addItem(item(Language.t("menu.quit"), action: #selector(quit)))
        statusItem.menu = menu
        refreshMenuState()
    }

    /// 切语言:改设置 → 重建菜单;设置窗口关掉,下次打开按新语言重建
    @objc private func switchLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let c = Language.Choice(rawValue: raw), c != Language.choice else { return }
        Language.choice = c
        configureStatusItem()
        settingsWindowController?.closeWindow()
        settingsWindowController = nil
    }

    private func refreshMenuState() {
        soundMenuItem.title = Language.t(Settings.shared.soundOn ? "menu.soundOn" : "menu.soundOff")
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
        // 鸟隐藏着(fallAway 挂起了 60fps)不恢复定时器——否则锁屏一晚空转 CPU
        if petController?.behavior.isVisible == true {
            petController?.petView.resumeAnimation()
            poopCtl?.resume()
            branchCtl?.resume()
        }
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
        // 注意:不 Effects.clearAll()——锁屏屏幕黑,特效看不见;解锁后会自然到期消失。
        // 但如果锁屏很久(系统没真睡,只是锁屏),Effects 的 asyncAfter close 会继续清。
    }

    /// 解锁:鸟赖床 2–4 秒后醒来。
    @objc private func screenUnlocked() {
        kfLog("screenUnlocked effects=\(Effect.active.count)")
        if petController?.behavior.isVisible == true {   // 隐藏鸟不空转
            petController?.petView.resumeAnimation()
            poopCtl?.resume()
            branchCtl?.resume()
        }
        petController?.behavior.wakeFromUserAbsence()
    }

    /// 设置变化:应用到各子系统 + 同步菜单
    @objc private func settingsChanged(_ n: Notification) {
        let key = (n.userInfo?["key"] as? String) ?? ""
        switch key {
        case "kingfisher.settings.soundOn":
            SpriteLibrary.shared.soundOn = Settings.shared.soundOn
            soundMenuItem.title = Language.t(Settings.shared.soundOn ? "menu.soundOn" : "menu.soundOff")
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
        alert.messageText = Language.t("about.title")
        alert.informativeText = Language.t("about.body")
        alert.alertStyle = .informational
        alert.addButton(withTitle: Language.t("about.github"))
        alert.addButton(withTitle: Language.t("about.ok"))
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
