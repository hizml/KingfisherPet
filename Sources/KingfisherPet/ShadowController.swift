import AppKit
import QuartzCore

/// 地面阴影:常驻透明、点击穿透的覆盖层(屏幕底部一条),30fps 读取鸟窗口位置
/// + 当前系统时间算太阳方位(右升左落),驱动一坨柔和阴影。
/// 鸟飞高 → 影子变大变淡、留在地面;夜晚 → 淡淡月光影。
final class ShadowController {

    private weak var bird: NSWindow?
    private let overlay: NSWindow
    private let shadow = CALayer()
    private var timer: Timer?

    init(bird: NSWindow) {
        self.bird = bird
        overlay = NSWindow(contentRect: .zero, styleMask: .borderless,
                           backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.level = .floating
        overlay.ignoresMouseEvents = true
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary]
        overlay.isReleasedWhenClosed = false

        let v = NSView()
        v.wantsLayer = true
        v.layer = CALayer()
        shadow.contentsGravity = .resize
        shadow.backgroundColor = .clear
        v.layer?.addSublayer(shadow)
        overlay.contentView = v

        if let url = Bundle.main.url(forResource: "shadow", withExtension: "png"),
           let img = NSImage(contentsOf: url),
           let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            shadow.contents = cg
        }
    }

    func start() {
        resizeOverlay()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        overlay.orderFrontRegardless()
        tick()
    }

    func setVisible(_ visible: Bool) {
        if visible { overlay.orderFrontRegardless() } else { overlay.orderOut(nil) }
    }

    /// 即时刷新一次(鸟移动时由 Behavior 同步调用,避免阴影延迟)
    func updateNow() { tick() }

    private func resizeOverlay() {
        guard let scr = bird?.screen ?? NSScreen.main else { return }
        let a = scr.visibleFrame
        overlay.setFrame(CGRect(x: a.minX, y: a.minY, width: a.width, height: 100), display: true)
    }

    private func tick() {
        guard let b = bird, let scr = b.screen ?? NSScreen.main else { return }
        let a = scr.visibleFrame
        if overlay.frame.width != a.width || overlay.frame.minY != a.minY {
            resizeOverlay()
        }
        // 阴影固定在 Dock 上边(地面),正对鸟下方;不再做太阳角度偏移
        let groundY = a.minY + 4
        let bx = b.frame.midX
        let heightAbove = max(0, b.frame.midY - groundY)
        let sx = max(a.minX + 30, min(bx, a.maxX - 30))

        // 尺寸:基础较大;鸟飞高 → 更大更散;透明度:鸟越高 → 越淡
        let w = 92 + min(heightAbove * 0.12, 70)
        let h = 26 + min(heightAbove * 0.02, 16)
        var op: CGFloat = 0.8 * max(0, 1 - heightAbove / 700)
        op = max(0.12, op)

        // overlay 内坐标:原点对齐 a.minY(底部)
        shadow.position = CGPoint(x: sx - a.minX, y: groundY - a.minY)
        shadow.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        shadow.opacity = Float(op)
    }
}
