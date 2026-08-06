import AppKit
import QuartzCore

/// 树枝:鸟停到屏幕高处"歇脚"时,脚下出现一根树枝(不在地面、不跟着飞)。
/// 一个可移动的透明 click-through 小窗口,30fps 跟随鸟的 x,贴在脚下。
final class BranchController {

    private weak var bird: NSWindow?
    private weak var behavior: Behavior?
    private let overlay: NSWindow
    private let branchLayer = CALayer()
    private var timer: Timer?
    private var shown = false

    private let overlaySize = CGSize(width: 230, height: 96)

    init(bird: NSWindow, behavior: Behavior) {
        self.bird = bird
        self.behavior = behavior
        overlay = NSWindow(contentRect: NSRect(origin: .zero, size: overlaySize),
                           styleMask: .borderless, backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.level = .floating
        overlay.ignoresMouseEvents = true
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary]
        overlay.isReleasedWhenClosed = false

        let v = NSView(frame: NSRect(origin: .zero, size: overlaySize))
        v.wantsLayer = true
        v.layer = CALayer()
        branchLayer.contentsGravity = .resize
        branchLayer.bounds = CGRect(origin: .zero, size: overlaySize)
        branchLayer.position = CGPoint(x: overlaySize.width / 2, y: overlaySize.height / 2)
        if let url = Bundle.main.url(forResource: "branch", withExtension: "png"),
           let img = NSImage(contentsOf: url),
           let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            branchLayer.contents = cg
        }
        v.layer?.addSublayer(branchLayer)
        overlay.contentView = v
    }

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let b = bird, let beh = behavior, let scr = b.screen ?? NSScreen.main else { return }
        let a = scr.visibleFrame
        // 高处 = 屏幕上 40% 区域;且处于歇脚状态
        let high = b.frame.minY > a.maxY - a.height * 0.40
        let shouldShow = beh.isResting() && high && b.isVisible
                         && !beh.dragging && !beh.onWindow

        if shouldShow {
            // 树枝贴在脚下(鸟脚靠近窗口底部)
            let origin = CGPoint(x: b.frame.midX - overlaySize.width / 2,
                                 y: b.frame.minY - overlaySize.height * 0.45)
            overlay.setFrameOrigin(origin)
            if !shown {
                overlay.orderFrontRegardless()
                shown = true
                // 让鸟压在树枝之上
                b.orderFrontRegardless()
            }
        } else if shown {
            overlay.orderOut(nil)
            shown = false
        }
    }
}
