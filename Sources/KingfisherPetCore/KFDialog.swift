import AppKit

/// 自绘小弹窗(v1.6.0 评审 A6:项目红线「弹窗必须自绘」,替换原生 NSAlert runModal)。
/// 形态对齐 Windows 端 update.html:标题+正文+右对齐按钮排,主按钮青底白字。
/// 模态语义:按钮点击 → onClose(序号);用户点关闭钮 → onClose(-1)。窗口自管理生命周期。
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

    private func build(title: String, message: String, buttons: [String],
                       width: CGFloat, onClose: @escaping (Int) -> Void) {
        self.onClose = onClose

        let titleL = NSTextField(wrappingLabelWithString: title)
        titleL.font = .systemFont(ofSize: 14, weight: .semibold)
        let msgL = NSTextField(wrappingLabelWithString: message)
        msgL.font = .systemFont(ofSize: 12)
        msgL.textColor = .secondaryLabelColor

        let btnRow = NSView()
        let btnW: CGFloat = 96, btnH: CGFloat = 30
        for (i, raw) in buttons.enumerated() {
            let b = NSButton(title: raw, target: self, action: #selector(tapped(_:)))
            b.tag = 100 + i
            b.bezelStyle = .rounded
            b.font = .systemFont(ofSize: 12, weight: .medium)
            b.frame = NSRect(x: CGFloat(i) * (btnW + 8), y: 0, width: btnW, height: btnH)
            if i == 0 {   // 主按钮:青底白字
                b.wantsLayer = true
                b.layer?.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.486, blue: 0.525, alpha: 1).cgColor
                b.layer?.cornerRadius = 6
                b.contentTintColor = .white
                b.isBordered = false
            }
            btnRow.addSubview(b)
        }
        let rowW = CGFloat(buttons.count) * btnW + CGFloat(max(0, buttons.count - 1)) * 8
        btnRow.frame = NSRect(x: 0, y: 0, width: rowW, height: btnH)

        // 布局(手工竖排:标题 20 / 正文按宽折行 / 按钮 30 + 间距)
        titleL.preferredMaxLayoutWidth = width - 48
        msgL.preferredMaxLayoutWidth = width - 48
        titleL.sizeToFit()
        msgL.sizeToFit()
        let titleH = max(22, titleL.fittingSize.height)
        let msgH = max(18, msgL.fittingSize.height)
        let contentH = 24 + titleH + 8 + msgH + 18 + btnH + 20

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: contentH))
        titleL.frame.origin = CGPoint(x: 24, y: contentH - 20 - titleH)
        msgL.frame.origin = CGPoint(x: 24, y: contentH - 20 - titleH - 8 - msgH)
        btnRow.frame.origin = CGPoint(x: width - 24 - rowW, y: 20)
        root.addSubview(titleL)
        root.addSubview(msgL)
        root.addSubview(btnRow)

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
