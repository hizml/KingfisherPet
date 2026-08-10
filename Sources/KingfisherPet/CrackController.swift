import AppKit
import QuartzCore

/// 屏幕裂纹:全屏透明 click-through 覆盖层。裂纹像真玻璃碎——放射裂 + 同心环裂 + 分叉 + 碎屑;
/// 同位置续啄会扩大已有裂纹,大小随次数增长(有上限),裂纹数量有上限。
/// 层级 statusBar:可超出屏幕、盖过 Dock/菜单栏;鸟用更高层级盖在裂纹上。
final class CrackController {

    private let overlay: NSWindow
    private var cracks: [Crack] = []
    private var origin = CGPoint.zero
    private let maxCracks = 8
    private let maxRadius: CGFloat = 180
    /// 鸟所在窗口,用来确定裂纹覆盖哪个屏(多屏跟随鸟)
    weak var bird: NSWindow?

    init() {
        overlay = NSWindow(contentRect: .zero, styleMask: .borderless,
                           backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
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
        // 跟随鸟所在屏;无鸟则主屏
        guard let scr = bird?.screen ?? NSScreen.main else { return }
        origin = scr.frame.origin
        overlay.setFrame(scr.frame, display: true)
    }

    /// 屏幕布局变化(外接屏插拔等)时重定位覆盖层
    func relocate() {
        sizeToScreen()
    }

    /// 啄一下:附近(55px 内)有裂纹就扩大,否则新建一道;老裂纹始终保留,直到"修复屏幕"
    func peck(at point: CGPoint) {
        guard let layer = overlay.contentView?.layer else { return }
        if overlay.frame.width == 0 { sizeToScreen() }
        let c = CGPoint(x: point.x - origin.x, y: point.y - origin.y)

        if let near = cracks.last(where: { hypot($0.center.x - c.x, $0.center.y - c.y) < 55 }) {
            near.grow()
            return
        }
        guard cracks.count < maxCracks else { return }
        let cr = Crack(center: c, radius: 44, max: maxRadius)
        layer.addSublayer(cr.container)
        cracks.append(cr)
    }

    /// 修复屏幕:清空所有裂纹
    func clear() {
        cracks.forEach { $0.container.removeFromSuperlayer() }
        cracks.removeAll()
    }
}

/// 单条裂纹(玻璃碎):放射裂 + 同心环裂 + 分叉 + 碎屑;可生长。
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

        for l in [dark, light] {
            l.fillColor = .clear
            l.lineCap = .round
            l.lineJoin = .round
            container.addSublayer(l)
        }
        dark.strokeColor = ThemeColors.shared.cgColor("crack_dark", fallback: NSColor(calibratedWhite: 0.05, alpha: 0.6))
        dark.lineWidth = 2.2
        light.strokeColor = ThemeColors.shared.cgColor("crack_light", fallback: NSColor(calibratedWhite: 1, alpha: 0.7))
        light.lineWidth = 0.8

        // 中心冲击点
        let dot = CALayer()
        dot.bounds = CGRect(x: 0, y: 0, width: 7, height: 7)
        dot.position = center
        dot.cornerRadius = 3.5
        dot.backgroundColor = ThemeColors.shared.cgColor("crack_dark", fallback: NSColor(calibratedWhite: 0.08, alpha: 0.65))
        container.addSublayer(dot)

