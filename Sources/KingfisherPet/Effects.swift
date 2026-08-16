import AppKit
import QuartzCore

/// 一个短命的透明、置顶、点击穿透窗口,用来承载粒子特效(水花/音符)。
/// 用 `Effect` 包装,靠静态数组保活,播完自动撤窗口。
final class Effect {
    static var active: [Effect] = []
    let window: NSWindow
    private var dismissed = false   // dismiss 幂等:clearAll 与挂起的 close(after:) 可能先后触发,双重 close 会抛异常

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
        w.collectionBehavior = [.canJoinAllSpaces]   // 去 stationary:短命特效必须能真正销毁
        // ARC 下必须 false:true 会让 AppKit 在 close() 时额外 release → 过度释放,
        // 下一次 CA 提交摸到野指针直接段错误(_NSWindowTransformAnimation dealloc 崩溃)
        w.isReleasedWhenClosed = false

        let v = NSView(frame: NSRect(origin: .zero, size: size))
        v.wantsLayer = true
        v.layer = CALayer()
        build(v)
        w.contentView = v
        self.window = w

        Effect.active.append(self)
        kfLog("Effect+ total=\(Effect.active.count)")
        w.orderFrontRegardless()
    }

    func close(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.dismiss()
        }
    }

    /// 彻底撤掉:停动画 + 清 layer + 关窗口(真正释放 WindowServer 资源)+ 移出 active。幂等。
    func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        // 停掉所有 CA 动画(防止无限重复动画在后台渲染占用 GPU)
        if let v = window.contentView {
            v.layer?.removeAllAnimations()
            if let subs = v.layer?.sublayers {
                for s in subs { s.removeAllAnimations(); s.sublayers?.forEach { $0.removeAllAnimations() } }
            }
        }
        window.contentView = nil      // 释放 layer 树
        window.orderOut(nil)
        window.close()                // close 真正断开 WindowServer(orderOut 只隐藏,窗口资源泄漏)
        Effect.active.removeAll { $0 === self }
        kfLog("Effect- total=\(Effect.active.count)")
    }

    /// 立即撤掉所有活着的特效窗口(系统唤醒后清场,彻底释放,避免卡死)
    static func dismissAll() {
        for e in Effect.active { e.dismiss() }
        Effect.active.removeAll()
    }
}

enum Effects {

    /// 按全局动画速度缩放一段时长(快=更短)
    private static func sp(_ s: TimeInterval) -> TimeInterval { s / Settings.shared.speed }

    /// 加载当前主题的特效贴图(太阳/水花/音符/zzz/屎)。主题切换后新建特效自动用新主题。
    private static func effectImage(_ name: String) -> CGImage? {
        let theme = SpriteLibrary.shared.currentTheme
        guard let url = Bundle.main.url(forResource: name, withExtension: "png",
                                        subdirectory: "Sprites/\(theme)"),
              let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return cg
    }

    /// 当前太阳特效实例(同时只允许 1 个,防止堆积卡死)
    private static var sunEffectInstance: Effect?

    /// 清场:撤掉所有短命特效(太阳/水花/zzz/音符等)。唤醒后调用。
    static func clearAll() { Effect.dismissAll(); sunEffectInstance = nil }

