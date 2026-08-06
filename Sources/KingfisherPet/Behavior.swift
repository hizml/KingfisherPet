import AppKit
import Foundation

/// 宠物行为状态机:idle / walk / fly / hover / dive / fly_fish / eat / sing /
/// dart / watch / sun / sleep / happy / egg / dead,并移动窗口、触发特效。
final class Behavior: PetViewDelegate {

    private weak var window: NSWindow?
    private weak var view: PetView?

    private var thinkTimer: Timer?
    private var poopTimer: Timer?
    private var zzzTimer: Timer?
    private var current = "idle"
    private var busy = false          // 正在执行一个多阶段动作
    private var onScreen = true       // 用户意图:是否可见

    private let size = CGSize(width: 160, height: 160)

    weak var shadow: ShadowController?            // 地面阴影(随太阳)

    init(view: PetView, window: NSWindow) {
        self.view = view
        self.window = window
        view.delegate = self
    }

    // MARK: - 几何
    private var screen: NSScreen? { window?.screen ?? NSScreen.main }
    private var area: CGRect { screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero }

    // MARK: - 启动
    func start() {
        placeAtBottomRight()
        hatchIn()
    }

    // MARK: - PetViewDelegate
    func petViewWasClicked() {
        SpriteLibrary.shared.playPeep()
        enter("happy")
        busy = true
        hold(0.8) { [weak self] in
            guard let self = self, self.current == "happy" else { return }
            self.finish()
        }
    }

    func petViewDidBeginDrag() {
        busy = true
        thinkTimer?.invalidate()
        enter("idle")
    }

    func petViewDidEndDrag() {
        finish()
    }

    // MARK: - 状态
    private func enter(_ s: String) {
        current = s
        view?.state = s
        if s != "sleep" { stopZzz() }
    }

