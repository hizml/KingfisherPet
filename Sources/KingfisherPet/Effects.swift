import AppKit
import QuartzCore

/// 一个短命的透明、置顶、点击穿透窗口,用来承载粒子特效(水花/音符)。
/// 用 `Effect` 包装,靠静态数组保活,播完自动撤窗口。
final class Effect {
    static var active: [Effect] = []
    let window: NSWindow

    init(centeredAt point: CGPoint, size: CGSize, on screen: NSScreen?,
         level: NSWindow.Level = .floating,
         build: (NSView) -> Void) {
        let rect = NSRect(x: point.x - size.width / 2,
                          y: point.y - size.height / 2,
                          width: size.width, height: size.height)
        let w = NSWindow(contentRect: rect, styleMask: .borderless,
                         backing: .buffered, defer: false, screen: screen)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = level
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
            ring.opacity = 0
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
                drop.opacity = 0
                drop.add(pos, forKey: "p"); drop.add(op, forKey: "o")
                layer.addSublayer(drop)
            }
        }
        e.close(after: 0.7)
    }

    /// 音符:在 point(屏幕坐标,鸟头上方)处 ♪ 上浮淡出
    static func notes(at point: CGPoint, on screen: NSScreen?) {
        let size = CGSize(width: 120, height: 120)
        let e = Effect(centeredAt: point, size: size, on: screen, level: .statusBar) { v in
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
                t.opacity = 0
                t.add(pos, forKey: "p"); t.add(op, forKey: "o")
                layer.addSublayer(t)
            }
        }
        e.close(after: 1.6)
    }

    /// 鸟屎:从 point(屁股位置,屏幕坐标)处掉出一小坨白色鸟屎(尿酸白 + 一小撮深色),摆动+淡出
    static func poop(at point: CGPoint, on screen: NSScreen?) {
        let size = CGSize(width: 70, height: 220)
        let center = CGPoint(x: point.x, y: point.y - size.height / 2)
        let e = Effect(centeredAt: center, size: size, on: screen) { v in
            guard let layer = v.layer else { return }
            let top = CGPoint(x: size.width / 2, y: size.height - 16)
            let bot = CGPoint(x: size.width / 2, y: 14)

            // 小坨白色鸟屎:主体白 + 米白 + 一小撮深绿(粪便)
            let blob = CALayer()
            blob.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
            blob.position = top
            func drop(w: CGFloat, h: CGFloat, off: CGFloat, c: NSColor) -> CALayer {
                let l = CALayer()
                l.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                l.position = CGPoint(x: 15, y: 15 + off)
                l.cornerRadius = min(w, h) / 2
                l.backgroundColor = c.cgColor
                return l
            }
            blob.addSublayer(drop(w: 16, h: 12, off: 0, c: NSColor(calibratedWhite: 0.97, alpha: 1)))
            blob.addSublayer(drop(w: 11, h: 8,  off: 3, c: NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.82, alpha: 1)))
            blob.addSublayer(drop(w: 5,  h: 4,  off: 5, c: NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.26, alpha: 1)))

            // 下落 + 左右摆
            let mid = CGPoint(x: top.x - 5, y: (top.y + bot.y) / 2)
            let lower = CGPoint(x: top.x + 5, y: bot.y + (top.y - bot.y) * 0.25)
            let pos = CAKeyframeAnimation(keyPath: "position")
            pos.values = [top, mid, lower, bot]
            pos.keyTimes = [0, 0.4, 0.75, 1]
            pos.duration = 1.0
            pos.timingFunction = CAMediaTimingFunction(name: .easeIn)
            let op = CAKeyframeAnimation(keyPath: "opacity")
            op.values = [1, 1, 0]
            op.keyTimes = [0, 0.8, 1]
            op.duration = 1.0
            blob.opacity = 0
            blob.add(pos, forKey: "p"); blob.add(op, forKey: "o")
            layer.addSublayer(blob)
        }
        e.close(after: 1.2)
    }

    /// 带描边的字形(填充 + 描边),用于 zzz
    private static func outlinedGlyph(_ ch: String, size: CGFloat) -> NSImage {
        let str = NSAttributedString(string: ch, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 0.95),
            .strokeColor: NSColor(calibratedHue: 0.52, saturation: 0.45,
                                  brightness: 0.55, alpha: 0.95),
            .strokeWidth: -3.0          // 负值 = 填充 + 描边
        ])
        let bbox = str.size()
        let img = NSImage(size: bbox)
        img.lockFocus()
        str.draw(at: .zero)
        img.unlockFocus()
        return img
    }

    /// 睡眠 zzz:在 point(鸟头上方)放一个带描边的 z,上浮 + 漂移 + 淡出
    static func zzz(at point: CGPoint, on screen: NSScreen?) {
        let size = CGSize(width: 90, height: 130)
        // 让窗口底部对齐 point(鸟头),z 从这里往上飞
        let center = CGPoint(x: point.x, y: point.y + size.height / 2)
        let e = Effect(centeredAt: center, size: size, on: screen, level: .statusBar) { v in
            guard let layer = v.layer else { return }
            let sz = CGFloat.random(in: 22...30)
            let img = outlinedGlyph("z", size: sz)
            guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let z = CALayer()
            z.bounds = CGRect(origin: .zero, size: img.size)
            let startX = size.width / 2 + CGFloat.random(in: -12...12)
            let startY: CGFloat = 14                        // 窗口底部 ≈ 鸟头
            z.position = CGPoint(x: startX, y: startY)
            z.contents = cg
            z.contentsScale = NSScreen.main?.backingScaleFactor ?? 2

            let pos = CABasicAnimation(keyPath: "position")
            pos.fromValue = NSValue(point: CGPoint(x: startX, y: startY))
            pos.toValue = NSValue(point: CGPoint(x: startX + CGFloat.random(in: -18...18),
                                                 y: size.height - 14))
            pos.duration = 1.8
            let op = CAKeyframeAnimation(keyPath: "opacity")
            op.values = [0, 1, 1, 0]
            op.keyTimes = [0, 0.12, 0.7, 1]
            op.duration = 1.8
            z.opacity = 0
            z.add(pos, forKey: "p"); z.add(op, forKey: "o")
            layer.addSublayer(z)
        }
        e.close(after: 1.9)
    }
}
