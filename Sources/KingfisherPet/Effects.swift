import AppKit
import QuartzCore

/// 一个短命的透明、置顶、点击穿透窗口,用来承载粒子特效(水花/音符)。
/// 用 `Effect` 包装,靠静态数组保活,播完自动撤窗口。
final class Effect {
    static var active: [Effect] = []
    let window: NSWindow

    init(centeredAt point: CGPoint, size: CGSize, on screen: NSScreen?,
         build: (NSView) -> Void) {
        let rect = NSRect(x: point.x - size.width / 2,
                          y: point.y - size.height / 2,
                          width: size.width, height: size.height)
        let w = NSWindow(contentRect: rect, styleMask: .borderless,
                         backing: .buffered, defer: false, screen: screen)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .floating
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]
        w.isReleasedWhenClosed = true

        let v = NSView(frame: NSRect(origin: .zero, size: size))
        v.wantsLayer = true
        v.layer = CALayer()
        build(v)
        w.contentView = v
        self.window = w

        Effect.active.append(self)
        w.orderFrontRegardless()
    }

    func close(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.window.orderOut(nil)
            Effect.active.removeAll { $0 === self }
        }
    }
}

enum Effects {

    /// 水花:在 point(屏幕坐标)处溅起白色水滴 + 涟漪
    static func splash(at point: CGPoint, on screen: NSScreen?) {
        let size = CGSize(width: 160, height: 160)
        let e = Effect(centeredAt: point, size: size, on: screen) { v in
            guard let layer = v.layer else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)

            // 涟漪(空心圆环放大淡出)
            let ring = CALayer()
            ring.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
            ring.position = c
            ring.cornerRadius = 15
            ring.borderWidth = 3
            ring.borderColor = NSColor(calibratedWhite: 1, alpha: 0.9).cgColor
            ring.backgroundColor = .clear
            let rs = CABasicAnimation(keyPath: "transform.scale")
            rs.fromValue = 0.3; rs.toValue = 3.2; rs.duration = 0.55
            let ro = CABasicAnimation(keyPath: "opacity")
            ro.fromValue = 0.9; ro.toValue = 0; ro.duration = 0.55
            ring.add(rs, forKey: "s"); ring.add(ro, forKey: "o")
            layer.addSublayer(ring)

            // 水滴:向上四散再落下
            let n = 9
            for i in 0..<n {
                let frac = CGFloat(i) / CGFloat(n - 1)
                let ang = (.pi * 0.15) + frac * (.pi * 0.7)   // 向上扇形
                let dist: CGFloat = 46
                let dx = cos(ang) * dist
                let drop = CALayer()
                let ds: CGFloat = 6
                drop.bounds = CGRect(x: 0, y: 0, width: ds, height: ds)
                drop.cornerRadius = ds / 2
                drop.position = c
                drop.backgroundColor = NSColor.white.cgColor

                let peak = CGPoint(x: c.x + dx, y: c.y - dist * 0.95)
                let end  = CGPoint(x: c.x + dx * 1.25, y: c.y + 22)
                let pos = CAKeyframeAnimation(keyPath: "position")
                pos.values = [c, peak, end]
                pos.keyTimes = [0, 0.45, 1]
                pos.duration = 0.6
                pos.timingFunctions = [
                    CAMediaTimingFunction(name: .easeOut),
                    CAMediaTimingFunction(name: .easeIn)
                ]
                let op = CABasicAnimation(keyPath: "opacity")
                op.fromValue = 1; op.toValue = 0; op.duration = 0.6
                drop.add(pos, forKey: "p"); drop.add(op, forKey: "o")
                layer.addSublayer(drop)
            }
        }
        e.close(after: 0.7)
    }

    /// 音符:在 point(屏幕坐标,鸟头上方)处 ♪ 上浮淡出
    static func notes(at point: CGPoint, on screen: NSScreen?) {
        let size = CGSize(width: 120, height: 120)
        let e = Effect(centeredAt: point, size: size, on: screen) { v in
            guard let layer = v.layer else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let glyphs = ["♪", "♫", "♬"]
            for i in 0..<glyphs.count {
                let t = CATextLayer()
                t.string = glyphs[i]
                t.font = NSFont.systemFont(ofSize: 28)
                t.fontSize = 28
                t.foregroundColor = NSColor(calibratedHue: 0.5, saturation: 0.5,
                                            brightness: 0.95, alpha: 1).cgColor
                t.alignmentMode = .center
                t.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
                t.bounds = CGRect(x: 0, y: 0, width: 40, height: 36)
                t.position = CGPoint(x: c.x + CGFloat(i - 1) * 14, y: c.y)
                let now = CACurrentMediaTime()
                let pos = CABasicAnimation(keyPath: "position")
                pos.fromValue = NSValue(point: t.position)
                pos.toValue = NSValue(point: CGPoint(x: t.position.x, y: t.position.y + 40))
                pos.duration = 1.2
                pos.beginTime = now + Double(i) * 0.25
                pos.fillMode = .forwards
                let op = CAKeyframeAnimation(keyPath: "opacity")
                op.values = [0, 1, 1, 0]
                op.keyTimes = [0, 0.15, 0.7, 1]
                op.duration = 1.2
                op.beginTime = now + Double(i) * 0.25
                op.fillMode = .forwards
                t.add(pos, forKey: "p"); t.add(op, forKey: "o")
                layer.addSublayer(t)
            }
        }
        e.close(after: 1.6)
    }
}
