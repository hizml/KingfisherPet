import AppKit
import QuartzCore

/// 树枝:鸟停到屏幕高处歇脚时脚下出现一根树枝。
/// - 和鸟同层(.floating 之上的 statusBar+1),鸟在树枝之上(同级靠 key 序)。
/// - 飞往高处前可在目的地"提前出现"(showAt),鸟到了无缝接管,而不是到了才冒出来。
/// - 一个可移动的透明 click-through 小窗口,60fps 跟随鸟的 x,贴在脚下。
final class BranchController {

    private weak var bird: NSWindow?
    private weak var behavior: Behavior?
    private let overlay: NSWindow
    private let branchLayer = CALayer()
    private var timer: Timer?
    private var shown = false
    private var eligibleAt: CFTimeInterval = 0
    private var preview: CGPoint?
    private var previewUntil: CFTimeInterval = 0

    private let overlaySize = CGSize(width: 230, height: 96)
    private let feetOffset: CGFloat = 27

    init(bird: NSWindow, behavior: Behavior) {
        self.bird = bird
        self.behavior = behavior
        overlay = NSWindow(contentRect: NSRect(origin: .zero, size: overlaySize),
                           styleMask: .borderless, backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)  // 和鸟同层
        overlay.ignoresMouseEvents = true
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary]
        overlay.isReleasedWhenClosed = false

        let v = NSView(frame: NSRect(origin: .zero, size: overlaySize))
        v.wantsLayer = true
        v.layer = CALayer()
        branchLayer.contentsGravity = .resize
        branchLayer.bounds = CGRect(origin: .zero, size: overlaySize)
        branchLayer.position = CGPoint(x: overlaySize.width / 2, y: overlaySize.height / 2)
        loadBranchAsset()
        v.layer?.addSublayer(branchLayer)
        overlay.contentView = v
    }

    /// 从当前主题目录加载 branch.png
    private func loadBranchAsset() {
        let theme = SpriteLibrary.shared.currentTheme
        if let url = Bundle.main.url(forResource: "branch", withExtension: "png",
                                     subdirectory: "Sprites/\(theme)"),
           let img = NSImage(contentsOf: url),
           let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            branchLayer.contents = cg
        }
    }

    /// 主题切换:重载树枝贴图
    func reloadTheme() {
        loadBranchAsset()
    }

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 飞往高处前在"脚的落点"提前显示树枝;鸟到了由常规跟踪无缝接管
    func showAt(_ feetPoint: CGPoint) {
        preview = feetPoint
        previewUntil = CACurrentMediaTime() + 5
        position(feetX: feetPoint.x, feetY: feetPoint.y)
        if !shown {
            overlay.orderFrontRegardless()
            shown = true
            bird?.orderFrontRegardless()
        }
    }

    private func position(feetX: CGFloat, feetY: CGFloat) {
        overlay.setFrameOrigin(CGPoint(x: feetX - overlaySize.width / 2,
                                       y: feetY - overlaySize.height / 2))
    }

    private func tick() {
        let now = CACurrentMediaTime()

        // 预览模式:树枝固定在目的地,直到鸟到了或超时
        if let p = preview {
            if now > previewUntil {
                preview = nil
                if shown { overlay.orderOut(nil); shown = false }
                return
            }
            position(feetX: p.x, feetY: p.y)
            if let b = bird, let beh = behavior {
                let arrived = beh.isResting() && abs(b.frame.midX - p.x) < 40
                if arrived { preview = nil; eligibleAt = now }
            }
            return
        }

        guard let b = bird, let beh = behavior else { return }
        // 只要鸟在歇着、没踩 Dock/窗口(悬空),就得有树枝托着——不再限制屏上 40% 高度
        let shouldShow = beh.isResting() && beh.isAirborne() && b.isVisible
                         && !beh.dragging && !beh.onWindow

        if shouldShow {
            if eligibleAt == 0 { eligibleAt = now }
            position(feetX: b.frame.midX, feetY: b.frame.minY + feetOffset)
            if !shown, now - eligibleAt > 0.3 {
                overlay.orderFrontRegardless()
                shown = true
                b.orderFrontRegardless()      // 鸟压在树枝之上
            }
        } else {
            eligibleAt = 0
            if shown {
                overlay.orderOut(nil)
                shown = false
            }
        }
    }
}
