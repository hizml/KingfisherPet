import AppKit
import Foundation

/// 全局设置单例:活跃度 / 动画速度 / 声音 / 主题。
/// 持久化到 UserDefaults;变化时通知所有监听者(用 NotificationCenter,因为监听者分散)。
final class Settings {

    static let shared = Settings()

    /// 设置变化通知(统一用这个,userInfo["key"] = 改变的字段名)
    static let didChangeNotification = Notification.Name("kingfisher.settings.didChange")

    // MARK: - 字段
    /// 活跃度 0(几乎不动)…1(活跃),默认 0.5
    var activity: Double {
        get { Defaults.double(forKey: K.activity, default: 0.5) }
        set { clampAndSet(K.activity, newValue, lo: 0, hi: 1) }
    }
    /// 动画速度 0.5…1.5,默认 1.0
    var speed: Double {
        get { Defaults.double(forKey: K.speed, default: 1.0) }
        set { clampAndSet(K.speed, newValue, lo: 0.5, hi: 1.5) }
    }
    /// 声音开关
    var soundOn: Bool {
        get { Defaults.bool(forKey: K.soundOn, default: true) }
        set { set(K.soundOn, newValue) }
    }
    /// 主题 id(对应 SpriteLibrary.themes)
    var theme: String {
        get { Defaults.string(forKey: K.theme, default: "flat") }
        set { set(K.theme, newValue) }
    }

    private func clampAndSet(_ key: String, _ value: Double, lo: Double, hi: Double) {
        set(key, min(max(value, lo), hi))
    }
    private func set(_ key: String, _ value: Double) {
        UserDefaults.standard.set(value, forKey: key)
        notify(key: key)
    }
    private func set(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
        notify(key: key)
    }
    private func set(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: key)
        notify(key: key)
    }
    private func notify(key: String) {
        NotificationCenter.default.post(name: Self.didChangeNotification,
                                        object: nil, userInfo: ["key": key])
    }

    private enum K {
        static let activity = "kingfisher.settings.activity"
        static let speed    = "kingfisher.settings.speed"
        static let soundOn  = "kingfisher.settings.soundOn"
        static let theme    = "kingfisher.settings.theme"
    }
    private enum Defaults {
        static func double(forKey key: String, default def: Double) -> Double {
            let d = UserDefaults.standard
            return d.object(forKey: key) != nil ? d.double(forKey: key) : def
        }
        static func bool(forKey key: String, default def: Bool) -> Bool {
            let d = UserDefaults.standard
            return d.object(forKey: key) != nil ? d.bool(forKey: key) : def
        }
        static func string(forKey key: String, default def: String) -> String {
            UserDefaults.standard.string(forKey: key) ?? def
        }
    }
}

// MARK: - 设置窗口

