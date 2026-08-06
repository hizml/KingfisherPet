import AppKit
import QuartzCore

/// 地面阴影:自己是一个小型透明 click-through 窗口,**和鸟一样用 setFrame 移动**,
/// 所以左右移动时与鸟同帧、零延迟(避免"图层 commit vs 窗口移动"的合成差)。
/// 固定在 Dock 上边、正对鸟下方;鸟飞高 → 窗口变大、透明度变低。
final class ShadowController {

    private weak var bird: NSWindow?
    private let overlay: NSWindow
    private var lastW: CGFloat = -1
    private var lastH: CGFloat = -1
    private var lastX: CGFloat = .infinity
    private var lastY: CGFloat = .infinity

    init(bird: NSWindow) {
        self.bird = bird
        overlay = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 150, height: 40),
                           styleMask: .borderless, backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.level = .floating
        overlay.ignoresMouseEvents = true
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary]
        overlay.isReleasedWhenClosed = false

        let v = NSView()
        v.wantsLayer = true
        let layer = CALayer()
        layer.contentsGravity = .resize
        layer.backgroundColor = .clear
        if let url = Bundle.main.url(forResource: "shadow", withExtension: "png"),
           let img = NSImage(contentsOf: url),
           let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            layer.contents = cg
        }
        v.layer = layer
        overlay.contentView = v
    }

    func start() {
        overlay.orderFrontRegardless()
        tick()
    }

    func setVisible(_ visible: Bool) {
        if visible { overlay.orderFrontRegardless() } else { overlay.orderOut(nil) }
    }

    /// 即时刷新(鸟每次移动/拖拽时由 Behavior 同步调用)
    func updateNow() { tick() }

    private func tick() {
        guard let b = bird, let scr = b.screen ?? NSScreen.main else { return }
        let a = scr.visibleFrame
        let groundY = a.minY + 4
        let bx = b.frame.midX
        let heightAbove = max(0, b.frame.midY - groundY)
        let sx = max(a.minX + 40, min(bx, a.maxX - 40))

        let w = 150 + min(heightAbove * 0.12, 70)
        let h = 40 + min(heightAbove * 0.02, 16)
        var op: CGFloat = 0.85 * max(0, 1 - heightAbove / 700)
        op = max(0.16, op)

        let frame = NSRect(x: sx - w / 2, y: groundY - h / 2, width: w, height: h)

        // 尺寸变了才 setFrame(触发 resize),否则只挪窗口(和鸟同管线,零延迟)
        if w != lastW || h != lastH {
            overlay.setFrame(frame, display: false)
            lastW = w; lastH = h; lastX = frame.minX; lastY = frame.minY
        } else if frame.minX != lastX || frame.minY != lastY {
            overlay.setFrameOrigin(frame.origin)
            lastX = frame.minX; lastY = frame.minY
        }
        // 透明度
        if abs(overlay.alphaValue - op) > 0.01 {
            overlay.alphaValue = op
        }
    }
}
