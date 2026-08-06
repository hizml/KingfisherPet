import AppKit
import QuartzCore

/// 屏幕裂纹:全屏透明 click-through 覆盖层(与鸟同层 .floating),
/// 啄击时在指定点叠加"碎玻璃"裂纹,累积;可一键修复清空。
final class CrackController {

    private let overlay: NSWindow
    private var cracks: [CALayer] = []
    private var origin = CGPoint.zero

    init() {
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
        let f = scr.frame
        origin = f.origin
        overlay.setFrame(f, display: true)
    }

    /// 在屏幕坐标 point 处加一条裂纹
    func addCrack(at point: CGPoint) {
        guard let layer = overlay.contentView?.layer else { return }
        if overlay.frame.width == 0 { sizeToScreen() }
        let c = CGPoint(x: point.x - origin.x, y: point.y - origin.y)

        let path = CGMutablePath()
        path.move(to: c)
        let rays = Int.random(in: 8...12)
        for _ in 0..<rays {
            let ang = CGFloat.random(in: 0...(2 * .pi))
            let len = CGFloat.random(in: 45...95)
            let segs = Int.random(in: 2...4)
            var p = c
            path.move(to: c)
            for s in 1...segs {
                let f = CGFloat(s) / CGFloat(segs)
                let drift = CGFloat.random(in: -0.35...0.35)
                let jx = CGFloat.random(in: -10...10)
                let jy = CGFloat.random(in: -10...10)
                p = CGPoint(x: c.x + cos(ang + drift) * len * f + jx,
                            y: c.y + sin(ang + drift) * len * f + jy)
                path.addLine(to: p)
            }
            // 末梢再分一小叉
            let br = ang + CGFloat.random(in: -0.6...0.6)
            path.addLine(to: CGPoint(x: p.x + cos(br) * 18, y: p.y + sin(br) * 18))
        }

        // 深色底 + 亮色描边,保证在任何背景上都可见
        let dark = CAShapeLayer()
        dark.path = path
        dark.fillColor = .clear
        dark.strokeColor = NSColor(calibratedWhite: 0.05, alpha: 0.55).cgColor
        dark.lineWidth = 2.2
        dark.lineCap = .round
        dark.lineJoin = .round

        let light = CAShapeLayer()
        light.path = path
        light.fillColor = .clear
        light.strokeColor = NSColor(calibratedWhite: 1, alpha: 0.7).cgColor
        light.lineWidth = 0.8
        light.lineCap = .round
        light.lineJoin = .round

        // 中心冲击点
        let dot = CALayer()
        dot.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
        dot.position = c
        dot.cornerRadius = 3
        dot.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.6).cgColor

        let group = CALayer()
        group.addSublayer(dark)
        group.addSublayer(light)
        group.addSublayer(dot)
        // 直接出现(淡入,不缩放,避免"飞过来"的感觉)
        group.opacity = 0
        layer.addSublayer(group)
        cracks.append(group)

        let o = CABasicAnimation(keyPath: "opacity")
        o.fromValue = 0.0; o.toValue = 1.0; o.duration = 0.1
        group.add(o, forKey: "in")
        group.opacity = 1
    }

    /// 修复屏幕:清空所有裂纹
    func clear() {
        cracks.forEach { $0.removeFromSuperlayer() }
        cracks.removeAll()
    }
}