/// 独立设置窗口(NSWindow + 纯 AppKit 控件,实时生效)。
/// 活跃度/速度滑块、声音开关、主题下拉。
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private weak var activitySlider: NSSlider?
    private weak var activityLabel: NSTextField?
    private weak var speedSlider: NSSlider?
    private weak var speedLabel: NSTextField?
    private weak var soundButton: NSButton?
    private weak var themePopup: NSPopUpButton?

    func show() {
        if window == nil { buildWindow() }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        // 设置窗口需要 app 能成为 key(我们是 accessory policy,临时激活一下)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 语言切换时外部调:关掉窗口(isReleasedWhenClosed=false),下次 show 按新语言重建
    func closeWindow() {
        window?.orderOut(nil)
    }

    private func buildWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = Language.t("settings.title")
        w.titlebarAppearsTransparent = false
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.isMovableByWindowBackground = true
        let s = Settings.shared

        // 根视图:垂直 stack
        let root = NSView(frame: w.contentView!.bounds)
        root.autoresizingMask = [.width, .height]

        let margin: CGFloat = 20
        var y = root.bounds.height - margin

        // 主题
        y -= 18
        let themeTitle = label(Language.t("settings.theme"))
        place(themeTitle, root, top: &y, margin: margin)
        y -= 26
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for (id, name) in SpriteLibrary.themes {
            popup.addItem(withTitle: name)
            popup.lastItem?.representedObject = id
            if id == s.theme { popup.select(popup.lastItem) }
        }
        popup.target = self
        popup.action = #selector(themeChanged(_:))
        popup.frame = NSRect(x: margin, y: y, width: root.bounds.width - margin * 2, height: 26)
        popup.autoresizingMask = [.width]
        root.addSubview(popup)
        themePopup = popup
        y -= 22

        // 分隔
        y = separator(root, top: y, margin: margin)

        // 活跃度
        y -= 18
        place(label(Language.t("settings.activity")), root, top: &y, margin: margin)
        y -= 4
        let actRow = NSView(frame: NSRect(x: margin, y: y - 22, width: root.bounds.width - margin * 2, height: 22))
        let actSlider = NSSlider(value: Double(s.activity), minValue: 0, maxValue: 1,
                                 target: self, action: #selector(activityChanged(_:)))
        actSlider.setAccessibilityLabel("活跃度")
        actSlider.frame = NSRect(x: 0, y: 0, width: actRow.bounds.width - 70, height: 22)
        actSlider.autoresizingMask = [.width]
        let actLabel = label(activityText(s.activity))
        actLabel.alignment = .right
        actLabel.frame = NSRect(x: actRow.bounds.width - 60, y: 2, width: 60, height: 18)
        actLabel.autoresizingMask = [.minXMargin]
        actRow.addSubview(actSlider)
        actRow.addSubview(actLabel)
        actRow.autoresizingMask = [.width]
        root.addSubview(actRow)
        activitySlider = actSlider
        activityLabel = actLabel
        y -= 28

        // 动画速度
        y -= 14
        place(label(Language.t("settings.speed")), root, top: &y, margin: margin)
        y -= 4
        let spdRow = NSView(frame: NSRect(x: margin, y: y - 22, width: root.bounds.width - margin * 2, height: 22))
        let spdSlider = NSSlider(value: Double(s.speed), minValue: 0.5, maxValue: 1.5,
                                 target: self, action: #selector(speedChanged(_:)))
        spdSlider.setAccessibilityLabel("动画速度")
        spdSlider.frame = NSRect(x: 0, y: 0, width: spdRow.bounds.width - 70, height: 22)
        spdSlider.autoresizingMask = [.width]
        let spdLabel = label(String(format: "%.1f×", s.speed))
        spdLabel.alignment = .right
        spdLabel.frame = NSRect(x: spdRow.bounds.width - 60, y: 2, width: 60, height: 18)
        spdLabel.autoresizingMask = [.minXMargin]
        spdRow.addSubview(spdSlider)
        spdRow.addSubview(spdLabel)
        spdRow.autoresizingMask = [.width]
        root.addSubview(spdRow)
        speedSlider = spdSlider
        speedLabel = spdLabel
        y -= 28

        // 分隔
        y = separator(root, top: y, margin: margin)

        // 声音
        y -= 22
        let sndBtn = NSButton(checkboxWithTitle: Language.t("settings.sound"),
                              target: self, action: #selector(soundToggled(_:)))
        sndBtn.state = s.soundOn ? .on : .off
        sndBtn.frame = NSRect(x: margin, y: y, width: root.bounds.width - margin * 2, height: 22)
        sndBtn.autoresizingMask = [.width]
        root.addSubview(sndBtn)
        soundButton = sndBtn

        w.contentView = root
        window = w

        // 监听外部变化(如菜单改了声音),同步控件
        NotificationCenter.default.addObserver(self, selector: #selector(externalChange(_:)),
                                               name: Settings.didChangeNotification, object: nil)
    }

    // MARK: - 控件回调
    @objc private func themeChanged(_ s: NSPopUpButton) {
        if let id = s.selectedItem?.representedObject as? String {
            Settings.shared.theme = id
        }
    }
    @objc private func activityChanged(_ s: NSSlider) {
        Settings.shared.activity = Double(s.doubleValue)
        activityLabel?.stringValue = activityText(Settings.shared.activity)
    }
    @objc private func speedChanged(_ s: NSSlider) {
        Settings.shared.speed = Double(s.doubleValue)
        speedLabel?.stringValue = String(format: "%.1f×", Settings.shared.speed)
    }
    @objc private func soundToggled(_ b: NSButton) {
        Settings.shared.soundOn = (b.state == .on)
    }

    /// 外部改了设置:同步本窗口控件(避免 UI 与状态不同步)
    @objc private func externalChange(_ n: Notification) {
        let key = (n.userInfo?["key"] as? String) ?? ""
        let s = Settings.shared
        switch key {
        case "kingfisher.settings.activity":
            activitySlider?.doubleValue = Double(s.activity)
            activityLabel?.stringValue = activityText(s.activity)
        case "kingfisher.settings.speed":
            speedSlider?.doubleValue = Double(s.speed)
            speedLabel?.stringValue = String(format: "%.1f×", s.speed)
        case "kingfisher.settings.soundOn":
            soundButton?.state = s.soundOn ? .on : .off
        case "kingfisher.settings.theme":
            // 选中匹配项
            for item in themePopup?.itemArray ?? [] {
                if (item.representedObject as? String) == s.theme {
                    themePopup?.select(item)
                    break
                }
            }
        default: break
        }
    }

    // MARK: - 辅助
    private func label(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        f.textColor = .labelColor
        return f
    }
    private func place(_ view: NSTextField, _ inView: NSView, top y: inout CGFloat, margin: CGFloat) {
        view.sizeToFit()
        var f = view.frame
        f.origin = NSPoint(x: margin, y: y - f.height)
        view.frame = f
        inView.addSubview(view)
        y -= f.height
    }
    private func separator(_ inView: NSView, top y: CGFloat, margin: CGFloat) -> CGFloat {
        let line = NSBox(frame: NSRect(x: margin, y: y - 10, width: inView.bounds.width - margin * 2, height: 1))
        line.boxType = .separator
        line.autoresizingMask = [.width]
        inView.addSubview(line)
        return y - 10
    }
    private func activityText(_ a: Double) -> String {
        if a < 0.34 { return Language.t("settings.activity.low") }
        if a > 0.66 { return Language.t("settings.activity.high") }
        return Language.t("settings.activity.mid")
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