    /// 水花:在 point(屏幕坐标)处溅起白色水滴 + 涟漪
    static func splash(at point: CGPoint, on screen: NSScreen?) {
        let size = CGSize(width: 160, height: 160)
        let e = Effect(centeredAt: point, size: size, on: screen) { v in
            guard let layer = v.layer else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)

            // 涟漪(空心圆环放大淡出)—— 主题贴图
            let ring = CALayer()
            ring.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
            ring.position = c
            ring.contents = effectImage("splash_ring")
            ring.contentsGravity = .resize
            let rs = CABasicAnimation(keyPath: "transform.scale")
            rs.fromValue = 0.3; rs.toValue = 3.2; rs.duration = sp(0.55)
            let ro = CABasicAnimation(keyPath: "opacity")
            ro.fromValue = 0.9; ro.toValue = 0; ro.duration = sp(0.55)
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
                let ds: CGFloat = 8
                drop.bounds = CGRect(x: 0, y: 0, width: ds, height: ds)
                drop.position = c
                drop.contents = effectImage("splash_drop")
                drop.contentsGravity = .resize

                let peak = CGPoint(x: c.x + dx, y: c.y - dist * 0.95)
                let end  = CGPoint(x: c.x + dx * 1.25, y: c.y + 22)
                let pos = CAKeyframeAnimation(keyPath: "position")
                pos.values = [c, peak, end]
                pos.keyTimes = [0, 0.45, 1]
                pos.duration = sp(0.6)
                pos.timingFunctions = [
                    CAMediaTimingFunction(name: .easeOut),
                    CAMediaTimingFunction(name: .easeIn)
                ]
                let op = CABasicAnimation(keyPath: "opacity")
                op.fromValue = 1; op.toValue = 0; op.duration = sp(0.6)
                drop.opacity = 0
                drop.add(pos, forKey: "p"); drop.add(op, forKey: "o")
                layer.addSublayer(drop)
            }
        }
        e.close(after: sp(0.7))
    }

    /// 音符:在 point(屏幕坐标,鸟头上方)处 ♪ 上浮淡出
    static func notes(at point: CGPoint, on screen: NSScreen?) {
        let size = CGSize(width: 120, height: 120)
        let e = Effect(centeredAt: point, size: size, on: screen, level: .statusBar) { v in
            guard let layer = v.layer else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<3 {
                let t = CALayer()
                t.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
                t.contents = effectImage("note")
                t.contentsGravity = .resize
                t.position = CGPoint(x: c.x + CGFloat(i - 1) * 14, y: c.y)
                let now = CACurrentMediaTime()
                let stagger = sp(0.25)
                let pos = CABasicAnimation(keyPath: "position")
                pos.fromValue = NSValue(point: t.position)
                pos.toValue = NSValue(point: CGPoint(x: t.position.x, y: t.position.y + 40))
                pos.duration = sp(1.2)
                pos.beginTime = now + Double(i) * stagger
                pos.fillMode = .forwards
                let op = CAKeyframeAnimation(keyPath: "opacity")
                op.values = [0, 1, 1, 0]
                op.keyTimes = [0, 0.15, 0.7, 1]
                op.duration = sp(1.2)
                op.beginTime = now + Double(i) * stagger
                op.fillMode = .forwards
                t.opacity = 0
                t.add(pos, forKey: "p"); t.add(op, forKey: "o")
                layer.addSublayer(t)
            }
        }
        e.close(after: sp(1.6))
    }

    /// 睡眠 zzz(池化窗口):打盹每 0.9s 一个 z,原来每 tick 新建 NSWindow——
    /// 夜间 DarkWake 高频活动时窗口泄漏堆积几十个(实测 3 分钟 7→98),把机器拖死。
    /// 改为一个常驻复用窗口:每次只重建动画层,空闲 3s 自动 orderOut(窗口保留复用)。
    private static let zzzSize = CGSize(width: 90, height: 130)
    private static var zzzWin: NSWindow?
    private static var zzzLastAt: CFTimeInterval = 0
    private static var zzzIdleTimer: Timer?

    static func zzz(at point: CGPoint, on screen: NSScreen?) {
        let size = zzzSize
        let w: NSWindow
        if let existing = zzzWin {
            w = existing
            w.setFrameOrigin(CGPoint(x: point.x - size.width / 2, y: point.y))
        } else {
            w = NSWindow(contentRect: NSRect(x: point.x - size.width / 2, y: point.y,
                                             width: size.width, height: size.height),
                         styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.level = .statusBar
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces]   // 去 stationary(池化 zzz 窗也要能收干净)
            w.isReleasedWhenClosed = false
            let v = NSView(frame: NSRect(origin: .zero, size: size))
            v.wantsLayer = true
            v.layer = CALayer()
            w.contentView = v
            zzzWin = w
        }
        guard let layer = w.contentView?.layer else { return }
        w.orderFrontRegardless()

        // 重建动画层(旧的丢弃)
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let sz = CGFloat.random(in: 28...40)
        let z = CALayer()
        z.bounds = CGRect(x: 0, y: 0, width: sz, height: sz)
        z.contents = effectImage("zzz")
        z.contentsGravity = .resize
        let startX = size.width / 2 + CGFloat.random(in: -12...12)
        let startY: CGFloat = 14                        // 窗口底部 ≈ 鸟头
        z.position = CGPoint(x: startX, y: startY)

        let pos = CABasicAnimation(keyPath: "position")
        pos.fromValue = NSValue(point: CGPoint(x: startX, y: startY))
        pos.toValue = NSValue(point: CGPoint(x: startX + CGFloat.random(in: -18...18),
                                             y: size.height - 14))
        pos.duration = sp(1.8)
        let op = CAKeyframeAnimation(keyPath: "opacity")
        op.values = [0, 1, 1, 0]
        op.keyTimes = [0, 0.12, 0.7, 1]
        op.duration = sp(1.8)
        z.opacity = 0
        z.add(pos, forKey: "p"); z.add(op, forKey: "o")
        layer.addSublayer(z)

        // 空闲 3s(打盹结束)→ 收窗口(隐藏,保留复用)
        zzzLastAt = CACurrentMediaTime()
        if zzzIdleTimer == nil {
            let t = Timer(timeInterval: 1.0, repeats: true) { _ in
                if CACurrentMediaTime() - Effects.zzzLastAt > 3.0 {
                    Effects.zzzWin?.orderOut(nil)
                    Effects.zzzIdleTimer?.invalidate()
                    Effects.zzzIdleTimer = nil
                }
            }
            RunLoop.main.add(t, forMode: .common)
            zzzIdleTimer = t
        }
    }

    /// 日光浴的太阳:在 point 处一个旋转光芒 + 脉冲的太阳盘,持续 duration 秒
    static func sun(at point: CGPoint, on screen: NSScreen?, duration: TimeInterval) {
        // 硬上限:同时只允许 1 个太阳(防止睡眠唤醒等场景堆积几十个卡死)
        Effect.active.removeAll { $0 === sunEffectInstance }
        sunEffectInstance?.dismiss()
        let size = CGSize(width: 120, height: 120)
        let e = Effect(centeredAt: point, size: size, on: screen, level: .statusBar) { v in
            guard let layer = v.layer else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)

            // 太阳 = 光芒 + 圆盘 一体:container 整体脉冲(光芒+圆盘一起呼吸,不错位),光芒额外旋转
            let container = CALayer()
            container.bounds = CGRect(origin: .zero, size: size)
            container.position = c

            let rays = CALayer()
            rays.bounds = CGRect(origin: .zero, size: size)
            rays.position = CGPoint(x: size.width / 2, y: size.height / 2)
            rays.contents = effectImage("sun_rays")
            rays.contentsGravity = .resize
            let rot = CABasicAnimation(keyPath: "transform.rotation.z")
            rot.fromValue = 0.0
            rot.toValue = 2.0 * Double.pi
            rot.duration = 14
            rot.repeatCount = .infinity
            rays.add(rot, forKey: "r")

            let disk = CALayer()
            disk.bounds = CGRect(x: 0, y: 0, width: 58, height: 58)
            disk.position = CGPoint(x: size.width / 2, y: size.height / 2)
            disk.contents = effectImage("sun_disk")
            disk.contentsGravity = .resize

            container.addSublayer(rays)
            container.addSublayer(disk)

            // 整体脉冲(container scale → 光芒+圆盘一起放大缩小)
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.95
            pulse.toValue = 1.1
            pulse.duration = 1.4
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            container.add(pulse, forKey: "p")

            layer.addSublayer(container)
        }
        sunEffectInstance = e
        e.close(after: sp(duration))
    }
}
