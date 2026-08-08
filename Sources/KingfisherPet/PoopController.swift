import AppKit
import QuartzCore

/// 屎物理系统:屎从鸟处下落,落在途径的窗口上沿或 Dock 上;停靠一会儿后消失。
/// 若落在某窗口上、该窗口移走(不再托住),屎重新落到 Dock / 下一窗口。
/// 屎窗口层级高于 Dock(能落在 Dock 上)、低于鸟。
final class PoopController {

    private var poops: [Poop] = []
    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0
    /// 鸟所在窗口,用来确定屎落在哪个屏(多屏时屎跟随鸟的屏,而非死主屏)
    weak var bird: NSWindow?

    func start() {
        lastTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 解析屎应使用的屏:鸟所在屏,否则主屏
    private var screen: NSScreen? { bird?.screen ?? NSScreen.main }

    func dropPoop(at point: CGPoint) {
        let p = Poop(start: point)
        poops.append(p)
        if let scr = screen {
            let (ly, id) = WindowTracker.landingSpot(belowX: point.x, fromY: point.y,
                                                     groundY: scr.visibleFrame.minY)
            p.landingY = ly
            p.landedID = id
        }
    }

    private func update() {
        let now = CACurrentMediaTime()
        let dt = lastTime == 0 ? 1.0 / 30.0 : min(0.05, now - lastTime)
        lastTime = now
        guard let scr = screen else { return }
        let ground = scr.visibleFrame.minY
        let sh = scr.frame.height
        for p in poops { p.update(dt: dt, ground: ground, screenH: sh) }
        let gone = poops.filter { $0.dead }
        gone.forEach { $0.window.orderOut(nil) }
        poops.removeAll { $0.dead }
    }
}

private final class Poop {
    enum State { case falling, sitting, fading }
    let window: NSWindow
    private let blob = CALayer()
    let x: CGFloat
    var y: CGFloat
    var landingY: CGFloat
    var landedID: CGWindowID?
    var state: State = .falling
    var sitRemain: TimeInterval = 0
    var opacity: CGFloat = 1
    var dead = false

    init(start: CGPoint) {
        x = start.x
        y = start.y
        landingY = start.y
        window = NSWindow(contentRect: NSRect(x: start.x - 15, y: start.y, width: 30, height: 20),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: 21)      // 高于 Dock、低于鸟
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isReleasedWhenClosed = false

        let v = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 20))
        v.wantsLayer = true
        v.layer = CALayer()
        buildBlob()
        v.layer?.addSublayer(blob)
        window.contentView = v
        window.orderFrontRegardless()
    }

    private func buildBlob() {
        func drop(_ w: CGFloat, _ h: CGFloat, _ cx: CGFloat, _ cy: CGFloat, _ c: NSColor) -> CALayer {
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            l.position = CGPoint(x: cx, y: cy)
            l.cornerRadius = min(w, h) / 2
            l.backgroundColor = c.cgColor
            return l
        }
        blob.bounds = CGRect(x: 0, y: 0, width: 30, height: 20)
        blob.position = CGPoint(x: 15, y: 10)
        let white = ThemeColors.shared.color("poop_white", fallback: NSColor(calibratedWhite: 0.97, alpha: 1))
        let off = ThemeColors.shared.color("poop_off",   fallback: NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.82, alpha: 1))
        let dark = ThemeColors.shared.color("poop_dark",  fallback: NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.26, alpha: 1))
        // 一摊稀屎:宽扁主体底边贴窗口底(local y=0) + 几滴飞溅 + 一小撮深色
        blob.addSublayer(drop(24, 8, 15, 4, white))    // 主体 y 0..8
        blob.addSublayer(drop(16, 6, 15, 6, off))      // 中间略厚
        blob.addSublayer(drop(5, 4, 3, 3, white))
        blob.addSublayer(drop(4, 3, 27, 4, white))
        blob.addSublayer(drop(3, 3, 22, 2, white))
        blob.addSublayer(drop(5, 3, 17, 5, dark))
    }

    func update(dt: TimeInterval, ground: CGFloat, screenH: CGFloat) {
        switch state {
        case .falling:
            // 下落速度受全局动画速度影响
            y -= 220 * CGFloat(dt) * CGFloat(Settings.shared.speed)
            if y <= landingY {
                y = landingY
                state = .sitting
                sitRemain = Double.random(in: 8...15)
                splat()
            }
            applyOrigin()
        case .sitting:
            // 落在窗口上时,跟着窗口上沿;窗口移走/消失/被盖住 → 重新下落到 Dock / 下一窗口
            if let id = landedID {
                if let b = WindowTracker.frameOfWindow(id: id) {
                    let topNS = screenH - b.minY
                    let off = x < b.minX || x > b.maxX || topNS < y - 12
                    // 遮挡:屎处最前面的窗口不是本窗口(被更大窗口盖住)→ 落下
                    let occluded = WindowTracker.frontWindowAt(nsPoint: CGPoint(x: x, y: y)) != id
                    if off || occluded {
                        resumeFall(ground: ground)
                    } else {
                        y = topNS
                        applyOrigin()
                    }
                } else {
                    resumeFall(ground: ground)            // 窗口不见了
                }
            }
            sitRemain -= dt
            if sitRemain <= 0 { state = .fading }
        case .fading:
            opacity -= CGFloat(dt) * 1.2
            window.alphaValue = max(0, opacity)
            if opacity <= 0 { dead = true }
        }
    }

    private func applyOrigin() {
        // y 是屎的底边 → 窗口底贴地
        window.setFrameOrigin(CGPoint(x: x - 15, y: y))
    }

    /// 重新下落(窗口移走/消失):重新计算落点(Dock / 下一窗口)
    private func resumeFall(ground: CGFloat) {
        state = .falling
        let (ly, nid) = WindowTracker.landingSpot(belowX: x, fromY: y, groundY: ground)
        landingY = ly
        landedID = nid
    }

    /// 落地:轻微压扁一下
    private func splat() {
        let s = CAKeyframeAnimation(keyPath: "transform.scale")
        s.values = [1.0, 1.35, 1.0]
        s.keyTimes = [0, 0.4, 1]
        s.duration = 0.18
        s.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        blob.add(s, forKey: "splat")
    }
}