    /// 是否处于"停靠歇脚"状态(非飞行/俯冲/死亡/蛋)——供树枝控制器判断
    private static let restingStates: Set<String> =
        ["idle", "walk", "eat", "sing", "watch", "sun", "sleep", "happy", "poop"]
    func isResting() -> Bool { Self.restingStates.contains(current) }
    private func finish() { busy = false; enter("idle"); scheduleThink() }
    private func hold(_ t: TimeInterval, _ done: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: done)
    }

    // MARK: - 定时思考
    private func scheduleThink() {
        thinkTimer?.invalidate()
        let delay = Double.random(in: 3.5...7.0)
        thinkTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.think()
        }
    }

    private func think() {
        guard !busy else { scheduleThink(); return }
        switch Int.random(in: 0..<100) {
        case 0..<25:   enter("idle"); scheduleThink()
        case 25..<47:  startWalk()
        case 47..<55:  startFly()
        case 55..<63:  startFish()
        case 63..<71:  startSing()
        case 71..<79:  startDart()
        case 79..<87:  startWatch()
        case 87..<92:  startSun()
        default:       startSleep()
        }
    }

    // MARK: - 走
    private func startWalk() {
        guard let window = window, screen != nil else { finish(); return }
        busy = true; thinkTimer?.invalidate()
        enter("walk")
        let a = area, cur = window.frame.origin
        let step = CGFloat.random(in: 60...180) * (Bool.random() ? 1 : -1)
        var tx = cur.x + step
        tx = max(a.minX + 8, min(tx, a.maxX - size.width - 8))
        view?.facingRight = tx > cur.x
        let dist = abs(tx - cur.x)
        animateWindow(to: CGPoint(x: tx, y: cur.y),
                      duration: max(0.6, Double(dist) / 90.0)) { [weak self] in self?.finish() }
    }

    // MARK: - 飞(随机挪窝,偶尔空中拉屎)
    private func startFly() {
        guard let window = window, screen != nil else { finish(); return }
        busy = true; thinkTimer?.invalidate()
        enter("fly")
        let a = area
        let tx = CGFloat.random(in: a.minX + 8 ... a.maxX - size.width - 8)
        let ty = Bool.random() ? (a.maxY - size.height) : a.minY
        view?.facingRight = tx < window.frame.origin.x ? false : true
        if Int.random(in: 0..<100) < 35 {
            hold(Double.random(in: 0.3...0.7)) { [weak self] in self?.airPoop() }
        }
        animateWindow(to: CGPoint(x: tx, y: ty), duration: 1.3) { [weak self] in self?.finish() }
    }

    /// 空中拉屎:从鸟当前(飞行中)位置往下掉一坨
    private func airPoop() {
        guard let w = window else { return }
        let facingRight = view?.facingRight ?? false
        let x = w.frame.midX + (facingRight ? -44 : 44)
        let y = w.frame.minY + 30
        Effects.poop(at: CGPoint(x: x, y: y), on: screen)
    }

    // MARK: - 俯冲捕鱼(招牌):抛物线上顶→悬停→直下俯冲;已在高位则直线俯冲
    func startFish() {
        guard let window = window, let scr = screen else { finish(); return }
        busy = true; thinkTimer?.invalidate()
        let a = scr.visibleFrame
        let topY = a.maxY - size.height
        let diveY = a.minY
        let halfW = size.width / 2
        let targetX = CGFloat.random(in: (a.minX + halfW + 40) ... max(a.minX + halfW + 41, a.maxX - halfW - 40))
        let alreadyHigh = window.frame.minY > a.maxY - a.height * 0.35
        view?.facingRight = targetX > window.frame.midX
        enter("fly")
        let diveStart = CGPoint(x: targetX - halfW, y: topY)

        if alreadyHigh {
            // 已在最顶端:直接朝目标直线俯冲(不悬停)
            diveFish(targetX: targetX, diveY: diveY, topY: topY, a: a, window: window, hover: false)
        } else {
            // 抛物线飞到顶点
            animateArc(to: diveStart, duration: 1.0, apexDy: 70) { [weak self] in
                guard let self = self else { return }
                self.diveFish(targetX: targetX, diveY: diveY, topY: topY, a: a, window: window, hover: true)
            }
        }
    }

    /// 俯冲入水 + 水花 + 叼鱼回栖 + 仰头吞(hover=true 时先悬停瞄准)
    private func diveFish(targetX: CGFloat, diveY: CGFloat, topY: CGFloat,
                          a: CGRect, window: NSWindow, hover: Bool) {
        let halfW = size.width / 2
        let go = { [weak self] in
            guard let self = self else { return }
            self.enter("dive")
            self.animateWindow(to: CGPoint(x: targetX - halfW, y: diveY), duration: 0.45) { [weak self] in
                guard let self = self else { return }
                Effects.splash(at: CGPoint(x: targetX, y: diveY + 8), on: self.screen)
                self.enter("fly_fish")
                let perchX = CGFloat.random(in: (a.minX + 30) ... max(a.minX + 31, a.maxX - self.size.width - 30))
                let perchY = Bool.random() ? topY : (a.minY + 20)
                self.view?.facingRight = perchX > window.frame.origin.x
                self.animateWindow(to: CGPoint(x: perchX, y: perchY), duration: 0.95) { [weak self] in
                    guard let self = self else { return }
                    self.enter("eat")
                    SpriteLibrary.shared.playPeep()
                    self.hold(1.1) {
                        self.finish()
                        self.schedulePoop(after: Double.random(in: 4...7))
                    }
                }
            }
        }
        if hover {
            enter("hover")
            hold(0.7, go)
        } else {
            go()
        }
    }

    /// 沿二次贝塞尔(抛物线)从当前位置飞到 end,顶点抬升 apexDy
    private func animateArc(to end: CGPoint, duration: TimeInterval, apexDy: CGFloat,
                            done: @escaping () -> Void) {
        guard let window = window else { done(); return }
        let start = window.frame.origin
        let ctrl = CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + apexDy)
        let t0 = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] tm in
            guard let self = self, let w = self.window else { tm.invalidate(); done(); return }
            let t = min(1, (CACurrentMediaTime() - t0) / duration)
            let mt = 1 - t
            let x = mt * mt * start.x + 2 * mt * t * ctrl.x + t * t * end.x
            let y = mt * mt * start.y + 2 * mt * t * ctrl.y + t * t * end.y
            w.setFrameOrigin(CGPoint(x: x, y: y))
            if t >= 1 { tm.invalidate(); done() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - 鸣唱
    func startSing() {
        busy = true; thinkTimer?.invalidate()
        enter("sing")
        Effects.notes(at: CGPoint(x: window?.frame.midX ?? 0,
                                  y: (window?.frame.maxY ?? 0) + 14), on: screen)
        SpriteLibrary.shared.playPeep()
        hold(Double.random(in: 1.2...1.6)) { [weak self] in self?.finish() }
    }

    // MARK: - 低空快飞掠过
    func startDart() {
        guard let window = window, screen != nil else { finish(); return }
        busy = true; thinkTimer?.invalidate()
        enter("fly")
        let a = area
        let toLeft = Bool.random()
        let tx = toLeft ? (a.minX + 20) : (a.maxX - size.width - 20)
        view?.facingRight = !toLeft
        animateWindow(to: CGPoint(x: tx, y: window.frame.origin.y),
                      duration: 0.55) { [weak self] in self?.finish() }
    }

    // MARK: - 栖枝守候探头
    func startWatch() {
        busy = true; thinkTimer?.invalidate()
        enter("watch")
        hold(Double.random(in: 1.4...2.2)) { [weak self] in self?.finish() }
    }

    // MARK: - 日光浴(彩蛋)
    func startSun() {
        busy = true; thinkTimer?.invalidate()
        enter("sun")
        hold(Double.random(in: 3...5)) { [weak self] in self?.finish() }
    }

    // MARK: - 打盹
    func startSleep() {
        busy = true; thinkTimer?.invalidate()
        enter("sleep")
        startZzz()
        hold(Double.random(in: 5...9)) { [weak self] in
            guard let self = self, self.current == "sleep" else { return }
            self.finish()
        }
    }

    private func startZzz() {
        zzzTimer?.invalidate()
        emitZzz()
        zzzTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            self?.emitZzz()
        }
    }
    private func emitZzz() {
        guard let w = window else { return }
        Effects.zzz(at: CGPoint(x: w.frame.midX, y: w.frame.maxY + 6), on: screen)
    }
    private func stopZzz() { zzzTimer?.invalidate(); zzzTimer = nil }

    // MARK: - 吃完拉屎
    private func schedulePoop(after t: TimeInterval) {
        poopTimer?.invalidate()
        poopTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
            self?.tryPoop()
        }
    }

    private func tryPoop() {
        guard !busy, onScreen, let w = window else { return }
        busy = true
        thinkTimer?.invalidate()
        enter("poop")
        let facingRight = view?.facingRight ?? false
        let buttX = w.frame.midX + (facingRight ? -44 : 44)   // 屁股在尾部一侧
        let buttY = w.frame.minY + 50
        hold(0.5) { [weak self] in
            guard let self = self else { return }
            Effects.poop(at: CGPoint(x: buttX, y: buttY), on: self.screen)
        }
        hold(0.9) { [weak self] in self?.finish() }
    }

    // MARK: - 显示:破壳而出
    func hatchIn() {
        busy = true; thinkTimer?.invalidate()
        onScreen = true
        enter("egg")
        view?.applyNow()                  // 先刷成 egg_0,避免闪现 dead 残影
        shadow?.setVisible(true)
        window?.makeKeyAndOrderFront(nil)
        hold(1.4) { [weak self] in
            guard let self = self else { return }
            self.finish()
        }
    }

    // MARK: - 隐藏:死掉 → 自由落体掉出屏幕
    func fallAway() {
        guard let window = window, let scr = screen else { onScreen = false; return }
        busy = true; thinkTimer?.invalidate()
        onScreen = false
        enter("dead")
        let a = scr.visibleFrame
        let startX = window.frame.origin.x
        hold(0.3) { [weak self] in
            guard let self = self else { return }
            let endY = a.minY - self.size.height - 400
            self.animateWindow(to: CGPoint(x: startX, y: endY), duration: 0.85) { [weak self] in
                guard let self = self else { return }
                self.window?.orderOut(nil)
                self.shadow?.setVisible(false)
                self.busy = false
            }
        }
    }

    // MARK: - 外部控制
    func callOver() {
        guard let window = window, let scr = screen else { return }
        busy = false; thinkTimer?.invalidate()
        enter("fly")
        let a = scr.visibleFrame
        let mx = NSEvent.mouseLocation.x
        let tx = max(a.minX + 8, min(mx - size.width / 2, a.maxX - size.width - 8))
        let ty = a.minY + a.height * 0.55
        view?.facingRight = tx > window.frame.origin.x
        animateWindow(to: CGPoint(x: tx, y: ty), duration: 1.0) { [weak self] in
            self?.finish()
        }
    }

    func toggleVisibility() { setVisible(!onScreen) }
    func setVisible(_ visible: Bool) {
        if visible { if !onScreen { placeAtBottomRight(); hatchIn() } }
        else { if onScreen { fallAway() } }
    }
    var isVisible: Bool { onScreen }

    // MARK: - 工具
    private func animateWindow(to origin: CGPoint, duration: TimeInterval, done: @escaping () -> Void) {
        guard let window = window else { done(); return }
        var f = window.frame
        f.origin = origin
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(f, display: true)
        }, completionHandler: done)
    }

    private func placeAtBottomRight() {
        guard let window = window, screen != nil else { return }
        let a = area
        // 默认栖息在屏幕底部(桌面/Dock 上),这样影子落在脚下、连贯
        let origin = CGPoint(x: a.maxX - size.width - 30, y: a.minY)
        // display:false —— 不立即按旧内容重绘,避免重新显示时闪现 dead 帧
        window.setFrame(CGRect(origin: origin, size: size), display: false)
    }
}
