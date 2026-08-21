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
    func currentStateForLog() -> String { current }
    private var busy = false          // 正在执行一个多阶段动作
    private var onScreen = true       // 用户意图:是否可见
    /// 因用户离开(锁屏/系统睡眠)而睡;区别于 think() 里鸟自己困了的 startSleep。
    /// 为 true 时禁声;被任何新动作打断(点击/菜单/唤醒后活动)即惊醒清除(见 beginAction)。
    private var userSleeping = false
    private var gen = 0               // 动作代际;新动作/拖动 bump,旧的 hold/动画自动作废
    private var perchOccludeFrame = 0 // 栖窗遮挡检测降频计数(frontWindowAt 全窗口枚举,贵)

    private let size = CGSize(width: 160, height: 160)
    private let feetOffset: CGFloat = 26   // 脚位基准(原版 27,视觉校准)
    private let headOffset: CGFloat = 72   // 头距窗口顶(sprite 实测,预留)

    /// 按全局动画速度缩放一段时长:速度越快,实际时长越短(1.5×→除以 1.5)。
    private func sp(_ secs: TimeInterval) -> TimeInterval { secs / Settings.shared.speed }

    weak var shadow: ShadowController?
    weak var crack: CrackController?
    weak var poopCtl: PoopController?
    weak var branch: BranchController?

    var onWindow = false
    var dragging = false
    private var perchedID: CGWindowID?
    private var perchedWinFrame: CGRect = .zero   // 上次记录的栖枝窗口帧(算增量跟随用)
    private var perchWinMoving = false            // 栖枝窗口正在被拖动(优先级高于预设动作)
    private var lastPerchMoveAt: CFTimeInterval = 0  // 上次检测到窗口移动的时刻

    init(view: PetView, window: NSWindow) {
        self.view = view
        self.window = window
        view.delegate = self
        view.onMoved = { [weak self] in self?.shadow?.updateNow() }
    }

    /// 开始一个新动作:取消所有进行中的 hold/动画/定时器(代际 bump)
    /// 注意:不清 onWindow/leavePerch —— 原地静态动作(watch/sing/sun/sleep/peck/poop)
    /// 在窗口上做时该保持在窗口上,不出树枝。真正移动的动作(fly/walk/dart)自己调 leavePerch。
    private func beginAction() {
        gen &+= 1
        busy = true
        if userSleeping {            // 正在睡/赖床时被新动作打断 → 惊醒,恢复声音
            userSleeping = false
            SpriteLibrary.shared.mutedForSleep = false
        }
        thinkTimer?.invalidate()
        poopTimer?.invalidate()
        stopZzz()
    }

    // MARK: - 几何
    private var screen: NSScreen? { window?.screen ?? NSScreen.main }
    private var area: CGRect { screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero }

    /// 把窗口原点限制在屏内:脚不低于 Dock 顶、头不超菜单栏下、横向不出界。
    private func clamp(_ origin: CGPoint) -> CGPoint {
        let a = area
        let minX = a.minX
        let maxX = a.maxX - size.width
        let minY = a.minY - feetOffset     // 脚可到 Dock 顶
        let maxY = a.maxY - size.height    // 窗口顶不超菜单栏下(原版逻辑)
        return CGPoint(x: min(max(origin.x, minX), maxX),
                       y: min(max(origin.y, minY), maxY))
    }

    /// 停窗/吸附专用几何:横向不出 visibleFrame、下界不低于 Dock 顶、上界放宽到物理屏顶
    /// (screen.frame.maxY - 鸟高,允许盖菜单栏但不超屏)。配合 wouldOvershootTop:停之前先
    /// 过滤掉"脚踩上去会头超屏"的过高窗口(直接飞走),到这里的不超屏,脚精确踩窗台。
    private func clampPerch(_ origin: CGPoint) -> CGPoint {
        let vf = area
        let topCap = (screen?.frame.maxY ?? vf.maxY) - size.height   // 物理屏顶 - 鸟高(可盖菜单栏)
        let cx = min(max(origin.x, vf.minX), vf.maxX - size.width)
        let cy = min(max(origin.y, vf.minY - feetOffset), topCap)
        return CGPoint(x: cx, y: cy)
    }

    /// 脚踩 surfaceY(窗台上沿/Dock 顶)时,鸟头顶是否会超出物理屏顶。
    /// 鸟全身在屏内的上限:origin.y ≤ screen.frame.maxY - size.height(可盖菜单栏);
    /// 脚踩 surfaceY 的 origin.y = surfaceY - feetOffset,超上限即头出屏 → 该窗口太高,不停、飞走。
    private func wouldOvershootTop(surfaceY: CGFloat) -> Bool {
        guard let maxY = screen?.frame.maxY else { return false }
        return surfaceY - feetOffset > maxY - size.height
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
        leavePerch()           // 被拿起来了,脱离栖枝
        dragging = true
        enter("idle")
    }

    func petViewDidEndDrag() {
        dragging = false
        guard let w = window, let scr = screen else { finish(); return }
        let feetY = w.frame.minY + feetOffset
        // 吸附:找离鸟脚最近的表面(窗口上沿 / Dock 顶),上下方都找。
        // 脚在表面 ±20px 内 → 吸到精确位置(脚踩表面),否则飞走/落下。
        let ground = scr.visibleFrame.minY
        let (surfY, surfID) = WindowTracker.nearestSurface(atX: w.frame.midX,
                                                            feetY: feetY, groundY: ground)
        if abs(surfY - feetY) <= 70 && !wouldOvershootTop(surfaceY: surfY) {
            // 吸附:窗口原点 y = 表面 y - feetOffset,让脚精确踩在表面上(太高会头超屏的不吸)
            let origin = clampPerch(CGPoint(x: w.frame.origin.x, y: surfY - feetOffset))
            w.setFrameOrigin(origin)
            shadow?.updateNow()
            if let id = surfID {
                onWindow = true
                perchedID = id
                if let f = WindowTracker.frameOfWindow(id: id) { perchedWinFrame = f }
                startPerchCheck()
            } else {
                onWindow = false       // 踩 Dock/地面
            }
            enter("idle")
            busy = false
            scheduleThink()
            return
        }
        // 超出吸附范围:空中飞远 / 已踩表面就落下
        if isAirborne() {
            startFly(minDist: 300)
        } else {
            finish()
        }
    }

    /// 脚下没有近表面(Dock/窗口)= 在空中(悬空)
    /// 鸟当前是否悬空(脚下既无窗口也无 Dock)。供拖拽松手、树枝显隐判断用。
    func isAirborne() -> Bool {
        guard let w = window else { return true }
        return isPointAirborne(w.frame.origin)
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
    private func finish() {
        busy = false; enter("idle"); scheduleThink()
        // 栖着但跟随器没在跑(静态动作/赖床被打断)→ 恢复跟随,否则鸟悬在原地不跟窗
        if onWindow, perchedID != nil, perchChecker == nil { startPerchCheck() }
    }

    /// 延时回调;捕获当前代际,bump 后自动作废(避免被取消的动作继续推进)。
    /// 受全局动画速度影响(快=更短)。
    private func hold(_ t: TimeInterval, _ done: @escaping () -> Void) {
        let g = gen
        DispatchQueue.main.asyncAfter(deadline: .now() + sp(t)) { [weak self] in
            guard let self = self, self.gen == g else { return }
            done()
        }
    }

    // MARK: - 定时思考
    private func scheduleThink() {
        thinkTimer?.invalidate()
        // 活跃度越高,思考间隔越短(更频繁地决定下一个动作)
        let a = Settings.shared.activity           // 0…1
        let lo = 3.5 - 2.0 * a                      // 0→3.5s, 1→1.5s
        let hi = 7.0 - 3.5 * a                      // 0→7.0s, 1→3.5s
        let delay = Double.random(in: lo...hi)
        thinkTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.think()
        }
    }

    private func think() {
        // 窗口正在被拖动 = 用户实时交互,优先级最高:推迟预设动作
        guard !busy, !perchWinMoving else { scheduleThink(); return }
        let isLow = (window?.frame.minY ?? 0) < (area.minY + 60)   // Dock 附近
        // 活跃度越高,纯待机(idle)概率越低;省下的权重分给其他动作
        let a = Settings.shared.activity               // 0…1
        let idleBand = Int((1.0 - a) * 22)             // 0→22, 1→0
        let walk = idleBand + max(1, Int((1.0 - a) * 20))   // 待机+走动一起,高活跃更倾向走
        let bounds: [(Int, () -> Void)] = [
            (walk, { [weak self] in
                guard let self = self else { return }
                if self.onWindow || isLow { self.startWalk() }
                else { self.enter("idle"); self.scheduleThink() }
            }),
            (walk + 7,  { [weak self] in self?.startFly() }),
            (walk + 15, { [weak self] in self?.startFish() }),
            (walk + 22, { [weak self] in self?.startSing() }),
            (walk + 29, { [weak self] in self?.startDart() }),
            (walk + 36, { [weak self] in self?.startWatch() }),
            (walk + 43, { [weak self] in self?.startSun() }),
            (walk + 50, { [weak self] in self?.startPeck() }),
            (walk + 56, { [weak self] in self?.startPerchWindow() }),
            (walk + 62, { [weak self] in self?.startPoop() }),
        ]
        let r = Int.random(in: 0..<100)
        if r < idleBand {
            enter("idle"); scheduleThink()
        } else {
            // 找到第一个上界 > r 的桶(未达上限的动作)
            for (upper, action) in bounds where r < upper {
                action(); return
            }
            startSleep()   // 兜底:超 walk+62 的进入打盹
        }
    }

    // MARK: - 走(沿下方表面:Dock 顶 / 窗口上沿;在窗口上走到边就飞走)
    private func startWalk() {
        guard let window = window, screen != nil else { finish(); return }
        let onWin = onWindow                 // 先记下
        let wid = perchedID
        beginAction()
        leavePerch()                         // 走 = 自己移动,脱离栖枝跟随
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
        let dur = sp(duration)                // 全局动画速度
        let g = gen
        let t0 = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] tm in
            guard let self = self, let w = self.window else { tm.invalidate(); return }
            guard self.gen == g else { tm.invalidate(); return }       // 被取消
            let t = min(1, (CACurrentMediaTime() - t0) / dur)
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
                if Bool.random() { startPerchWindow() } else { startFly(minDist: 300) }
            } else {
                onWindow = true; perchedID = id
                if let f = WindowTracker.frameOfWindow(id: id) { perchedWinFrame = f }
                startPerchCheck()
                finish()
            }
        } else {
            finish()
        }
    }

    // MARK: - 飞(随机挪窝,偶尔空中拉屎)
    /// minDist:目标点离当前位置的最小距离(被赶走时给大值,飞远点,别停在原地附近)
    private func startFly(minDist: CGFloat = 0) {
        guard let window = window, screen != nil else { finish(); return }
        beginAction()
        enter("fly")
        let a = area
        let ox = window.frame.origin.x
        let oy = window.frame.origin.y
        // 选目标点:若要求最小距离,最多重试 8 次直到够远
        var tx = ox, ty = oy
        for _ in 0..<8 {
            tx = CGFloat.random(in: a.minX + 8 ... a.maxX - size.width - 8)
            ty = Bool.random() ? (a.maxY - size.height) : (a.minY - feetOffset)
            if hypot(tx - ox, ty - oy) >= minDist { break }
        }
        let dest = clamp(CGPoint(x: tx, y: ty))
        view?.facingRight = dest.x > ox
        // 落点若悬空(飞到高处),提前在落脚处显树枝——鸟要落树枝,树枝先到
        perchBranchIfNeeded(at: dest)
        if Int.random(in: 0..<100) < 35 {
            hold(Double.random(in: 0.3...0.7)) { [weak self] in self?.airPoop() }
        }
        animateFlight(to: dest, duration: 1.3) { [weak self] in self?.finish() }
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
                let dest = self.clamp(CGPoint(x: perchX, y: perchY))
                self.perchBranchIfNeeded(at: dest)   // 落屏顶悬空时提前显树枝,避免鸟叼鱼落定后才冒
                self.animateWindow(to: dest, duration: 0.95) {
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
        let dur = sp(duration)                // 全局动画速度
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
            let t = min(1, (CACurrentMediaTime() - t0) / dur)
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
        let dest = CGPoint(x: tx, y: window.frame.origin.y)
        perchBranchIfNeeded(at: dest)   // 从高处触发时落点悬空,提前显树枝
        animateWindow(to: dest,
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
        guard let window = window, screen != nil,
              let perch = WindowTracker.frontPerch(birdWidth: size.width) else { finish(); return }
        // 窗台太高 → 脚踩上去鸟头会超屏顶 → 不停这个窗口,飞走
        if wouldOvershootTop(surfaceY: perch.point.y) { startFly(minDist: 300); return }
        beginAction()
        enter("fly")
        // 脚踩在窗口上沿(perch.y - feetOffset)
        let target = clampPerch(CGPoint(x: perch.point.x, y: perch.point.y - feetOffset))
        view?.facingRight = target.x > window.frame.origin.x
        animateFlight(to: target, duration: 1.1) { [weak self] in
            guard let self = self else { return }
            self.onWindow = true
            self.perchedID = perch.id
            if let f = WindowTracker.frameOfWindow(id: perch.id) { self.perchedWinFrame = f }
            self.startPerchCheck()
            self.finish()
        }
    }

    private func leavePerch() {
        onWindow = false
        perchedID = nil
        perchedWinFrame = .zero
        perchWinMoving = false
        perchBadStreak = 0
        occlStreak = 0
        detachStreak = 0
        stopPerchCheck()
    }
    private func startPerchCheck() {
        stopPerchCheck()
        // 高频跟随窗口移动(20fps),避免窗口拖动时鸟脱离、悬空长出树枝
        let t = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in self?.checkPerch() }
        RunLoop.main.add(t, forMode: .common)
        perchChecker = t
    }
    private func stopPerchCheck() {
        perchChecker?.invalidate()
        perchChecker = nil
    }
    /// 栖窗"坏判定"迟滞:遮挡/脱离/过高要连续 3 次(≈150ms)才真飞走。
    /// 唤醒瞬间窗口层级混乱(锁屏窗淡出/App 重建),单次判定会反复翻转
    /// → 栖→飞→落高→树枝出→又栖→又遮 → 树枝"一会有一会没有"闪现。
    private var perchBadStreak = 0
    private var occlStreak = 0      // 遮挡坏判定连击(仅查询帧累加)
    private var detachStreak = 0    // 水平脱离/过高连击(每帧)
    /// 唤醒宽限:此刻之前不做遮挡判定(窗口层级未稳)
    private var perchGraceUntil: CFTimeInterval = 0

    private func checkPerch() {
        guard let wid = perchedID, let scr = screen, let w = window,
              let f = WindowTracker.frameOfWindow(id: wid) else {
            perchBadStreak += 1
            if perchBadStreak >= 3 { leavePerch(); startFly(minDist: 300) }   // 窗口连续3帧没了才飞
            return
        }
        let feetY = w.frame.minY + feetOffset
        // 遮挡检测降频:frontWindowAt 是全窗口枚举(贵),每 10 帧(≈0.5s)查一次。
        // 计数只在【查询帧】累加/清零——非查询帧不能碰它,否则永远凑不满(上一版就这洞)
        perchOccludeFrame += 1
        if perchOccludeFrame % 10 == 0 {
            if CACurrentMediaTime() > perchGraceUntil {
                let feetPt = CGPoint(x: w.frame.midX, y: feetY)
                if WindowTracker.frontWindowAt(nsPoint: feetPt) != wid {
                    occlStreak += 1
                } else {
                    occlStreak = 0
                }
            } else {
                occlStreak = 0   // 宽限期内查询本身跳过,计数保持干净
            }
        }
        // 水平脱离/过高:每帧查,确定性信号,150ms 迟滞即可
        let detach = w.frame.midX < f.minX - 10 || w.frame.midX > f.maxX + 10
                  || wouldOvershootTop(surfaceY: scr.frame.height - f.minY)
        if detach { detachStreak += 1 } else { detachStreak = 0 }
        // 遮挡要连续 2 次查询(≈1s)坏才飞;脱离 3 帧(150ms)
        if occlStreak >= 2 || detachStreak >= 3 {
            leavePerch(); startFly(minDist: 300); return
        }
        // 跟随窗口移动:用窗口位移增量(dxw/dyw),鸟保持相对窗口的位置(不往中间凑)
        let dxw = f.minX - perchedWinFrame.minX
        let dyw = (scr.frame.height - f.minY) - (scr.frame.height - perchedWinFrame.minY)
        if abs(dxw) > 0.5 || abs(dyw) > 0.5 {
            // 窗口正在被拖动:用户实时交互,优先级高于预设动作 → think 推迟
            perchWinMoving = true
            lastPerchMoveAt = CACurrentMediaTime()
            w.setFrameOrigin(clampPerch(CGPoint(x: w.frame.origin.x + dxw,
                                           y: w.frame.origin.y + dyw)))
            shadow?.updateNow()
        } else if perchWinMoving, CACurrentMediaTime() - lastPerchMoveAt > 0.6 {
            // 窗口停了 0.6s → 恢复正常思考
            perchWinMoving = false
        }
        perchedWinFrame = f
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
    func hatchIn(completion: (() -> Void)? = nil) {
        guard !dndActive else { completion?(); return }   // 勿扰中:鸟绝不盖全屏
        beginAction()
        onScreen = true
        enter("egg")
        view?.applyNow()
        shadow?.setVisible(true)
        window?.makeKeyAndOrderFront(nil)
        view?.resumeAnimation()    // 重新显示:恢复全部常驻 timer(fallAway 挂起过的)
        branch?.resume()
        poopCtl?.resume()
        hold(1.4) { [weak self] in
            guard let self = self else { return }
            self.finish()
            completion?()
        }
    }


    var isOnScreen: Bool { onScreen }   // 勿扰巡检用(隐身意图判断)
    var isSleeping: Bool { userSleeping }   // 锁屏/睡眠中(勿扰巡检需跳过)

    // MARK: - 勿扰(全屏应用):静默隐身——不播任何动画(动画本身也会盖在视频上)
    private(set) var dndActive = false   // 勿扰中(守卫:唤醒/破壳都不能把鸟拉回全屏上)
    func enterDnd() {
        dndActive = true
        beginAction()
        userSleeping = false
        SpriteLibrary.shared.mutedForSleep = true
        SpriteLibrary.shared.pauseAllPeeps()
        window?.orderOut(nil)
        shadow?.setVisible(false)
        stopZzz()
        view?.suspendAnimation()   // 停全部常驻 timer(零空转,Windows 同款)
        branch?.suspend()
        poopCtl?.suspend()
        busy = false
    }
    func exitDnd() {
        dndActive = false
        SpriteLibrary.shared.mutedForSleep = false
        window?.orderFrontRegardless()
        view?.resumeAnimation()
        branch?.resume()
        poopCtl?.resume()
        shadow?.updateNow()
        busy = false
        finish()
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
                // 鸟隐藏:停全部常驻 timer(逐帧/树枝/屎),零空转(hatchIn 时 resume)
                self.view?.suspendAnimation()
                self.branch?.suspend()
                self.poopCtl?.suspend()
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
        // 落点若悬空(没踩 Dock/窗口),提前在落脚处显树枝,鸟到了无缝接管
        perchBranchIfNeeded(at: target)
        animateFlight(to: target, duration: 1.0) { [weak self] in self?.finish() }
    }

    /// 判断某个窗口原点位置是否悬空:鸟脚下有没有可踩的表面(窗口上沿 / Dock 顶)。
    /// 踩在窗口上沿或 Dock 上 → 不悬空(不出树枝);脚下无表面 → 悬空(出树枝)。
    /// 用 nearestSurface 找离脚最近(上下都找)的窗口上沿/Dock。landingSpot 只找脚"正下方",
    /// 鸟踩在上沿上(上沿≈脚)时可能漏判成悬空、冒出树枝;nearestSurface 直接按距离判断更稳。
    /// 不能用 frontWindowAt 的 2D 矩形包含——会把"悬空在窗口前方"误判成"在窗口上"。
    private func isPointAirborne(_ origin: CGPoint) -> Bool {
        guard let scr = screen else { return true }
        let feetX = origin.x + size.width / 2
        let feetY = origin.y + feetOffset
        let ground = scr.visibleFrame.minY + 6
        let (surfY, _) = WindowTracker.nearestSurface(atX: feetX, feetY: feetY, groundY: ground)
        return abs(surfY - feetY) > 30
    }

    /// 落点若悬空(脚下无 Dock/窗口),在脚的落点提前显树枝——鸟要落树枝,树枝先到,
    /// 鸟到了由 BranchController 无缝接管。所有"飞到某处落下"的路径统一调用,避免漏判
    /// 导致鸟落定后才由滞后检测冒出树枝(BranchController.tick 的 eligibleAt + 0.3s 兜底)。
    private func perchBranchIfNeeded(at origin: CGPoint) {
        // 预显判断用 y 高度(和 BranchController.tick 的显示条件同一套):
        // 之前用 isPointAirborne(实时探测脚下窗口)与落地判定不一致,会出现
        // 预显被跳过、鸟落定后树枝才补出来的诡异时序。脚高于 Dock 区即悬空 → 树枝先到。
        guard let scr = screen else { return }
        let feetY = origin.y + feetOffset
        guard feetY > scr.visibleFrame.minY + 40 else { return }
        branch?.showAt(CGPoint(x: origin.x + size.width / 2, y: origin.y + feetOffset))
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
        let dur = sp(duration)                // 全局动画速度
        let start = window.frame.origin
        let g = gen
        let t0 = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] tm in
            guard let self = self, let w = self.window else { tm.invalidate(); done(); return }
            guard self.gen == g else { tm.invalidate(); return }       // 被取消
            let t = min(1, (CACurrentMediaTime() - t0) / dur)
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

    /// 屏幕布局变化时把鸟钳制回当前屏可见区(外接屏拔掉/分辨率变,避免飞出屏外)。
    func clampToCurrentScreen() {
        guard let window = window else { return }
        let origin = clamp(window.frame.origin)
        window.setFrameOrigin(origin)
        shadow?.updateNow()
    }

    /// 用户离开(锁屏 / 系统睡眠)→ 入睡。
    /// - systemSleep=true:进程将挂起,无条件 suspend 停所有定时器,防唤醒时 asyncAfter/Timer
    ///   密集补发堆出特效卡死(历史顽疾)。屏幕已黑,视觉次要。
    /// - systemSleep=false(锁屏):进程继续,走 beginAction 打断当前动作 + 自然 startZzz。
    /// 两种路径视觉一致(sleep 动画 + zzz + 禁声)。已睡时再调幂等。
    func sleepForUserAbsence(systemSleep: Bool) {
        let alreadySleeping = userSleeping
        if systemSleep {
            suspend()                  // 无条件:挂起前必须停 think/poop/zzz/perch + 代际 bump
        } else if !alreadySleeping {
            beginAction()              // 首次锁屏:代际 bump 取消进行中的飞/走
            stopPerchCheck()           // 鸟静止,停栖窗 20fps 全窗口枚举检查
            // 不 startZzz:锁屏屏幕黑,飘 zzz 纯浪费 CPU/合成;解锁后 wakeFromUserAbsence 会重开
        }
        userSleeping = true            // 标志在 beginAction/suspend 之后设,避免入睡误触发惊醒
        SpriteLibrary.shared.mutedForSleep = true
        SpriteLibrary.shared.pauseAllPeeps()   // 锁屏前一瞬在播的叫声也停掉
        enter("sleep")                 // 切 sleep 动画;enter 里 s=="sleep" 不 stopZzz,保住 zzz
    }

    /// 用户回来(解锁 / 系统唤醒)→ 赖床随机 2–4 秒后醒来。
    /// 赖床期间用户点击/菜单操作会走 beginAction 惊醒打断(见 beginAction)。
    func wakeFromUserAbsence() {
        guard userSleeping else { return }
        // 勿扰中(全屏应用)唤醒:窗口隐藏着,只清睡眠状态——zzz/恢复会把鸟画到全屏视频上
        if dndActive {
            userSleeping = false
            SpriteLibrary.shared.mutedForSleep = false
            busy = false
            enter("idle")
            return
        }
        perchGraceUntil = CACurrentMediaTime() + 6.0   // 唤醒宽限 6s:检查器 3s 后才恢复,且系统层级稳定要几秒
        perchBadStreak = 0
        // 鸟隐藏着(fallAway 后)不能复活:不 zzz、不 finish 重启行为,
        // 否则隐形鸟继续拉屎/唱歌出幽灵特效。只清睡眠状态。
        guard onScreen else {
            userSleeping = false
            SpriteLibrary.shared.mutedForSleep = false
            busy = false
            enter("idle")
            return
        }
        enter("sleep")
        startZzz()                     // 系统唤醒后 zzz 已被 suspend 停,这里重开呈现睡觉视觉
        hold(Double.random(in: 2...4)) { [weak self] in
            guard let self = self, self.userSleeping else { return }
            self.userSleeping = false
            SpriteLibrary.shared.mutedForSleep = false
            if self.onWindow, self.perchedID != nil { self.startPerchCheck() }  // 恢复窗口跟随(防回归)
            self.finish()              // busy=false + enter idle + scheduleThink
        }
    }

    /// 系统睡眠前彻底暂停:停掉所有定时器(think/zzz/poop/perch)+ 代际 bump,
    /// 不再排任何新回调。睡眠期间没有任何待处理 timer/asyncAfter,唤醒时不会补发堆积。
    func suspend() {
        gen &+= 1                  // 作废所有 hold/动画回调(唤醒后即使补发也被 gen 守卫拦掉)
        busy = true                // 标记忙,防止 think 在唤醒瞬间触发
        thinkTimer?.invalidate(); thinkTimer = nil
        poopTimer?.invalidate(); poopTimer = nil
        stopZzz()
        stopPerchCheck()
        dragging = false        // 合盖瞬间可能正拖着鸟:mouseUp 丢失,不清则永久卡住(树枝永不显示)
    }

    /// 熔断恢复:解除 sleep 标志 + 回 idle + 排 think(供 emergencyReset 用)
    func forceIdle() {
        userSleeping = false
        SpriteLibrary.shared.mutedForSleep = false
        perchWinMoving = false          // 熔断时若用户正拖栖窗,标志可能卡 true → think 永久推迟
        beginAction()
        current = "idle"
        view?.state = "idle"
        busy = false
        if onScreen { scheduleThink() } // 隐藏着不复活行为
        if onWindow, perchedID != nil { startPerchCheck() }   // 恢复栖窗跟随
    }
}
