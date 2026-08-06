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
    private var perchChecker: Timer?
    private var current = "idle"
    private var busy = false          // 正在执行一个多阶段动作
    private var onScreen = true       // 用户意图:是否可见

    private let size = CGSize(width: 160, height: 160)

    weak var shadow: ShadowController?            // 地面阴影(随太阳)
    weak var crack: CrackController?              // 屏幕裂纹(啄裂)

    var onWindow = false                          // 是否停在某个窗口上(停窗时不显示树枝)
    var dragging = false                          // 是否正在被拖拽(拖拽时不显示树枝)
    private var perchedID: CGWindowID?

    init(view: PetView, window: NSWindow) {
        self.view = view
        self.window = window
        view.delegate = self
        view.onMoved = { [weak self] in self?.shadow?.updateNow() }
    }

    // MARK: - 几何
    private var screen: NSScreen? { window?.screen ?? NSScreen.main }
    private var area: CGRect { screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero }

    // MARK: - 启动
    func start() {
        if !restorePosition() { placeAtBottomRight() }
        hatchIn()
    }

    // MARK: - 位置记忆
    private static let kX = "kingfisher.lastX"
    private static let kY = "kingfisher.lastY"

    func restorePosition() -> Bool {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.kX) != nil,
              let win = window, let scr = win.screen ?? NSScreen.main else { return false }
        let origin = CGPoint(x: d.double(forKey: Self.kX), y: d.double(forKey: Self.kY))
        let f = CGRect(origin: origin, size: size)
        // 中心点需在可见区内,避免恢复到已不存在的屏外位置
        if scr.visibleFrame.contains(CGPoint(x: f.midX, y: f.midY)) {
            win.setFrame(f, display: false)
            return true
        }
        return false
    }

    func savePosition() {
        guard let w = window else { return }
        UserDefaults.standard.set(Double(w.frame.origin.x), forKey: Self.kX)
        UserDefaults.standard.set(Double(w.frame.origin.y), forKey: Self.kY)
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
        dragging = true
        leavePerch()
        thinkTimer?.invalidate()
        enter("idle")
    }

    func petViewDidEndDrag() {
        dragging = false
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
        ["idle", "eat", "sing", "watch", "sun", "sleep", "happy", "poop"]
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
        let high = (window?.frame.minY ?? 0) > (area.maxY - area.height * 0.40)
        switch Int.random(in: 0..<100) {
        case 0..<22:   enter("idle"); scheduleThink()
        case 22..<42:  if high { enter("idle"); scheduleThink() } else { startWalk() }  // 高处不走
        case 42..<49:  startFly()
        case 49..<57:  startFish()
        case 57..<64:  startSing()
        case 64..<71:  startDart()
        case 71..<78:  startWatch()
        case 78..<83:  startSun()
        case 83..<88:  startPeck()
        case 88..<92:  startPerchWindow()
        case 92..<97:  startPoop()
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
        animateFlight(to: CGPoint(x: tx, y: ty), duration: 1.3) { [weak self] in self?.finish() }
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
        view?.facingRight = targetX > window.frame.midX
        enter("fly")
        let diveStart = CGPoint(x: targetX - halfW, y: topY)

        // 一律走自然轨迹飞到顶点 → 悬停 → 俯冲
        animateFlight(to: diveStart, duration: 1.0) { [weak self] in
            guard let self = self else { return }
            self.diveFish(targetX: targetX, diveY: diveY, topY: topY, a: a, window: window, hover: true)
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

    /// 自然鸟飞轨迹:三次贝塞尔(先平后升、顶端拉平)+ 拍翅的小幅起伏
    private func animateFlight(to end: CGPoint, duration: TimeInterval,
                               done: @escaping () -> Void) {
        guard let window = window else { done(); return }
        leavePerch()
        let start = window.frame.origin
        // 控制点:前方低位(先平飞)+ 目标高位附近(顶端拉平)
        let c1 = CGPoint(x: start.x + (end.x - start.x) * 0.35,
                         y: start.y + (end.y - start.y) * 0.15)
        let c2 = CGPoint(x: end.x - (end.x - start.x) * 0.15,
                         y: end.y - (end.y - start.y) * 0.10)
        let t0 = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] tm in
            guard let self = self, let w = self.window else { tm.invalidate(); done(); return }
            let t = min(1, (CACurrentMediaTime() - t0) / duration)
            let mt = 1 - t
            var x = mt*mt*mt*start.x + 3*mt*mt*t*c1.x + 3*mt*t*t*c2.x + t*t*t*end.x
            var y = mt*mt*mt*start.y + 3*mt*mt*t*c1.y + 3*mt*t*t*c2.y + t*t*t*end.y
            let bob = sin(t * .pi * 6)          // 拍翅起伏
            y += bob * 4
            x += bob * 1.5
            w.setFrameOrigin(CGPoint(x: x, y: y))
            self.shadow?.updateNow()
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

    // MARK: - 啄屏幕(连啄几次,每次以鸟嘴尖为中心随机啄裂)
    func startPeck() {
        busy = true; thinkTimer?.invalidate()
        peckBurst(remaining: Int.random(in: 3...5))
    }

    private func peckBurst(remaining: Int) {
        guard let w = window else { finish(); return }
        enter("peck")
        SpriteLibrary.shared.playPeep()
        // 头带动猛啄时,鸟嘴尖位置(按朝向)
        let facingRight = view?.facingRight ?? false
        let bx = w.frame.minX + (facingRight ? 128 : 6)
        let by = w.frame.minY + 92
        if Int.random(in: 0..<100) < 15 {          // 随机啄裂,不频繁
            crack?.addCrack(at: CGPoint(x: bx, y: by))
        }
        hold(0.3) { [weak self] in
            guard let self = self else { return }
            if remaining > 1 {
                self.peckBurst(remaining: remaining - 1)
            } else {
                self.finish()
            }
        }
    }

    // MARK: - 停到最前面窗口的上沿(随机;窗口移走就飞走)
    func startPerchWindow() {
        guard let window = window, let scr = screen,
              let perch = WindowTracker.frontPerch(birdWidth: size.width) else { finish(); return }
        busy = true; thinkTimer?.invalidate()
        enter("fly")
        let a = scr.visibleFrame
        let tx = max(a.minX, min(perch.point.x, a.maxX - size.width))
        let ty = max(a.minY, min(perch.point.y, a.maxY - size.height))
        view?.facingRight = tx > window.frame.origin.x
        animateFlight(to: CGPoint(x: tx, y: ty), duration: 1.1) { [weak self] in
            guard let self = self else { return }
            self.onWindow = true
            self.perchedID = perch.id
            self.startPerchCheck()
            self.finish()
        }
    }

    private func leavePerch() {
        onWindow = false
        perchedID = nil
        stopPerchCheck()
    }
    private func startPerchCheck() {
        stopPerchCheck()
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.checkPerch() }
        RunLoop.main.add(t, forMode: .common)
        perchChecker = t
    }
    private func stopPerchCheck() {
        perchChecker?.invalidate()
        perchChecker = nil
    }
    private func checkPerch() {
        guard let wid = perchedID, let scr = screen, let w = window,
              let f = WindowTracker.frameOfWindow(id: wid) else {
            leavePerch(); startFly(); return                 // 窗口没了 → 飞走
        }
        let topY = scr.frame.height - f.minY
        if abs(topY - w.frame.minY) > 24 || abs(f.midX - w.frame.midX) > 120 {
            leavePerch(); startFly()                          // 窗口挪了 → 飞走
        }
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
        // 头在左上:从头部上方出 z,贴近头
        Effects.zzz(at: CGPoint(x: w.frame.minX + 46, y: w.frame.maxY - 30), on: screen)
    }
    private func stopZzz() { zzzTimer?.invalidate(); zzzTimer = nil }

    // MARK: - 吃完拉屎
    private func schedulePoop(after t: TimeInterval) {
        poopTimer?.invalidate()
        poopTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
            self?.startPoop()
        }
    }

    /// 拉屎(自主随机 / 吃完延时触发)
    func startPoop() {
        guard onScreen, let w = window else { finish(); return }
        busy = true
        thinkTimer?.invalidate()
        enter("poop")
        let facingRight = view?.facingRight ?? false
        let buttX = w.frame.midX + (facingRight ? -44 : 44)   // 屁股在尾部一侧
        let buttY = w.frame.minY + 50
        hold(0.5) { [weak self] in
            guard let self = self else { return }
            Effects.poop(at: CGPoint(x: buttX, y: buttY), on: self.screen)
            self.hold(0.4) { self.finish() }
        }
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
                // 隐藏期间把帧切成 egg,下次显示不再闪现 dead
                self.view?.state = "egg"
                self.view?.applyNow()
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
    /// 线性移动(无缓动),每步同步刷新阴影,避免阴影延迟
    private func animateWindow(to origin: CGPoint, duration: TimeInterval, done: @escaping () -> Void) {
        guard let window = window else { done(); return }
        leavePerch()
        let start = window.frame.origin
        let t0 = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] tm in
            guard let self = self, let w = self.window else { tm.invalidate(); done(); return }
            let t = min(1, (CACurrentMediaTime() - t0) / duration)
            w.setFrameOrigin(CGPoint(x: start.x + (origin.x - start.x) * t,
                                     y: start.y + (origin.y - start.y) * t))
            self.shadow?.updateNow()
            if t >= 1 { tm.invalidate(); done() }
        }
        RunLoop.main.add(timer, forMode: .common)
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
