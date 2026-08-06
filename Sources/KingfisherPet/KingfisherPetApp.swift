import AppKit

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 加载资源
        _ = SpriteLibrary.shared

        // 菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()

        // 宠物
        petController = PetWindowController()
        petController.show()

        if ProcessInfo.processInfo.environment["KF_SNAPSHOT"] != nil {
            writeDebugSnapshot()
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
        menu.addItem(item("显示 / 隐藏", action: #selector(toggleVisibility)))
        menu.addItem(.separator())
        soundMenuItem = item("啾鸣声:开", action: #selector(toggleSound))
        menu.addItem(soundMenuItem)
        menu.addItem(.separator())
        menu.addItem(item("关于 翡", action: #selector(showAbout)))
        menu.addItem(item("退出 翡", action: #selector(quit)))
        statusItem.menu = menu
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

    @objc private func toggleVisibility() {
        petController.behavior.toggleVisibility()
    }

    @objc private func toggleSound() {
        SpriteLibrary.shared.soundOn.toggle()
        soundMenuItem.title = SpriteLibrary.shared.soundOn ? "啾鸣声:开" : "啾鸣声:关"
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
