import AppKit
import QuartzCore

/// 访客鸟(v1.5.x batch2):短命 overlay 窗(点击穿透,zzz 池化同款基建),
/// 三种演出:①访客飞过并在本鸟旁对唱 ②孵化彩蛋的蛋摇摆 ③小鸟跟班绕飞。
/// 访客不是第二套行为机——只是一条路径 + 帧序列,播完即收。
/// Windows 侧对称:poop 舞台窗 fx 事件(kind=visitor/egg)。
final class VisitorService {

    static let shared = VisitorService()

    /// 池化窗(一次建好反复用;同时只允许一场演出,后来的顶掉先来的)
    private var win: NSWindow?
    private var layer: CALayer?
    private var timer: Timer?

    // MARK: - 演出 1:访客飞过(从屏边进 → 本鸟旁停 ~2.2s 对唱 → 飞出)
    /// birdSings:访客落定开唱时回调(本鸟应答一声;由 Behavior 注入)
    func visitorPass(near birdFrame: CGRect, on screen: NSScreen?, birdSings: @escaping () -> Void) {
        let area = screen?.visibleFrame ?? birdFrame
        let fromLeft = Bool.random()
        let enter = CGPoint(x: fromLeft ? area.minX - 160 : area.maxX + 160,
                            y: area.midY + CGFloat.random(in: 40...140))
        // 停留点:本鸟斜上方(读作"落在旁边聊两句")
        var stop = CGPoint(x: birdFrame.midX + (fromLeft ? 90 : -90),
                           y: birdFrame.midY + 60)
        stop.x = min(max(stop.x, area.minX + 90), area.maxX - 90)
        stop.y = min(max(stop.y, area.minY + 200), area.maxY - 90)
        let exit = CGPoint(x: fromLeft ? area.maxX + 160 : area.minX - 160,
                           y: area.midY + CGFloat.random(in: 0...120))
        runFlight(points: [enter, stop, exit], total: 8.0, screen: screen, scale: 1.0,
                  pauseAt: 0.42, pauseDur: 2.2) { [weak self] in
            self?.showVisitor(seqName: "visitor_sing", t: CACurrentMediaTime())
            birdSings()
        }
    }

    // MARK: - 演出 2:孵化彩蛋的蛋(原地摇摆 ~2.4s 后收窗;破壳瞬间由调用方接小鸟)
    func eggWobble(at point: CGPoint, on screen: NSScreen?) {
        prepareWindow(screen: screen)
        guard let layer else { return }
        placeWindow(center: point, size: 140, screen: screen, scale: 1.0)
        layer.contents = SpriteLibrary.shared.frame("egg_0")?.image
        var t: CFTimeInterval = 0
        startTimer(0.24) { [weak self] tick in
            guard let self else { return false }
            t += 0.24
            if t >= 2.4 { self.hide(); return false }
            // egg_1/egg_2 交替 = 摇摆;每四拍回 egg_0 = 静止蓄力
            let name = (tick % 4 == 3) ? "egg_0" : ((tick % 2 == 0) ? "egg_1" : "egg_2")
            layer.contents = SpriteLibrary.shared.frame(name)?.image
            return true
        }
    }

