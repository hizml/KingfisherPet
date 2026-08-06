import AppKit
import Foundation

/// 宠物行为状态机。用 gen(代际)保证新动作/拖动能取消进行中的动作链(拖动优先级最高)。
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
    private var gen = 0               // 动作代际;新动作/拖动 bump,旧的 hold/动画自动作废

    private let size = CGSize(width: 160, height: 160)
    private let feetOffset: CGFloat = 27   // 脚距窗口底部约 27px(按 sprite 脚趾坐标)

    weak var shadow: ShadowController?
    weak var crack: CrackController?
    weak var poopCtl: PoopController?
    weak var branch: BranchController?

    var onWindow = false
    var dragging = false
    private var perchedID: CGWindowID?

    init(view: PetView, window: NSWindow) {
        self.view = view
        self.window = window
        view.delegate = self
        view.onMoved = { [weak self] in self?.shadow?.updateNow() }
    }

    /// 开始一个新动作:取消所有进行中的 hold/动画/定时器(代际 bump)
    private func beginAction() {
        gen &+= 1
        busy = true
        thinkTimer?.invalidate()
        poopTimer?.invalidate()
        stopZzz()
        leavePerch()
    }

    // MARK: - 几何
    private var screen: NSScreen? { window?.screen ?? NSScreen.main }
    private var area: CGRect { screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero }

    /// 把窗口原点限制在屏内:脚不低于 Dock 顶、头不超屏顶、横向不出界
    private func clamp(_ origin: CGPoint) -> CGPoint {
        let a = area
        let minX = a.minX
        let maxX = a.maxX - size.width
        let minY = a.minY - feetOffset     // 脚可到 Dock 顶
        let maxY = a.maxY - size.height
        return CGPoint(x: min(max(origin.x, minX), maxX),
                       y: min(max(origin.y, minY), maxY))
    }

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
        let origin = clamp(CGPoint(x: d.double(forKey: Self.kX), y: d.double(forKey: Self.kY)))
        let f = CGRect(origin: origin, size: size)
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

    // MARK: - PetViewDelegate(拖动优先级最高)
    func petViewWasClicked() {
        beginAction()
        SpriteLibrary.shared.playPeep()
        enter("happy")
        hold(0.8) { [weak self] in
            guard let self = self, self.current == "happy" else { return }
            self.finish()
        }
    }

    func petViewDidBeginDrag() {
        beginAction()          // 取消一切进行中的动作
        dragging = true
        enter("idle")
    }

    func petViewDidEndDrag() {
        dragging = false
        if isAirborne() {
            startFly()          // 空中松手 → 自己飞走落下
        } else {
            finish()
        }
    }

    /// 脚下没有近表面(Dock/窗口)= 在空中
    private func isAirborne() -> Bool {
        guard let w = window, let scr = screen else { return true }
        let ground = scr.visibleFrame.minY + 6
        let feetY = w.frame.minY + feetOffset
        let (ly, _) = WindowTracker.landingSpot(belowX: w.frame.midX,
                                                fromY: feetY + 40, groundY: ground)
        return abs(ly - feetY) > 30
    }

    // MARK: - 状态
    private func enter(_ s: String) {
        current = s
        view?.state = s
        if s != "sleep" { stopZzz() }
    }

    private static let restingStates: Set<String> =
        ["idle", "eat", "sing", "watch", "sun", "sleep", "happy", "poop", "peck"]
    func isResting() -> Bool { Self.restingStates.contains(current) }
    private func finish() { busy = false; enter("idle"); scheduleThink() }

    /// 延时回调;捕获当前代际,bump 后自动作废(避免被取消的动作继续推进)
    private func hold(_ t: TimeInterval, _ done: @escaping () -> Void) {
        let g = gen
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
            guard let self = self, self.gen == g else { return }
            done()
        }
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
        let onWin = onWindow
        let isLow = (window?.frame.minY ?? 0) < (area.minY + 60)   // Dock 附近
        switch Int.random(in: 0..<100) {
        case 0..<22:   enter("idle"); scheduleThink()
        case 22..<42:  if onWin || isLow { startWalk() }        // 只在 窗口/Dock 上走
                       else { enter("idle"); scheduleThink() }  // 树枝上不走路
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

    // MARK: - 走(沿下方表面:Dock 顶 / 窗口上沿;在窗口上走到边就飞走)
    private func startWalk() {
        guard let window = window, screen != nil else { finish(); return }
        let onWin = onWindow                 // 先记下(beginAction 会清)
        let wid = perchedID
        beginAction()
        enter("walk")
        let a = area
        let dir: CGFloat = Bool.random() ? 1 : -1
        let dist = CGFloat.random(in: 80...200)
        let startX = window.frame.origin.x
        let raw = startX + dir * dist
        var loX = a.minX + 8
        var hiX = a.maxX - size.width - 8
        if onWin, let id = wid, let b = WindowTracker.frameOfWindow(id: id) {
            loX = b.minX
            hiX = max(b.minX, b.maxX - size.width)
        }
        let targetX = min(max(raw, loX), hiX)
        if abs(targetX - startX) < 20 { finish(); return }
        let hitEdge = onWin && (raw < loX || raw > hiX)      // 想走更远但到窗口边了
        view?.facingRight = targetX > startX
        walkStep(startX: startX, to: targetX,
                 duration: max(0.6, Double(abs(targetX - startX)) / 70),
                 onWin: onWin, wid: wid, flyOff: hitEdge)
    }

    private func walkStep(startX: CGFloat, to targetX: CGFloat, duration: TimeInterval,
                          onWin: Bool, wid: CGWindowID?, flyOff: Bool) {
        guard let w = window else { finish(); return }
        let y = w.frame.origin.y              // 表面是平的:行走时高度不变(避免瞬移)
        let g = gen
        let t0 = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] tm in
            guard let self = self, let w = self.window else { tm.invalidate(); return }
            guard self.gen == g else { tm.invalidate(); return }       // 被取消
            let t = min(1, (CACurrentMediaTime() - t0) / duration)
            let x = startX + (targetX - startX) * t
            w.setFrameOrigin(self.clamp(CGPoint(x: x, y: y)))
            self.shadow?.updateNow()
            if t >= 1 {
                tm.invalidate()
                self.afterWalk(onWin: onWin, wid: wid, flyOff: flyOff)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// 走完:在窗口上走到边 → 飞走(下一个窗口/别处);窗口没了 → 飞走;否则留下
    private func afterWalk(onWin: Bool, wid: CGWindowID?, flyOff: Bool) {
        if onWin, let id = wid {
            if flyOff || WindowTracker.frameOfWindow(id: id) == nil {
                if Bool.random() { startPerchWindow() } else { startFly() }
            } else {
                onWindow = true; perchedID = id; startPerchCheck()
                finish()
            }
        } else {
            finish()
        }
    }

    // MARK: - 飞(随机挪窝,偶尔空中拉屎)
    private func startFly() {
        guard let window = window, screen != nil else { finish(); return }
        beginAction()
        enter("fly")
        let a = area
        let tx = CGFloat.random(in: a.minX + 8 ... a.maxX - size.width - 8)
        let ty = Bool.random() ? (a.maxY - size.height) : (a.minY - feetOffset)
        view?.facingRight = tx > window.frame.origin.x
        // 飞往高处歇脚:树枝提前在目的地出现
        if ty > a.maxY - a.height * 0.4 {
            branch?.showAt(CGPoint(x: tx + size.width / 2, y: ty + feetOffset))
        }
        if Int.random(in: 0..<100) < 35 {
            hold(Double.random(in: 0.3...0.7)) { [weak self] in self?.airPoop() }
        }
        animateFlight(to: clamp(CGPoint(x: tx, y: ty)), duration: 1.3) { [weak self] in self?.finish() }
    }

    /// 空中拉屎:从鸟当前(飞行中)的屁股位置往下掉
    private func airPoop() {
        guard let w = window else { return }
        let facingRight = view?.facingRight ?? false
        let x = w.frame.midX + (facingRight ? -50 : 50)
        let y = w.frame.minY + 40
        poopCtl?.dropPoop(at: CGPoint(x: x, y: y))
    }

    // MARK: - 俯冲捕鱼(招牌):自然轨迹上顶→悬停→直下俯冲
    func startFish() {
        guard let window = window, let scr = screen else { finish(); return }
        beginAction()
        let a = scr.visibleFrame
        let topY = a.maxY - size.height
        let diveY = a.minY
        let halfW = size.width / 2
        let targetX = CGFloat.random(in: (a.minX + halfW + 40) ... max(a.minX + halfW + 41, a.maxX - halfW - 40))
        view?.facingRight = targetX > window.frame.midX
        enter("fly")
        let diveStart = CGPoint(x: targetX - halfW, y: topY)
        animateFlight(to: diveStart, duration: 1.0) { [weak self] in
            guard let self = self else { return }
            self.diveFish(targetX: targetX, diveY: diveY, topY: topY, a: a, window: window, hover: true)
        }
    }

    private func diveFish(targetX: CGFloat, diveY: CGFloat, topY: CGFloat,
                          a: CGRect, window: NSWindow, hover: Bool) {
        let halfW = size.width / 2
        let go = { [weak self] in
            guard let self = self else { return }
            self.enter("dive")
            self.animateWindow(to: CGPoint(x: targetX - halfW, y: diveY), duration: 0.45) {
                self.enter("fly_fish")
                Effects.splash(at: CGPoint(x: targetX, y: diveY + 8), on: self.screen)
                let perchX = CGFloat.random(in: (a.minX + 30) ... max(a.minX + 31, a.maxX - self.size.width - 30))
                let perchY = Bool.random() ? topY : (a.minY - self.feetOffset)
                self.view?.facingRight = perchX > window.frame.origin.x
                self.animateWindow(to: self.clamp(CGPoint(x: perchX, y: perchY)), duration: 0.95) {
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
        let c1 = CGPoint(x: start.x + (end.x - start.x) * 0.35,
                         y: start.y + (end.y - start.y) * 0.15)
        let c2 = CGPoint(x: end.x - (end.x - start.x) * 0.15,
                         y: end.y - (end.y - start.y) * 0.10)
        let g = gen
        let t0 = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] tm in
            guard let self = self, let w = self.window else { tm.invalidate(); done(); return }
            guard self.gen == g else { tm.invalidate(); return }       // 被取消,不再回调
            let t = min(1, (CACurrentMediaTime() - t0) / duration)
            let mt = 1 - t
            var x = mt*mt*mt*start.x + 3*mt*mt*t*c1.x + 3*mt*t*t*c2.x + t*t*t*end.x
            var y = mt*mt*mt*start.y + 3*mt*mt*t*c1.y + 3*mt*t*t*c2.y + t*t*t*end.y
            let bob = sin(t * .pi * 6)
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
        beginAction()
        enter("sing")
        // 音符从头上方出,左右随朝向
        let facingRight = view?.facingRight ?? false
        let w = window?.frame ?? .zero
        let x = w.minX + (facingRight ? 110 : 50)
        let y = w.maxY - 34
        Effects.notes(at: CGPoint(x: x, y: y), on: screen)
        SpriteLibrary.shared.playPeep()
        hold(Double.random(in: 1.2...1.6)) { [weak self] in self?.finish() }
    }

    // MARK: - 低空快飞掠过
    func startDart() {
        guard let window = window, screen != nil else { finish(); return }
        beginAction()
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
        beginAction()
        enter("watch")
        hold(Double.random(in: 1.4...2.2)) { [weak self] in self?.finish() }
    }

    // MARK: - 日光浴(彩蛋):斜上方出现照射的太阳;鸟在顶部时贴顶、放空的一侧
    func startSun() {
        guard let w = window, let scr = screen else { finish(); return }
        beginAction()
        enter("sun")
        let dur = Double.random(in: 3...5)
        let a = scr.frame                  // 全屏(太阳在 statusBar 层,可盖菜单栏)
        let bird = w.frame
        let margin: CGFloat = 70
        let preferRight = bird.midX < a.midX
        var sx = bird.midX + (preferRight ? 92 : -92)
        sx = min(max(sx, a.minX + margin), a.maxX - margin)
        var sy = bird.maxY + 64
        let topLimit = a.maxY - margin
        if sy > topLimit { sy = topLimit }    // 顶部不够就贴顶
        Effects.sun(at: CGPoint(x: sx, y: sy), on: screen, duration: dur)
        hold(dur) { [weak self] in self?.finish() }
    }

    // MARK: - 啄屏幕(先叫一声,再连啄几次;啄裂则每啄让裂纹长大)
    func startPeck() {
        beginAction()
        SpriteLibrary.shared.playPeep()          // 先叫一声
        let count = Int.random(in: 3...5)
        let willCrack = Int.random(in: 0..<100) < 12
        hold(0.25) { [weak self] in self?.peckBurst(remaining: count, crack: willCrack) }
    }

    private func peckBurst(remaining: Int, crack: Bool) {
        guard let w = window else { finish(); return }
        enter("peck")                            // 啄的时候不叫
        if crack {
            let facingRight = view?.facingRight ?? false
            let bx = w.frame.minX + (facingRight ? 156 : 4)
            let by = w.frame.minY + 72
            self.crack?.peck(at: CGPoint(x: bx, y: by))
        }
        hold(0.3) { [weak self] in
            guard let self = self else { return }
            if remaining > 1 { self.peckBurst(remaining: remaining - 1, crack: crack) }
            else { self.finish() }
        }
    }

    // MARK: - 停到最前面窗口的上沿(随机;窗口移走就飞走)
    func startPerchWindow() {
        guard let window = window, let scr = screen,
              let perch = WindowTracker.frontPerch(birdWidth: size.width) else { finish(); return }
        beginAction()
        enter("fly")
        // 脚踩在窗口上沿(perch.y - feetOffset)
        let target = clamp(CGPoint(x: perch.point.x, y: perch.point.y - feetOffset))
        view?.facingRight = target.x > window.frame.origin.x
        animateFlight(to: target, duration: 1.1) { [weak self] in
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
        let moved = abs(topY - (w.frame.minY + feetOffset)) > 24 || abs(f.midX - w.frame.midX) > 120
        // 遮挡:鸟脚处最前面的窗口不是本窗口(被更大窗口盖住)→ 飞走
        let feetPt = CGPoint(x: w.frame.midX, y: w.frame.minY + feetOffset)
        let occluded = WindowTracker.frontWindowAt(nsPoint: feetPt) != wid
        if moved || occluded {
            leavePerch(); startFly()
        }
    }

    // MARK: - 打盹
    func startSleep() {
        beginAction()
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
        // 从头上方出,左右随朝向(头在朝向一侧)
        let facingRight = view?.facingRight ?? false
        let x = w.frame.minX + (facingRight ? 110 : 50)
        let y = w.frame.maxY - 34
        Effects.zzz(at: CGPoint(x: x, y: y), on: screen)
    }
    private func stopZzz() { zzzTimer?.invalidate(); zzzTimer = nil }

    // MARK: - 拉屎(自主随机 / 吃完延时触发)
    private func schedulePoop(after t: TimeInterval) {
        poopTimer?.invalidate()
        poopTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
            self?.startPoop()
        }
    }

    func startPoop() {
        guard onScreen, let w = window else { finish(); return }
        beginAction()
        enter("poop")
        let facingRight = view?.facingRight ?? false
        let buttX = w.frame.midX + (facingRight ? -50 : 50)
        let buttY = w.frame.minY + 58
        hold(0.5) { [weak self] in
            guard let self = self else { return }
            self.poopCtl?.dropPoop(at: CGPoint(x: buttX, y: buttY))
            self.hold(0.4) { self.finish() }
        }
    }

    // MARK: - 显示:破壳而出
    func hatchIn() {
        beginAction()
        onScreen = true
        enter("egg")
        view?.applyNow()
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
        beginAction()
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
                self.view?.state = "egg"
                self.view?.applyNow()
                self.busy = false
            }
        }
    }

    // MARK: - 外部控制
    func callOver() {
        guard let window = window, let scr = screen else { return }
        beginAction()
        enter("fly")
        let a = scr.visibleFrame
        let mx = NSEvent.mouseLocation.x
        let target = clamp(CGPoint(x: mx - size.width / 2,
                                   y: a.minY + a.height * 0.55))
        view?.facingRight = target.x > window.frame.origin.x
        animateFlight(to: target, duration: 1.0) { [weak self] in self?.finish() }
    }

    func toggleVisibility() { setVisible(!onScreen) }
    func setVisible(_ visible: Bool) {
        if visible { if !onScreen { placeAtBottomRight(); hatchIn() } }
        else { if onScreen { fallAway() } }
    }
    var isVisible: Bool { onScreen }

    // MARK: - 工具
    /// 线性移动(无缓动),每步同步刷新阴影;代际取消
    private func animateWindow(to origin: CGPoint, duration: TimeInterval, done: @escaping () -> Void) {
        guard let window = window else { done(); return }
        leavePerch()
        let start = window.frame.origin
        let g = gen
        let t0 = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] tm in
            guard let self = self, let w = self.window else { tm.invalidate(); done(); return }
            guard self.gen == g else { tm.invalidate(); return }       // 被取消
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
        let origin = clamp(CGPoint(x: a.maxX - size.width - 30, y: a.minY - feetOffset))
        window.setFrame(CGRect(origin: origin, size: size), display: false)
    }
}
