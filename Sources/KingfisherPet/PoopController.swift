import AppKit
import QuartzCore

/// 屎物理系统:屎从鸟处下落,落在途径的窗口上沿或 Dock 上;停靠一会儿后消失。
/// 若落在某窗口上、该窗口移走(不再托住),屎重新落到 Dock / 下一窗口。
/// 屎窗口层级高于 Dock(能落在 Dock 上)、低于鸟。
final class PoopController {

    private var poops: [Poop] = []
    private var timer: Timer?
    private var lastTime: CFTimeInterval = 0
    /// 鸟所在窗口,用来确定屎落在哪个屏(多屏时屎跟随鸟的屏,而非死主屏)
    weak var bird: NSWindow?

    func start() {
        lastTime = CACurrentMediaTime()
        // 30fps:内容 8-14fps 足够,省一半常驻唤醒
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 系统睡眠前停屎物理 timer(防唤醒补发堆积);唤醒后 resume。
    func suspend() { timer?.invalidate(); timer = nil; kfLog("Poop suspend") }
    func resume() {
        guard timer == nil else { return }
        lastTime = CACurrentMediaTime()
        // 30fps:内容 8-14fps 足够,省一半常驻唤醒
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        kfLog("Poop resume")
    }

    /// 解析屎应使用的屏:鸟所在屏,否则主屏
    private var screen: NSScreen? { bird?.screen ?? NSScreen.main }

    /// 加载当前主题的屎堆贴图(供 Poop.buildBlob 用)。
    fileprivate static func effectImage(_ name: String) -> CGImage? {
        let theme = SpriteLibrary.shared.currentTheme
        guard let url = Bundle.main.url(forResource: name, withExtension: "png",
                                        subdirectory: "Sprites/\(theme)"),
              let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // 裁掉透明边:贴图(poop/zzz 等)通常有大片透明留白,不裁的话内容会悬浮。
        // 取 alpha 非零区域的 bounding box,裁剪返回。
        return cropToAlpha(cg)
    }

    /// 裁剪 CGImage 到非透明内容的 bounding box(去掉四周透明留白)。
    private static func cropToAlpha(_ cg: CGImage) -> CGImage? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return cg }
        // 渲染到 RGBA 缓冲读 alpha
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, maxX = 0, minY = h, maxY = 0
        var found = false
        for y in 0..<h {
            for x in 0..<w {
                if bytes[(y * w + x) * 4 + 3] > 20 {
                    found = true
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard found else { return cg }
        let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        return cg.cropping(to: crop)
    }

    func dropPoop(at point: CGPoint) {
        // 上限:防 sitting 屎堆积放大 30fps 全窗口枚举。超出时移除最老的(已 sit 一阵,移除不突兀)。
        if poops.count >= 8 {
            let old = poops.removeFirst()
            old.window.close()   // 真正释放(orderOut 只隐藏会泄漏窗口)
        }
        let p = Poop(start: point)
        poops.append(p)
        if let scr = screen {
            let groundY = scr.visibleFrame.minY
            let (ly, id) = WindowTracker.landingSpot(belowX: point.x, fromY: point.y,
                                                     groundY: groundY)
            p.landingY = ly
            p.landedID = id
        }
    }

    private func update() {
        let now = CACurrentMediaTime()
        let dt = lastTime == 0 ? 1.0 / 30.0 : min(0.05, now - lastTime)
        lastTime = now
        guard !poops.isEmpty else { return }   // 99% 的时间没有屎:跳过屏幕查询(WindowServer IPC)
        guard let scr = screen else { return }
        let ground = scr.visibleFrame.minY
        let sh = scr.frame.height
        for p in poops { p.update(dt: dt, ground: ground, screenH: sh) }
        let gone = poops.filter { $0.dead }
        // close() 真正释放窗口(orderOut 只隐藏,窗口对象+WindowServer 资源永远累积 → 泄漏)
        gone.forEach { $0.window.close() }
        poops.removeAll { $0.dead }
    }
}

private final class Poop {
    enum State { case falling, sitting, fading }
    let window: NSWindow
    private let blob = CALayer()
    let x: CGFloat
    var y: CGFloat
    var landingY: CGFloat
    var landedID: CGWindowID?
    var state: State = .falling
    var sitRemain: TimeInterval = 0
    var opacity: CGFloat = 1
    var dead = false
    private var occludeFrame = 0   // 遮挡检测降频计数(frontWindowAt 全窗口枚举,贵)

    /// 窗口尺寸:要大于 blob(30x20)× splat 放大倍数(1.35),否则落地压扁时内容被窗口裁掉。
    private static let winW: CGFloat = 44
    private static let winH: CGFloat = 32

    init(start: CGPoint) {
        x = start.x
        y = start.y
        landingY = start.y
        let w = Poop.winW, h = Poop.winH
        // 窗口底边对齐 y(屎落地底边);窗口比 blob 大,blob 在窗口底部居中
        window = NSWindow(contentRect: NSRect(x: start.x - w / 2, y: start.y, width: w, height: h),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: 21)      // 高于 Dock、低于鸟
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isReleasedWhenClosed = false   // Poop 持有引用;close() 已断开 WindowServer,对象随 Poop 释放

        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        v.wantsLayer = true
        let root = CALayer()
        root.masksToBounds = false          // 不裁:blob 放大时超出 root bounds 也不切
        v.layer = root
        buildBlob()
        root.addSublayer(blob)
        window.contentView = v
        window.orderFrontRegardless()
    }

    private func buildBlob() {
        let w: CGFloat = 30, h: CGFloat = 20
        blob.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        // blob 在窗口底部居中:y 偏低 3px 让屎底边压进表面一点(屎摊地上,底边嵌入)
        // 窗口底 = local y=0,blob 底 ≈ 3px 处(留一点放大空间不贴窗口底)
        blob.position = CGPoint(x: Poop.winW / 2, y: h / 2 - 3)
        blob.contents = PoopController.effectImage("poop")
        blob.contentsGravity = .resize
    }

    func update(dt: TimeInterval, ground: CGFloat, screenH: CGFloat) {
        switch state {
        case .falling:
            // 下落速度受全局动画速度影响
            y -= 220 * CGFloat(dt) * CGFloat(Settings.shared.speed)
            if y <= landingY {
                y = landingY
                state = .sitting
                sitRemain = Double.random(in: 8...15)
                splat()
            }
            applyOrigin()
        case .sitting:
            // 落在窗口上时,跟着窗口上沿;窗口移走/消失/被盖住 → 重新下落到 Dock / 下一窗口
            // 承载窗口查询(frameOfWindow = WindowServer 往返)降到 3fps(每 10 物理帧):
            // 窗口不会在 160ms 内消失,60fps 查纯属烧 CPU
            if let id = landedID {
                occludeFrame += 1
                if occludeFrame % 10 != 0 { sitRemain -= dt; if sitRemain <= 0 { state = .fading }; return }
                if let b = WindowTracker.frameOfWindow(id: id) {
                    let topNS = screenH - b.minY
                    let off = x < b.minX || x > b.maxX || topNS < y - 12
                    // 遮挡检测与承载窗口查询同频(每 10 帧一次)
                    let occluded = WindowTracker.frontWindowAt(nsPoint: CGPoint(x: x, y: y)) != id
                    if off || occluded {
                        resumeFall(ground: ground)   // 窗口移开/下沉/被盖 → 重新掉
                    }
                    // 不再 y=topNS 跟窗口上沿:屎落地固定,窗口一动就掉(还原"抖一下就掉")
                } else {
                    resumeFall(ground: ground)            // 窗口不见了
                }
            }
            sitRemain -= dt
            if sitRemain <= 0 { state = .fading }
        case .fading:
            opacity -= CGFloat(dt) * 1.2
            window.alphaValue = max(0, opacity)
            if opacity <= 0 { dead = true }
        }
    }

    private func applyOrigin() {
        // y 是屎的底边 → 窗口底贴地;x 居中用 winW/2
        window.setFrameOrigin(CGPoint(x: x - Poop.winW / 2, y: y))
    }

    /// 重新下落(窗口移走/消失):重新计算落点(Dock / 下一窗口)
    private func resumeFall(ground: CGFloat) {
        state = .falling
        let (ly, nid) = WindowTracker.landingSpot(belowX: x, fromY: y, groundY: ground)
        landingY = ly
        landedID = nid
    }

    /// 落地:轻微压扁一下
    private func splat() {
        let s = CAKeyframeAnimation(keyPath: "transform.scale")
        s.values = [1.0, 1.35, 1.0]
        s.keyTimes = [0, 0.4, 1]
        s.duration = 0.18
        s.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        blob.add(s, forKey: "splat")
    }
}