    // MARK: - 演出 3:小鸟跟班(0.6×,绕本鸟两圈后飞走)
    func childFlight(around birdFrame: CGRect, on screen: NSScreen?) {
        let c = CGPoint(x: birdFrame.midX, y: birdFrame.midY)
        let r: CGFloat = 130
        // 两圈采样成路径点(每 15° 一点),结尾拉远飞出
        var pts: [CGPoint] = []
        for i in 0..<48 {
            let a = CGFloat(i) / 48.0 * 4 * .pi
            pts.append(CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * 0.7))
        }
        pts.append(CGPoint(x: c.x + r * 2.4, y: c.y + r * 1.5))
        runFlight(points: pts, total: 5.5, screen: screen, scale: 0.6,
                  pauseAt: nil, pauseDur: 0, onArrivePause: nil)
    }

    // MARK: - 路径飞行基建(单停留点语义,当前所有演出最多一处停留)

    /// 沿折线匀速飞;总时长 total;pauseAt(飞行进度 0–1, nil=不停留)处停留 pauseDur 秒,
    /// 停留开始后调 onArrivePause(本鸟应答口)。停留期间播 idle/sing,飞行播 fly 帧。
    private func runFlight(points: [CGPoint], total: CFTimeInterval, screen: NSScreen?,
                           scale: CGFloat, pauseAt: Double?, pauseDur: CFTimeInterval,
                           onArrivePause: (() -> Void)?) {
        prepareWindow(screen: screen)
        guard let layer, points.count >= 2 else { return }
        placeWindow(center: points[0], size: 160, screen: screen, scale: scale)
        let flyDur = max(0.1, total - pauseDur)
        let pauseStart: CFTimeInterval? = pauseAt.map { $0 * flyDur }
        let flySeq = SpriteLibrary.shared.sequence("visitor_fly") ?? ["visitor_fly_2"]
        let idleSeq = SpriteLibrary.shared.sequence("visitor_idle") ?? ["visitor_idle_0"]
        var arrived = false
        var t: CFTimeInterval = 0
        let dt = 1.0 / 30.0
        startTimer(dt) { [weak self] _ in
            guard let self else { return false }
            t += dt
            if t >= total { self.hide(); return false }
            let inPause = pauseStart.map { t >= $0 && t < $0 + pauseDur } ?? false
            if inPause {
                if !arrived, t >= (pauseStart ?? 0) + 0.3 {   // 落定半拍后:开唱 + 本鸟应答
                    arrived = true
                    onArrivePause?()
                }
                // 停留前段 idle 张望,应答后转 sing(对唱)
                let seqNow = arrived ? (SpriteLibrary.shared.sequence("visitor_sing") ?? idleSeq) : idleSeq
                let idx = Int(t / 0.2) % seqNow.count
                layer.contents = SpriteLibrary.shared.frame(seqNow[idx])?.image
            } else {
                let tt = inPauseIsBehind(t: t, pauseStart: pauseStart, pauseDur: pauseDur)
                let prog = min(1.0, tt / flyDur)
                moveWindow(center: interpolate(points: points, t: prog))
                let idx = Int(t / 0.12) % flySeq.count
                layer.contents = SpriteLibrary.shared.frame(flySeq[idx])?.image
            }
            return true
        }
    }

    /// 当前时刻对应的飞行时长(停留段不推进;停留结束后把暂停时长扣除)
    private func inPauseIsBehind(t: CFTimeInterval, pauseStart: CFTimeInterval?, pauseDur: CFTimeInterval) -> CFTimeInterval {
        guard let ps = pauseStart, t >= ps + pauseDur else { return t }
        return t - pauseDur
    }

    /// 停留期外部想换帧给 visitor_sing(应答回调里同步换唱姿,免等下一拍)
    private func showVisitor(seqName: String, t: CFTimeInterval) {
        let seq = SpriteLibrary.shared.sequence(seqName) ?? ["visitor_idle_0"]
        let idx = Int(t / 0.2) % seq.count
        layer?.contents = SpriteLibrary.shared.frame(seq[idx])?.image
    }

    private func interpolate(points: [CGPoint], t: Double) -> CGPoint {
        let n = points.count - 1
        let f = max(0, min(1, t)) * Double(n)
        let i = min(n - 1, Int(f))
        let seg = CGFloat(f - Double(i))
        return CGPoint(x: points[i].x + (points[i+1].x - points[i].x) * seg,
                       y: points[i].y + (points[i+1].y - points[i].y) * seg)
    }

    // MARK: - 窗与定时器

    private func prepareWindow(screen: NSScreen?) {
        cancelTimer()
        if win == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 160),
                             styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.level = .floating          // 与本鸟同层(盖阴影,不盖裂纹层)
            w.ignoresMouseEvents = true  // 点击穿透:访客是风景,不是交互对象
            w.collectionBehavior = [.canJoinAllSpaces]
            w.isReleasedWhenClosed = false
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: 160))
            v.wantsLayer = true
            let l = CALayer()
            l.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
            l.contentsGravity = .resize
            v.layer = l
            w.contentView = v
            layer = l
            win = w
        }
        win?.orderFrontRegardless()
    }

    private func placeWindow(center: CGPoint, size: CGFloat, screen: NSScreen?, scale: CGFloat) {
        let s = size * scale
        win?.setFrame(CGRect(x: center.x - s / 2, y: center.y - s / 2, width: s, height: s),
                      display: false)
        layer?.frame = CGRect(x: 0, y: 0, width: s, height: s)
        // 缩放靠 contentsGravity=resize 拉伸帧(素材 256²,缩 0.6 质量足够)
    }

    private func moveWindow(center: CGPoint) {
        guard let f = win?.frame else { return }
        win?.setFrameOrigin(CGPoint(x: center.x - f.width / 2, y: center.y - f.height / 2))
    }

    private func startTimer(_ interval: TimeInterval, _ step: @escaping (Int) -> Bool) {
        var tick = 0
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] tm in
            guard let self else { tm.invalidate(); return }
            tick += 1
            if !step(tick) { tm.invalidate(); self.timer = nil }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func hide() {
        win?.orderOut(nil)
        cancelTimer()
    }
}
