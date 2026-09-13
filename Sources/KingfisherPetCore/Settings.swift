import AppKit
import Foundation

/// 全局设置单例:活跃度 / 动画速度 / 声音 / 主题。
/// 持久化到 UserDefaults;变化时通知所有监听者(用 NotificationCenter,因为监听者分散)。
final public class Settings {

    public static let shared = Settings()

    /// 设置变化通知(统一用这个,userInfo["key"] = 改变的字段名)
    static let didChangeNotification = Notification.Name("kingfisher.settings.didChange")

    // MARK: - 字段
    // 读写都过 clamp + NaN 防护(排查同类抓到:此前只有写入 clamp,getter 裸读——
    // 脏 plist/手工改 defaults 的 NaN 会灌进 think 的随机区间,行为链静默瘫痪,
    // Windows 侧 B5 已修,Mac 孪生漏修)
    public var activity: Double {
        get { Self.clamp(Defaults.double(forKey: K.activity, default: 0.5), lo: 0, hi: 1, fallback: 0.5) }
        set { clampAndSet(K.activity, newValue, lo: 0, hi: 1, fallback: 0.5) }
    }
    /// 动画速度 0.5…1.5,默认 1.0
    public var speed: Double {
        get { Self.clamp(Defaults.double(forKey: K.speed, default: 1.0), lo: 0.5, hi: 1.5, fallback: 1.0) }
        set { clampAndSet(K.speed, newValue, lo: 0.5, hi: 1.5, fallback: 1.0) }
    }
    /// 声音开关
    var soundOn: Bool {
        get { Defaults.bool(forKey: K.soundOn, default: true) }
        set { set(K.soundOn, newValue) }
    }
    /// 自发啄屏幕(菜单手动"啄一下"不受限;关掉后鸟不再自己啄裂屏幕)
    var peckScreen: Bool {
        get { Defaults.bool(forKey: K.peckScreen, default: true) }
        set { set(K.peckScreen, newValue) }
    }
    /// 主题 id(对应 SpriteLibrary.themes)
    var theme: String {
        get { Defaults.string(forKey: K.theme, default: "flat") }
        set { set(K.theme, newValue) }
    }

    // MARK: - 天气联动(v1.5.0;默认关 = 明示纪律:开启才发首个网络请求)
    var weatherEnabled: Bool {
        get { Defaults.bool(forKey: K.weatherEnabled, default: false) }
        set { set(K.weatherEnabled, newValue) }
    }
    /// 城市名;空 = IP 粗定位
    var weatherCity: String {
        get { Defaults.string(forKey: K.weatherCity, default: "") }
        set { set(K.weatherCity, newValue) }
    }
    /// 数据源:open-meteo(默认免 key)/ qweather(和风)
    var weatherProvider: String {
        get { let p = Defaults.string(forKey: K.weatherProvider, default: "open-meteo")
              return p == "qweather" ? "qweather" : "open-meteo" }   // 脏值回默认
        set { set(K.weatherProvider, newValue == "qweather" ? "qweather" : "open-meteo") }
    }
    /// 和风 API Key(用户自己的免费 key,本地明文,风险可接受;迁 Keychain 不在本批)
    var weatherKey: String {
        get { Defaults.string(forKey: K.weatherKey, default: "") }
        set { set(K.weatherKey, newValue) }
    }
    /// 和风 API Host(选填;以控制台分配的专属 Host 为准,默认 devapi)
    var weatherHost: String {
        get { Defaults.string(forKey: K.weatherHost, default: "devapi.qweather.com") }
        set { set(K.weatherHost, newValue) }
    }

