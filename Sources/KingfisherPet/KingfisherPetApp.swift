import AppKit
import ServiceManagement
import Foundation

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

    private static let kSound = "kingfisher.soundOn"
    private static let kAutoLogin = "kingfisher.autoLogin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 加载资源
        _ = SpriteLibrary.shared
        // 恢复设置
        let d = UserDefaults.standard
        SpriteLibrary.shared.soundOn = (d.object(forKey: Self.kSound) as? Bool) ?? true
        if d.bool(forKey: Self.kAutoLogin) {
            // 重新注册(更新版后系统可能要求重新允许)
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
            crackCtl = CrackController()
            crackCtl.start()
            petController.behavior.crack = crackCtl
        }

        if ProcessInfo.processInfo.environment["KF_SNAPSHOT"] != nil {
            writeDebugSnapshot()
        }
        if ProcessInfo.processInfo.environment["KF_DEMO"] != nil {
            // 调试:2.5s 后自动啄一下,便于截图看裂纹
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.petController.behavior.startPeck()
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
        button?.toolTip = "翡 · 翠鸟桌面宠物"

        let menu = NSMenu()
        menu.addItem(item("召唤过来", action: #selector(callOver)))
        menu.addItem(item("去抓条鱼", action: #selector(doFish)))
        menu.addItem(item("唱一个", action: #selector(doSing)))
        menu.addItem(item("停到窗口上", action: #selector(doPerch)))
        menu.addItem(item("啄一下", action: #selector(doPeck)))
        menu.addItem(item("显示 / 隐藏", action: #selector(toggleVisibility)))
        menu.addItem(.separator())
        soundMenuItem = item("啾鸣声:开", action: #selector(toggleSound))
        menu.addItem(soundMenuItem)
        autoLoginMenuItem = item("开机自启", action: #selector(toggleAutoLogin))
        menu.addItem(autoLoginMenuItem)
        menu.addItem(item("修复屏幕", action: #selector(repairScreen)))
        menu.addItem(.separator())
        menu.addItem(item("关于 翡", action: #selector(showAbout)))
        menu.addItem(item("退出 翡", action: #selector(quit)))
        statusItem.menu = menu
        refreshMenuState()
    }

    private func refreshMenuState() {
        soundMenuItem.title = SpriteLibrary.shared.soundOn ? "啾鸣声:开" : "啾鸣声:关"
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
        SpriteLibrary.shared.soundOn.toggle()
        UserDefaults.standard.set(SpriteLibrary.shared.soundOn, forKey: Self.kSound)
        soundMenuItem.title = SpriteLibrary.shared.soundOn ? "啾鸣声:开" : "啾鸣声:关"
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
        alert.messageText = "翡 · 翠鸟桌面宠物"
        alert.informativeText = "一只住在你 Mac 菜单栏的翠鸟。\n\n点击:啾一声卖萌\n拖拽:换位置\n它会自己走动、飞行、打盹,还会俯冲捕鱼、鸣唱、探头张望、晒太阳。\n显示时破壳而出,隐藏时死掉从天上掉下来。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        if let img = SpriteLibrary.shared.frame("idle_0")?.image {
            alert.icon = img
        }
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
