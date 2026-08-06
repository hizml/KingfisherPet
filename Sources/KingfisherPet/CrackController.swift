import AppKit
import QuartzCore

/// 屏幕裂纹:全屏透明 click-through 覆盖层。裂纹可生长——同位置续啄会扩大已有裂纹,
/// 大小随啄的次数增长(有上限),裂纹数量有上限。层级低于鸟(鸟永远盖在裂纹上)。
final class CrackController {

    private let overlay: NSWindow
    private var cracks: [Crack] = []
    private var origin = CGPoint.zero
    private let maxCracks = 6
    private let maxRadius: CGFloat = 170

    init() {
        overlay = NSWindow(contentRect: .zero, styleMask: .borderless,
                           backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        // 提到 statusBar:可盖过 Dock/菜单栏、延伸到屏幕边外;鸟会用更高层级盖在裂纹上
        overlay.level = .statusBar
        overlay.ignoresMouseEvents = true
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary]
        overlay.isReleasedWhenClosed = false
        let v = NSView()
        v.wantsLayer = true
        v.layer = CALayer()
        overlay.contentView = v
    }

    func start() {
        sizeToScreen()
        overlay.orderFrontRegardless()
    }

    func setVisible(_ visible: Bool) {
        if visible { overlay.orderFrontRegardless() } else { overlay.orderOut(nil) }
    }

    private func sizeToScreen() {
        guard let scr = NSScreen.main else { return }
        origin = scr.frame.origin
        overlay.setFrame(scr.frame, display: true)
    }

    /// 啄一下:附近有裂纹就扩大,否则新建一道小裂纹;受数量/尺寸上限约束
    func peck(at point: CGPoint) {
        guard let layer = overlay.contentView?.layer else { return }
        if overlay.frame.width == 0 { sizeToScreen() }
        let c = CGPoint(x: point.x - origin.x, y: point.y - origin.y)

        if let near = cracks.last(where: { hypot($0.center.x - c.x, $0.center.y - c.y) < 55 }) {
            near.grow()
            return
        }
        guard cracks.count < maxCracks else { return }
        let cr = Crack(center: c, radius: 42, max: maxRadius)
        layer.addSublayer(cr.container)
        cracks.append(cr)
    }

    /// 修复屏幕:清空所有裂纹
    func clear() {
        cracks.forEach { $0.container.removeFromSuperlayer() }
        cracks.removeAll()
    }
}

/// 单条裂纹:可生长。路径用 CGMutablePath,扩大时追加新裂纹线。
final class Crack {
    let container = CALayer()
    let center: CGPoint
    private var radius: CGFloat
    private let maxRadius: CGFloat
    private let path = CGMutablePath()
    private let dark = CAShapeLayer()
    private let light = CAShapeLayer()

    init(center: CGPoint, radius: CGFloat, max: CGFloat) {
        self.center = center
        self.radius = radius
        self.maxRadius = max

        for layer in [dark, light] {
            layer.fillColor = .clear
            layer.lineCap = .round
            layer.lineJoin = .round
            container.addSublayer(layer)
        }
        dark.strokeColor = NSColor(calibratedWhite: 0.05, alpha: 0.55).cgColor
        dark.lineWidth = 2.2
        light.strokeColor = NSColor(calibratedWhite: 1, alpha: 0.7).cgColor
        light.lineWidth = 0.8

        // 中心冲击点
        let dot = CALayer()
        dot.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
        dot.position = center
        dot.cornerRadius = 3
        dot.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.6).cgColor
        container.addSublayer(dot)

        for _ in 0..<4 { appendRay(length: radius) }
        rebuild()
    }

    /// 扩大:加长、加线,直到上限
    func grow() {
        guard radius < maxRadius else { return }
        radius = min(maxRadius, radius + 18)
        appendRay(length: radius)
        appendRay(length: radius * 0.7)
        rebuild()
        // 轻微冲击反馈
        let s = CABasicAnimation(keyPath: "transform.scale")
        s.fromValue = 0.96; s.toValue = 1.0; s.duration = 0.12
        s.timingFunction = CAMediaTimingFunction(name: .easeOut)
        container.add(s, forKey: "g")
    }

    private func appendRay(length: CGFloat) {
        let ang = CGFloat.random(in: 0...(2 * .pi))
        path.move(to: center)
        let segs = Int.random(in: 2...4)
        var p = center
        for s in 1...segs {
            let f = CGFloat(s) / CGFloat(segs)
            let drift = CGFloat.random(in: -0.35...0.35)
            let jx = CGFloat.random(in: -10...10)
            let jy = CGFloat.random(in: -10...10)
            p = CGPoint(x: center.x + cos(ang + drift) * length * f + jx,
                        y: center.y + sin(ang + drift) * length * f + jy)
            path.addLine(to: p)
        }
        let br = ang + CGFloat.random(in: -0.6...0.6)
        path.addLine(to: CGPoint(x: p.x + cos(br) * 16, y: p.y + sin(br) * 16))
    }

    private func rebuild() {
        dark.path = path
        light.path = path
    }
}
