import AppKit
import Foundation

/// 宠物行为状态机:决定 idle / walk / fly / sleep / happy,并移动窗口
final class Behavior: PetViewDelegate {

    private weak var window: NSWindow?
    private weak var view: PetView?

    private var thinkTimer: Timer?
    private var current = "idle"
    private var busy = false          // 正在执行 walk/fly 这种带动画的动作
    private var onScreen = true

    private let size = CGSize(width: 160, height: 160)

    init(view: PetView, window: NSWindow) {
        self.view = view
        self.window = window
        view.delegate = self
    }

    // MARK: - 启动
    func start() {
        placeAtTopRight()
        enter("idle")
        scheduleThink()
    }

    // MARK: - PetViewDelegate
    func petViewWasClicked() {
        SpriteLibrary.shared.playPeep()
        enter("happy")
        busy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }
            if self.current == "happy" {
                self.busy = false
                self.enter("idle")
                self.scheduleThink()
            }
        }
    }

    func petViewDidBeginDrag() {
        busy = true
        thinkTimer?.invalidate()
        enter("drag")   // 无序列 → 用 idle_0 占位
        view?.facingRight = view?.facingRight ?? false
    }

    func petViewDidEndDrag() {
        busy = false
        enter("idle")
        scheduleThink()
    }

    // MARK: - 状态切换
    private func enter(_ s: String) {
        current = s
        if s == "drag" {
            // 拖拽时停帧,用 idle_0
            view?.state = "idle"
        } else {
            view?.state = s
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
        let r = Int.random(in: 0..<100)
        switch r {
        case 0..<40:        // 继续待机
            enter("idle"); scheduleThink()
        case 40..<72:       // 沿栖息地走一段
            startWalk()
        case 72..<90:       // 飞到新位置
            startFly()
        default:            // 打盹
            startSleep()
        }
    }

    // MARK: - 动作:走
    private func startWalk() {
        guard let window = window, let screen = window.screen ?? NSScreen.main else {
            enter("idle"); scheduleThink(); return
        }
        busy = true
        enter("walk")
        let area = screen.visibleFrame
        let cur = window.frame.origin
        let step = CGFloat.random(in: 60...180) * (Bool.random() ? 1 : -1)
        var targetX = cur.x + step
        targetX = max(area.minX + 8, min(targetX, area.maxX - size.width - 8))
        view?.facingRight = targetX < cur.x ? false : true   // 朝左=默认;向右走要翻转
        let target = CGPoint(x: targetX, y: cur.y)
        let dist = abs(targetX - cur.x)
        animateWindow(to: target, duration: max(0.6, Double(dist) / 90.0)) { [weak self] in
            guard let self = self else { return }
            self.busy = false
            self.enter("idle")
            self.scheduleThink()
        }
    }

    // MARK: - 动作:飞
    private func startFly() {
        guard let window = window, let screen = window.screen ?? NSScreen.main else {
            enter("idle"); scheduleThink(); return
        }
        busy = true
        enter("fly")
        let area = screen.visibleFrame
        let targetX = CGFloat.random(in: area.minX + 8 ... area.maxX - size.width - 8)
        // 顶部(菜单栏下)或底部(Dock 上)随机栖息
        let perchTop = Bool.random()
        let targetY = perchTop
            ? (area.maxY - size.height)
            : area.minY
        view?.facingRight = targetX < window.frame.origin.x ? false : true
        animateWindow(to: CGPoint(x: targetX, y: targetY), duration: 1.3) { [weak self] in
            guard let self = self else { return }
            self.busy = false
            self.enter("idle")
            self.scheduleThink()
        }
    }

    // MARK: - 动作:睡
    private func startSleep() {
        busy = true
        enter("sleep")
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 5...9)) { [weak self] in
            guard let self = self else { return }
            if self.current == "sleep" {
                self.busy = false
                self.enter("idle")
                self.scheduleThink()
            }
        }
    }

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

    private func placeAtTopRight() {
        guard let window = window, let screen = window.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let origin = CGPoint(x: area.maxX - size.width - 30,
                             y: area.maxY - size.height)
        window.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    // MARK: - 外部控制(菜单调用)
    func callOver() {
        busy = false
        thinkTimer?.invalidate()
        enter("fly")
        guard let window = window, let screen = window.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        // 飞到屏幕中部偏上,靠近鼠标 X
        let mx = NSEvent.mouseLocation.x
        let targetX = max(area.minX + 8, min(mx - size.width / 2, area.maxX - size.width - 8))
        let targetY = area.minY + area.height * 0.55
        view?.facingRight = targetX < window.frame.origin.x ? false : true
        animateWindow(to: CGPoint(x: targetX, y: targetY), duration: 1.0) { [weak self] in
            self?.enter("idle")
            self?.scheduleThink()
        }
    }

    func toggleVisibility() {
        setVisible(!onScreen)
    }

    func setVisible(_ visible: Bool) {
        onScreen = visible
        if visible {
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderOut(nil)
        }
    }

    var isVisible: Bool { onScreen }
}
