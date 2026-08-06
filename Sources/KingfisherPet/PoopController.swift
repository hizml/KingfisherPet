import AppKit
import QuartzCore

/// 屎物理系统:屎从鸟处下落,落在途径的窗口上沿或 Dock 上;停靠一会儿后消失。
/// 若落在某窗口上、该窗口移走(不再托住),屎重新落到 Dock / 下一窗口。
/// 屎窗口层级高于 Dock(能落在 Dock 上)、低于鸟。
final class PoopController {

    private var poops: [Poop] = []
    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0

    func start() {
        lastTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func dropPoop(at point: CGPoint) {
        let p = Poop(start: point)
        poops.append(p)
        if let scr = NSScreen.main {
            let (ly, id) = WindowTracker.landingSpot(belowX: point.x, fromY: point.y,
                                                     groundY: scr.visibleFrame.minY + 6)
            p.landingY = ly
            p.landedID = id
        }
    }

    private func update() {
        let now = CACurrentMediaTime()
        let dt = lastTime == 0 ? 1.0 / 30.0 : min(0.05, now - lastTime)
        lastTime = now
        guard let scr = NSScreen.main else { return }
        let ground = scr.visibleFrame.minY + 6
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
    private let half: CGFloat = 14
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
        window = NSWindow(contentRect: NSRect(x: start.x - 14, y: start.y - 14, width: 28, height: 28),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: 21)      // 高于 Dock、低于鸟
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isReleasedWhenClosed = false

        let v = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        v.wantsLayer = true
        v.layer = CALayer()
        buildBlob()
        v.layer?.addSublayer(blob)
        window.contentView = v
        window.orderFrontRegardless()
    }

    private func buildBlob() {
        func drop(_ w: CGFloat, _ h: CGFloat, _ off: CGFloat, _ c: NSColor) -> CALayer {
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            l.position = CGPoint(x: 14, y: 14 + off)
            l.cornerRadius = min(w, h) / 2
            l.backgroundColor = c.cgColor
            return l
        }
        blob.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
        blob.position = CGPoint(x: 14, y: 14)
        blob.addSublayer(drop(16, 12, 0, NSColor(calibratedWhite: 0.97, alpha: 1)))
        blob.addSublayer(drop(11, 8, 3, NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.82, alpha: 1)))
        blob.addSublayer(drop(5, 4, 5, NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.26, alpha: 1)))
    }

    func update(dt: TimeInterval, ground: CGFloat, screenH: CGFloat) {
        switch state {
        case .falling:
            y -= 380 * CGFloat(dt)
            if y <= landingY {
                y = landingY
                state = .sitting
                sitRemain = Double.random(in: 8...15)
                splat()
            }
            applyOrigin()
        case .sitting:
            // 落在窗口上时,跟着窗口上沿;窗口移走或消失 → 重新下落到 Dock / 下一窗口
            if let id = landedID {
                if let b = WindowTracker.frameOfWindow(id: id) {
                    let topNS = screenH - b.minY
                    if x < b.minX || x > b.maxX || topNS < y - 12 {
                        resumeFall(ground: ground)        // 窗口移走
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
        window.setFrameOrigin(CGPoint(x: x - half, y: y - half))
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
