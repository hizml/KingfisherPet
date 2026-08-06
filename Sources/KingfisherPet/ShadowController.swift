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
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        overlay.orderFrontRegardless()
        tick()
    }

    func setVisible(_ visible: Bool) {
        if visible { overlay.orderFrontRegardless() } else { overlay.orderOut(nil) }
    }

    private func resizeOverlay() {
        guard let scr = bird?.screen ?? NSScreen.main else { return }
        let a = scr.visibleFrame
        overlay.setFrame(CGRect(x: a.minX, y: a.minY, width: a.width, height: 100), display: true)
    }

    /// 太阳参数:sunX 水平方向(+1=右/晨, -1=左/昏),elev 高度(0..1),night 夜晚
    private func sunParams() -> (sunX: CGFloat, elev: CGFloat, night: Bool) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let h = CGFloat(comps.hour ?? 12) + CGFloat(comps.minute ?? 0) / 60.0
        if h < 6 || h > 18 {
            return (sunX: 0, elev: 0.15, night: true)     // 夜晚:弱月光
        }
        let t = (h - 6) / 12                                // 0(晨)..1(昏)
        let sunX = cos(t * .pi)                             // 晨 +1(右) .. 昏 -1(左)
        let elev = max(0.12, sin(t * .pi))
        return (sunX, elev, false)
    }

    private func tick() {
        guard let b = bird, let scr = b.screen ?? NSScreen.main else { return }
        let a = scr.visibleFrame
        if overlay.frame.width != a.width || overlay.frame.minY != a.minY {
            resizeOverlay()
        }
        let groundY = a.minY + 6
        let (sunX, elev, night) = sunParams()

        let bx = b.frame.midX
        let heightAbove = max(0, b.frame.midY - groundY)

        // 影子水平偏移:与太阳相反;太阳越低(elev 小)偏得越远
        let maxOff: CGFloat = 150
        var off = -sunX * maxOff / max(elev, 0.25)
        off = max(-230, min(230, off))
        var sx = bx + off
        sx = max(a.minX + 24, min(sx, a.maxX - 24))

        // 尺寸:鸟越高 → 越大;透明度:鸟越高/夜晚 → 越淡
        let w = 60 + min(heightAbove * 0.10, 55)
        let h = 18 + min(heightAbove * 0.02, 14)
        var op: CGFloat = 0.5 * max(0, 1 - heightAbove / 680)
        op = max(0.06, op)
        if night { op *= 0.3 }

        // overlay 内坐标:原点对齐 a.minY(底部)
        shadow.position = CGPoint(x: sx - a.minX, y: groundY - a.minY)
        shadow.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        shadow.opacity = Float(op)
    }
}
