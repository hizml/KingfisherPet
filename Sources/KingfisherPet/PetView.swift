import AppKit
import QuartzCore

protocol PetViewDelegate: AnyObject {
    func petViewWasClicked()
    func petViewDidBeginDrag()
    func petViewDidEndDrag()
}

/// 宠物精灵视图:CALayer 逐帧播放 + 按像素 alpha 做点击穿透 + 鼠标拖拽
final class PetView: NSView {

    weak var delegate: PetViewDelegate?

    /// 窗口被移动时同步调用(让阴影等跟随,零延迟)
    var onMoved: (() -> Void)?

    /// 当前状态(改了会重置动画)
    var state: String = "idle" {
        didSet {
            if oldValue != state { animTime = 0; lastTick = 0 }
        }
    }

    /// 朝向:false=默认朝左;true=翻转朝右
    var facingRight = false {
        didSet { updateTransform() }
    }

    private let spriteLayer = CALayer()
    private var timer: Timer?
    private var animTime: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var lastName: String = ""

    // 拖拽状态
    private var mouseDownPoint = CGPoint.zero
    private var mouseDownWindowOrigin = CGPoint.zero
    private var mouseDownTime: CFTimeInterval = 0
    private var didDrag = false

    override var isFlipped: Bool { true }   // 左上角原点,与图像像素行一致

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer = CALayer()
        spriteLayer.contentsGravity = .resize
        spriteLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(spriteLayer)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, timer == nil {
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    override func layout() {
        super.layout()
        spriteLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        spriteLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        updateTransform()
    }

    private func updateTransform() {
        var t = CGAffineTransform.identity
        if facingRight { t = t.scaledBy(x: -1, y: 1) }
        spriteLayer.setAffineTransform(t)
    }

    // MARK: - 动画
    private func tick() {
        let now = CACurrentMediaTime()
        if lastTick == 0 { lastTick = now }
        animTime += (now - lastTick)
        lastTick = now
        applyFrame()
    }

    private func applyFrame() {
        let lib = SpriteLibrary.shared
        let name: String
        if let seq = lib.sequence(state), !seq.isEmpty {
            let f = max(1, lib.fps(state))
            let idx = Int(animTime * f) % seq.count
            name = seq[idx]
        } else {
            name = "idle_0"
        }
        guard let frame = lib.frame(name) else { return }
        if lastName != name {
            lastName = name
            spriteLayer.contents = frame.cgImage
        }
        spriteLayer.contentsScale = window?.backingScaleFactor ?? 2
        currentFrame = frame
    }

    /// 立即刷到当前状态的第一帧(用于重新显示前,避免闪现上一状态残影)
    func applyNow() {
        animTime = 0
        lastTick = 0
        lastName = ""
        applyFrame()
    }

    private var currentFrame: PetFrame?

    // MARK: - 点击穿透(透明像素点透传到后面的 App)
    override func hitTest(_ point: NSPoint) -> NSView? {
        // point 位于父视图坐标系,转到本视图
        let local = self.convert(point, from: superview)
        if alphaAt(local) > 16 { return self }
        return nil
    }

    private func alphaAt(_ p: NSPoint) -> UInt8 {
        guard let f = currentFrame, f.w > 0, f.h > 0 else { return 0 }
        guard bounds.width > 0, bounds.height > 0 else { return 0 }
        let nx = p.x / bounds.width
        let ny = p.y / bounds.height   // isFlipped -> y 从顶向下,与 alpha 顶行一致
        guard nx >= 0, nx <= 1, ny >= 0, ny <= 1 else { return 0 }
        let px = Int(nx * CGFloat(f.w))
        let py = Int(ny * CGFloat(f.h))
        let cx = min(max(px, 0), f.w - 1)
        let cy = min(max(py, 0), f.h - 1)
        return f.alpha[cy * f.w + cx]
    }

    // MARK: - 鼠标
    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = NSEvent.mouseLocation
        mouseDownWindowOrigin = window?.frame.origin ?? .zero
        mouseDownTime = CACurrentMediaTime()
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let dx = now.x - mouseDownPoint.x
        let dy = now.y - mouseDownPoint.y
        if !didDrag, hypot(dx, dy) > 4 {
            didDrag = true
            delegate?.petViewDidBeginDrag()
        }
        guard didDrag else { return }
        var o = mouseDownWindowOrigin
        o.x += dx
        o.y += dy
        // 限制:脚不低于 Dock 顶(原点 y >= minY - 56)、不出屏
        if let a = NSScreen.main?.visibleFrame, let win = window {
            o.x = min(max(o.x, a.minX), a.maxX - win.frame.width)
            o.y = min(max(o.y, a.minY - 27), a.maxY - win.frame.height)
        }
        window?.setFrameOrigin(o)
        onMoved?()
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            delegate?.petViewDidEndDrag()
        } else {
            delegate?.petViewWasClicked()
        }
    }
}
