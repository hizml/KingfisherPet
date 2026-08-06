import AppKit
import QuartzCore

/// 地面阴影:常驻透明、点击穿透的覆盖层(屏幕底部一条)。
/// **没有自己的定时器**——只在鸟移动/拖拽时由 Behavior 调 updateNow() 同步刷新,
/// 因此和鸟同帧、无延迟。固定在 Dock 上边、正对鸟下方;鸟飞高 → 变大变淡。
final class ShadowController {

    private weak var bird: NSWindow?
    private let overlay: NSWindow
    private let shadow = CALayer()
    private var lastW: CGFloat = -1
    private var lastH: CGFloat = -1

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
        overlay.orderFrontRegardless()
        tick()
    }

    func setVisible(_ visible: Bool) {
        if visible { overlay.orderFrontRegardless() } else { overlay.orderOut(nil) }
    }

    /// 即时刷新一次(鸟每次移动/拖拽时由 Behavior 同步调用 → 零延迟)
    func updateNow() { tick() }

    private func resizeOverlay() {
        guard let scr = bird?.screen ?? NSScreen.main else { return }
        let a = scr.visibleFrame
        overlay.setFrame(CGRect(x: a.minX, y: a.minY, width: a.width, height: 110), display: true)
    }

    private func tick() {
        guard let b = bird, let scr = b.screen ?? NSScreen.main else { return }
        let a = scr.visibleFrame
        if overlay.frame.width != a.width || overlay.frame.minY != a.minY {
            resizeOverlay()
        }
        let groundY = a.minY + 4
        let bx = b.frame.midX
        let heightAbove = max(0, b.frame.midY - groundY)
        let sx = max(a.minX + 40, min(bx, a.maxX - 40))

        // 尺寸:基础大;鸟飞高 → 更大更散;透明度:鸟越高 → 越淡
        let w = 150 + min(heightAbove * 0.12, 70)
        let h = 40 + min(heightAbove * 0.02, 16)
        var op: CGFloat = 0.85 * max(0, 1 - heightAbove / 700)
        op = max(0.16, op)

        shadow.position = CGPoint(x: sx - a.minX, y: groundY - a.minY)
        // 只在尺寸变化时才改 bounds(避免每帧重光栅化图片 → 阴影延迟)
        if abs(w - lastW) > 0.5 || abs(h - lastH) > 0.5 {
            shadow.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            lastW = w; lastH = h
        }
        shadow.opacity = Float(op)
    }
}
