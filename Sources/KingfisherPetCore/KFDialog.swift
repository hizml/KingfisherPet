import AppKit

/// 自绘小弹窗(项目红线「弹窗必须自绘」,替换原生 NSAlert runModal)。
/// 形态对齐 macOS NSAlert:左侧应用图标 + 右侧标题/正文,底部右对齐按钮排,
/// 主按钮(序号 0)在最右(macOS 规范:默认动作靠右、取消/稍后靠左)。
/// 模态语义:按钮点击 → onClose(序号);用户点关闭钮/Esc → onClose(-1)。
final class KFDialog: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var onClose: ((Int) -> Void)?
    private var closed = false

    private static var live: [KFDialog] = []   // 保活:闭包持有自己直到关闭

    static func show(title: String, message: String, buttons: [String],
                     width: CGFloat = 380, onClose: @escaping (Int) -> Void) {
        let d = KFDialog()
        d.build(title: title, message: message, buttons: buttons, width: width, onClose: onClose)
        live.append(d)
    }

    // 品牌青(主题色);dark 模式下提亮一档保持可读
    private static func primaryColor() -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.66, alpha: 1)
                : NSColor(calibratedRed: 0.055, green: 0.486, blue: 0.525, alpha: 1)
        }
    }

    /// 统一按钮工厂:主按钮青底白字,次按钮浅底细边框;均无系统 bezel/焦点环。
    private func makeButton(title raw: String, primary: Bool, tag: Int) -> NSButton {
        let b = NSButton(title: raw, target: self, action: #selector(tapped(_:)))
        b.tag = tag
        b.isBordered = false                  // 去系统 bezel(老板:UI 丑的根源)
        b.focusRingType = .none               // 自绘底色上系统焦点环会溢出成蓝框
        b.wantsLayer = true
        b.layer?.cornerRadius = 8
        b.font = .systemFont(ofSize: 13, weight: primary ? .semibold : .regular)
        if primary {
            b.layer?.backgroundColor = Self.primaryColor().cgColor
            b.contentTintColor = .white
        } else {
            let bg = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(calibratedWhite: 0.16, alpha: 1)
                    : NSColor(calibratedWhite: 0.95, alpha: 1)
            }
            b.layer?.backgroundColor = bg.cgColor
            b.layer?.borderWidth = 1
            b.layer?.borderColor = NSColor.separatorColor.cgColor
            b.contentTintColor = .labelColor
        }
        return b
    }

    private func build(title: String, message: String, buttons: [String],
                       width: CGFloat, onClose: @escaping (Int) -> Void) {
        self.onClose = onClose

        let m: CGFloat = 24                       // 左右边距
        let iconS: CGFloat = 48
        let textX = m + iconS + 16                // 文本块起点(图标右侧)
        let textW = width - textX - m

        let titleL = NSTextField(wrappingLabelWithString: title)
        titleL.font = .systemFont(ofSize: 14, weight: .semibold)
        titleL.preferredMaxLayoutWidth = textW
        titleL.lineBreakMode = .byCharWrapping    // 长串(路径/版本号)按字折行,不截断
        titleL.sizeToFit()

        let msgL = NSTextField(wrappingLabelWithString: message)
        msgL.font = .systemFont(ofSize: 12)
        msgL.textColor = .secondaryLabelColor
        msgL.preferredMaxLayoutWidth = textW
        msgL.lineBreakMode = .byCharWrapping      // DND 引导弹窗正文含完整 app 路径,按词折行必截断
        msgL.sizeToFit()

        let titleH = max(20, titleL.fittingSize.height)
        let msgH = max(18, msgL.fittingSize.height)
        let textBlockH = titleH + 6 + msgH
        let btnH: CGFloat = 32

        // 按钮:宽按文字自适应;渲染时主按钮(index 0)放最右,其余向左排
        var btnViews: [NSButton] = []
        var widths: [CGFloat] = []
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        for (i, raw) in buttons.enumerated() {
            let tw = (raw as NSString).size(withAttributes: attrs).width
            let w = max(88, ceil(tw) + 32)
            widths.append(w)
            btnViews.append(makeButton(title: raw, primary: i == 0, tag: 100 + i))
        }
        let gap: CGFloat = 10
        let rowW = widths.reduce(0, +) + gap * CGFloat(max(0, buttons.count - 1))

        let contentH = m + max(iconS, textBlockH) + 22 + btnH + 22
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: contentH))

        // 图标垂直居中于文本块
        let iconTop = m + max(0, (textBlockH - iconS) / 2)
        let icon = NSImageView(frame: NSRect(x: m, y: contentH - iconTop - iconS, width: iconS, height: iconS))
        icon.image = NSApplication.shared.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        root.addSubview(icon)

        titleL.frame = CGRect(x: textX, y: contentH - m - titleH, width: textW, height: titleH)
        msgL.frame = CGRect(x: textX, y: contentH - m - titleH - 6 - msgH, width: textW, height: msgH)
        root.addSubview(titleL)
        root.addSubview(msgL)

        // 按钮行:右对齐;渲染顺序反转,主按钮(0)落在最右
        var x = width - m - rowW
        for i in 0..<btnViews.count {
            let slot = btnViews.count - 1 - i
            btnViews[slot].frame = NSRect(x: x, y: 22, width: widths[slot], height: btnH)
            root.addSubview(btnViews[slot])
            x += widths[slot] + gap
        }

        let w = NSWindow(contentRect: root.bounds,
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = ""
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = root
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    @objc private func tapped(_ b: NSButton) {
        finish(b.tag - 100)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { true }

    func windowWillClose(_ notification: Notification) {
        finish(-1)
    }

    private func finish(_ idx: Int) {
        guard !closed else { return }
        closed = true
        window?.orderOut(nil)
        Self.live.removeAll { $0 === self }
        onClose?(idx)
    }
}
