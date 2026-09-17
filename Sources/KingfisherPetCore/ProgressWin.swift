import AppKit

/// 应用内更新的进度小窗(下载中 xx% + 进度条):点「下载并更新」后立刻出现,
/// 成功=进程重启自然消亡,失败=关闭后由失败弹窗接手。
final class ProgressWin {
    private let window: NSWindow
    private let bar = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")
    private var closed = false

    init() {
        let w = CGFloat(300), h = CGFloat(104)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = Language.t("update.downloading")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        bar.style = .bar
        bar.isIndeterminate = false   // 默认 true=不定态,doubleValue 不画(KFDialog 同坑已修,此处漏网)
        bar.minValue = 0; bar.maxValue = 100
        bar.frame = NSRect(x: 24, y: 40, width: w - 48, height: 20)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.frame = NSRect(x: 24, y: 14, width: w - 48, height: 18)
        window.contentView?.addSubview(bar)
        window.contentView?.addSubview(label)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        update(0)
    }

    func update(_ pct: Int) {
        guard !closed else { return }
        bar.doubleValue = Double(min(100, max(0, pct)))
        label.stringValue = "\(min(100, max(0, pct)))%"
    }

    func close() {
        guard !closed else { return }
        closed = true
        window.orderOut(nil)
    }
}