        for _ in 0..<5 { appendRay(length: radius) }
        appendArc(radius: radius * 0.55)
        for _ in 0..<3 { appendChip(r: radius * 0.45) }
        rebuild()
        stylize()   // 按主题风格化线条(霓虹发光/像素加粗/水墨毛笔/粘土投影)
    }

    /// 按当前主题风格化裂纹线条。颜色已跟 ThemeColors crack_dark/light;这里调粗细/发光/投影。
    private func stylize() {
        switch SpriteLibrary.shared.currentTheme {
        case "neon":
            for l in [dark, light] {
                l.shadowColor = ThemeColors.shared.cgColor("crack_dark", fallback: NSColor.cyan)
                l.shadowOpacity = 0.9; l.shadowRadius = 4; l.shadowOffset = .zero
            }
        case "pixel":
            dark.lineWidth = 3.5; light.lineWidth = 1.5
        case "ink":
            dark.lineWidth = CGFloat.random(in: 2.5...4.5); light.lineWidth = 1.0   // 毛笔粗细
        case "clay":
            for l in [dark, light] {
                l.shadowColor = NSColor.black.cgColor
                l.shadowOpacity = 0.35; l.shadowRadius = 2; l.shadowOffset = CGSize(width: 1.5, height: -1.5)
            }
        default:   // flat / watercolor 原样
            break
        }
    }

    /// 扩大:加长、加放射裂 + 同心环 + 碎屑,直到上限(不加弹跳动画,避免"刷新"感)
    func grow() {
        guard radius < maxRadius else { return }
        radius = min(maxRadius, radius + 18)
        appendRay(length: radius)
        appendRay(length: radius * 0.8)
        appendArc(radius: radius * 0.62)
        if Bool.random() { appendChip(r: radius * 0.5) }
        rebuild()
        // 轻微震动(玻璃被敲的余震),很轻、1px 量级
        let o = container.position
        let shake = CAKeyframeAnimation(keyPath: "position")
        shake.values = [NSValue(point: o),
                        NSValue(point: CGPoint(x: o.x + 1.2, y: o.y - 0.8)),
                        NSValue(point: CGPoint(x: o.x - 1.0, y: o.y + 0.6)),
                        NSValue(point: o)]
        shake.keyTimes = [0, 0.3, 0.6, 1]
        shake.duration = 0.12
        container.add(shake, forKey: "shake")
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
            // 中段偶尔分叉
            if s == segs / 2 && Bool.random() {
                let ba = ang + CGFloat.random(in: -1.0...1.0)
                path.addLine(to: CGPoint(x: p.x + cos(ba) * 12, y: p.y + sin(ba) * 12))
                path.move(to: p)
            }
        }
        let br = ang + CGFloat.random(in: -0.6...0.6)
        path.addLine(to: CGPoint(x: p.x + cos(br) * 16, y: p.y + sin(br) * 16))
    }

    /// 同心环裂(玻璃被击打后的一圈环形裂缝),用多段折线近似
    private func appendArc(radius r: CGFloat) {
        let start = CGFloat.random(in: 0...(2 * .pi))
        let span = CGFloat.random(in: 0.7...1.6)
        let steps = 9
        for i in 0..<steps {
            let a0 = start + span * CGFloat(i) / CGFloat(steps)
            let a1 = start + span * CGFloat(i + 1) / CGFloat(steps)
            let j0 = CGFloat.random(in: -3...3)
            let j1 = CGFloat.random(in: -3...3)
            path.move(to: CGPoint(x: center.x + cos(a0) * (r + j0), y: center.y + sin(a0) * (r + j0)))
            path.addLine(to: CGPoint(x: center.x + cos(a1) * (r + j1), y: center.y + sin(a1) * (r + j1)))
        }
    }

    /// 中心附近的小三角碎屑
    private func appendChip(r: CGFloat) {
        let ang = CGFloat.random(in: 0...(2 * .pi))
        let d = CGFloat.random(in: 0...r)
        let cx = center.x + cos(ang) * d
        let cy = center.y + sin(ang) * d
        path.move(to: CGPoint(x: cx, y: cy))
        path.addLine(to: CGPoint(x: cx + CGFloat.random(in: -7...7), y: cy + CGFloat.random(in: -7...7)))
        path.addLine(to: CGPoint(x: cx + CGFloat.random(in: -7...7), y: cy + CGFloat.random(in: -7...7)))
        path.closeSubpath()
    }

    private func rebuild() {
        dark.path = path
        light.path = path
    }
}