    /// clamp + NaN/Inf 防护:畸形值(外部数据/脏存储)一律回默认,不进存储不进行为链
    private static func clamp(_ v: Double, lo: Double, hi: Double, fallback: Double) -> Double {
        v.isFinite ? min(max(v, lo), hi) : fallback
    }
    private func clampAndSet(_ key: String, _ value: Double, lo: Double, hi: Double, fallback: Double) {
        set(key, Self.clamp(value, lo: lo, hi: hi, fallback: fallback))
    }
    private func set(_ key: String, _ value: Double) {
        UserDefaults.standard.set(value, forKey: key)
        notify(key: key)
    }
    private func set(_ key: String, _ value: Bool) {
        // 评审 A19:同值不写不通知——设置窗失焦即提交,重复提交会触发天气服务重启(无谓网络请求)
        guard UserDefaults.standard.bool(forKey: key) != value || UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(value, forKey: key)
        notify(key: key)
    }
    private func set(_ key: String, _ value: String) {
        guard UserDefaults.standard.string(forKey: key) != value else { return }
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
        static let peckScreen = "kingfisher.settings.peckScreen"
        static let theme    = "kingfisher.settings.theme"
        static let weatherEnabled = "kingfisher.settings.weatherEnabled"
        static let weatherCity    = "kingfisher.settings.weatherCity"
        static let weatherProvider = "kingfisher.settings.weatherProvider"
        static let weatherKey     = "kingfisher.settings.weatherKey"
        static let weatherHost    = "kingfisher.settings.weatherHost"
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
/// 活跃度/速度滑块、声音开关、主题下拉、天气联动区。
final class SettingsWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {

    private var window: NSWindow?
    /// 观察者只注册一次:换数据源会复用控制器重建窗口,重复 add 会收到重复回调
    private var observersInstalled = false
    private weak var activitySlider: NSSlider?
    private weak var activityLabel: NSTextField?
    private weak var speedSlider: NSSlider?
    private weak var speedLabel: NSTextField?
    private weak var soundButton: NSButton?
    private weak var peckButton: NSButton?
    private weak var themePopup: NSPopUpButton?
    // 天气区(v1.5.0)
    private weak var weatherButton: NSButton?
    private weak var weatherStatusLabel: NSTextField?

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
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 308),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = Language.t("settings.title")
        w.titlebarAppearsTransparent = false
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.isMovableByWindowBackground = true
        let s = Settings.shared

        // 根视图:垂直 stack
        // 宽高钉死与窗口 contentRect 一致:实测 w.contentView!.bounds 曾返回
        // 640×560(2×backing 尺寸),按它布局导致内容 600 宽、横向可拖(v1.4.51 宽度问题)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 308))
        root.autoresizingMask = [.width]

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

        // 啄屏幕开关(自发行为;关掉后不再自己啄裂屏幕,免得频繁"修复屏幕")
        y -= 22
        let peckBtn = NSButton(checkboxWithTitle: Language.t("settings.peck"),
                               target: self, action: #selector(peckToggled(_:)))
        peckBtn.state = s.peckScreen ? .on : .off
        peckBtn.frame = NSRect(x: margin, y: y, width: root.bounds.width - margin * 2, height: 22)
        peckBtn.autoresizingMask = [.width]
        root.addSubview(peckBtn)
        peckButton = peckBtn

        // ── 天气联动区(v1.5.0;默认关,开启才发首个请求——文案明示网络行为)──
        y = separator(root, top: y, margin: margin)
        y -= 20
        place(label(Language.t("settings.weather")), root, top: &y, margin: margin)
        y -= 24
        let wxBtn = NSButton(checkboxWithTitle: Language.t("settings.weather.enable"),
                             target: self, action: #selector(weatherToggled(_:)))
        wxBtn.state = s.weatherEnabled ? .on : .off
        wxBtn.frame = NSRect(x: margin, y: y, width: root.bounds.width - margin * 2, height: 22)
        wxBtn.autoresizingMask = [.width]
        root.addSubview(wxBtn)
        weatherButton = wxBtn
        // 明示文案(小字两行)
        y -= 30
        let note = NSTextField(wrappingLabelWithString: Language.t("settings.weather.note"))
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: margin, y: y - 4, width: root.bounds.width - margin * 2, height: 30)
        note.autoresizingMask = [.width]
        root.addSubview(note)
        // 城市
        y -= 28
        // 标签列宽:按天气四行标签实际最宽动态取(「和风 API Key」≈71pt、en「QWeather API Key」≈100pt)。
        // 之前钉死 56:输入框左缘正好压在 Key/Host 标签文字上(截图实测的"文字遮挡")
        let wxTitleKeys = ["settings.weather.city", "settings.weather.provider",
                           "settings.weather.key", "settings.weather.host"]
        let maxTW = wxTitleKeys.map {
            (Language.t($0) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
        }.max() ?? 56
        let labelCol = min(124, max(56, ceil(maxTW) + 12))
        let cityTitle = label(Language.t("settings.weather.city"))
        cityTitle.font = NSFont.systemFont(ofSize: 12)
        cityTitle.sizeToFit()
        cityTitle.frame.origin = NSPoint(x: margin, y: y)
        root.addSubview(cityTitle)
        let cityField = NSTextField()
        cityField.placeholderString = Language.t("settings.weather.cityPlaceholder")
        cityField.stringValue = s.weatherCity
        cityField.delegate = self
        cityField.font = NSFont.systemFont(ofSize: 12)
        cityField.frame = NSRect(x: margin + labelCol, y: y - 2, width: root.bounds.width - margin * 2 - labelCol, height: 24)
        cityField.autoresizingMask = [.width]
        cityField.identifier = NSUserInterfaceItemIdentifier("wx.city")
        root.addSubview(cityField)
        // 数据源(选和风时下方多出 Key/Host 两行:重建窗口换布局,比动态增删行稳)
        y -= 30
        let provTitle = label(Language.t("settings.weather.provider"))
        provTitle.font = NSFont.systemFont(ofSize: 12)
        provTitle.sizeToFit()
        provTitle.frame.origin = NSPoint(x: margin, y: y)
        root.addSubview(provTitle)
        let provPopup = NSPopUpButton(frame: NSRect(x: margin + labelCol, y: y - 4,
                                                    width: root.bounds.width - margin * 2 - labelCol, height: 26),
                                      pullsDown: false)
        provPopup.addItem(withTitle: "Open-Meteo")
        provPopup.lastItem?.representedObject = "open-meteo"
        provPopup.addItem(withTitle: "和风天气")
        provPopup.lastItem?.representedObject = "qweather"
        for it in provPopup.itemArray where (it.representedObject as? String) == s.weatherProvider {
            provPopup.select(it)
        }
        provPopup.target = self
        provPopup.action = #selector(weatherProviderChanged(_:))
        provPopup.autoresizingMask = [.width]
        root.addSubview(provPopup)
        // 和风专属两行:Key(密码框)+ Host
        if s.weatherProvider == "qweather" {
            y -= 32
            let keyTitle = label(Language.t("settings.weather.key"))
            keyTitle.font = NSFont.systemFont(ofSize: 12)
            keyTitle.sizeToFit()
            keyTitle.frame.origin = NSPoint(x: margin, y: y)
            root.addSubview(keyTitle)
            let keyField = NSSecureTextField()
            keyField.stringValue = s.weatherKey
            keyField.delegate = self
            keyField.font = NSFont.systemFont(ofSize: 12)
            keyField.frame = NSRect(x: margin + labelCol, y: y - 2, width: root.bounds.width - margin * 2 - labelCol, height: 24)
            keyField.autoresizingMask = [.width]
            keyField.identifier = NSUserInterfaceItemIdentifier("wx.key")
            root.addSubview(keyField)
            y -= 32
            let hostTitle = label(Language.t("settings.weather.host"))
            hostTitle.font = NSFont.systemFont(ofSize: 12)
            hostTitle.sizeToFit()
            hostTitle.frame.origin = NSPoint(x: margin, y: y)
            root.addSubview(hostTitle)
            let hostField = NSTextField()
            hostField.placeholderString = "devapi.qweather.com"
            hostField.stringValue = s.weatherHost
            hostField.delegate = self
            hostField.font = NSFont.systemFont(ofSize: 12)
            hostField.frame = NSRect(x: margin + labelCol, y: y - 2, width: root.bounds.width - margin * 2 - labelCol, height: 24)
            hostField.autoresizingMask = [.width]
            hostField.identifier = NSUserInterfaceItemIdentifier("wx.host")
            root.addSubview(hostField)
        }
        // 状态行(状态可见纪律:失败/正常/关闭都在这标)。
        // 宽度钉满可用区:此前按内容 sizeToFit,天气状态异步变化时 stringValue
        // 直接塞进旧窄 frame → 文字被裁(切数据源后状态变长必现);钉宽+截尾省略号
        y -= 26
        let status = NSTextField(labelWithString: weatherStatusText())
        status.font = NSFont.systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.frame = NSRect(x: margin, y: y,
                              width: root.bounds.width - margin * 2, height: 16)
        root.addSubview(status)
        weatherStatusLabel = status

        // Y 轴滚动(几何全部钉常量,不从 contentView.bounds 取值——它实测返回过
        // 640×560 的 2× 假值,前两轮滚动全毁在它手里):
        // ①内容高度按真实布局收口;②frame 变高后平移全部子视图(坐标系不会自动重映射);
        // ③只开纵向滚动,内容宽钉 320;④非 flipped document 默认显示底部,显式滚回顶部。
        // v1.5.0:窗口高度自适应内容(天气区进设置窗后内容 500+,固定 308 会把新功能
        // 藏在折叠线下);内容超过 760 才回落到滚动。
        let baseH: CGFloat = 308
        // +18 底部余量:原式内容超高时状态行底边恰好压在 documentView 的 y=0 上,
        // 一点呼吸空间没有(截图实测:状态行「状态:天气…」贴底被裁)
        let contentH = max((baseH - margin) - y + margin + 18, baseH)
        let viewH = min(contentH, 760)
        let grow = contentH - baseH
        if grow != 0 { for sv in root.subviews { sv.frame.origin.y += grow } }
        root.frame = NSRect(x: 0, y: 0, width: 320, height: contentH)
        let scroll = NSScrollView()
        scroll.frame = NSRect(x: 0, y: 0, width: 320, height: viewH)
        scroll.hasVerticalScroller = viewH < contentH
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.documentView = root
        scroll.autoresizingMask = [.width, .height]
        w.contentView = scroll
        w.setContentSize(NSSize(width: 320, height: viewH))
        if viewH < contentH { scroll.contentView.scroll(NSPoint(x: 0, y: max(0, contentH - viewH))) }   // 初始置顶
        kfLog("settings 几何: root=\(Int(root.bounds.width))x\(Int(root.bounds.height)) view=320x\(Int(viewH)) 最后控件top=\(Int(y + grow))")
        window = w

        // 监听外部变化(如菜单改了声音),同步控件(只装一次:重建窗口不复装)
        if !observersInstalled {
            observersInstalled = true
            NotificationCenter.default.addObserver(self, selector: #selector(externalChange(_:)),
                                                   name: Settings.didChangeNotification, object: nil)
            // 天气快照/状态更新 → 刷新状态行(状态可见)
            NotificationCenter.default.addObserver(self, selector: #selector(weatherStatusChanged),
                                                   name: WeatherService.didUpdate, object: nil)
        }
    }

    // MARK: - 文本框提交(回车/失焦时才写设置——避免逐键触发重启请求轰炸)
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField else { return }
        let s = Settings.shared
        switch tf.identifier?.rawValue {
        case "wx.city": s.weatherCity = tf.stringValue.trimmingCharacters(in: .whitespaces)
        case "wx.key": s.weatherKey = tf.stringValue.trimmingCharacters(in: .whitespaces)
        case "wx.host": s.weatherHost = tf.stringValue.trimmingCharacters(in: .whitespaces)
        default: break
        }
    }

    @objc private func weatherStatusChanged() {
        weatherStatusLabel?.stringValue = weatherStatusText()
    }

    private func weatherStatusText() -> String {
        switch WeatherService.shared.status {
        case .off: return String(format: Language.t("settings.weather.status"),
                                 Language.t("settings.weather.status.off"))
        case .ok: return String(format: Language.t("settings.weather.status"),
                                Language.t("settings.weather.status.ok"))
        case .unavailable: return String(format: Language.t("settings.weather.status"),
                                         Language.t("settings.weather.status.unavailable"))
        }
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
    @objc private func peckToggled(_ b: NSButton) {
        Settings.shared.peckScreen = (b.state == .on)
    }
    @objc private func weatherToggled(_ b: NSButton) {
        Settings.shared.weatherEnabled = (b.state == .on)
    }
    @objc private func weatherProviderChanged(_ p: NSPopUpButton) {
        guard let id = p.selectedItem?.representedObject as? String else { return }
        Settings.shared.weatherProvider = id
        // 换源要增删 Key/Host 行:关掉按新布局重建(内容少,重建最稳)
        closeWindow()
        self.window = nil
        show()
    }

    /// 外部改了设置:同步本窗口控件(避免 UI 与状态不同步)
    @objc private func externalChange(_ n: Notification) {
        let key = (n.userInfo?["key"] as? String) ?? ""
        let s = Settings.shared
        switch key {
        case "kingfisher.settings.activity":
            activitySlider?.doubleValue = Double(s.activity)
            activityLabel?.stringValue = activityText(s.activity)
        case "kingfisher.settings.peckScreen":
            peckButton?.state = s.peckScreen ? .on : .off
        case "kingfisher.settings.weatherEnabled":
            weatherButton?.state = s.weatherEnabled ? .on : .off
            weatherStatusLabel?.stringValue = weatherStatusText()
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
