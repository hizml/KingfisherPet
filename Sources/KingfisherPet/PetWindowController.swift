import AppKit

/// 透明无边框置顶窗口,承载宠物视图
final class PetWindowController: NSWindowController, NSWindowDelegate {

    let petView: PetView
    let behavior: Behavior
    private let size = CGSize(width: 160, height: 160)

    init() {
        let frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let window = NSWindow(contentRect: frame,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.animationBehavior = .none
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.title = "翡"

        let view = PetView(frame: NSRect(origin: .zero, size: size))
        window.contentView = view

        self.petView = view
        self.behavior = Behavior(view: view, window: window)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        showWindow(nil)
        behavior.start()
    }
}
