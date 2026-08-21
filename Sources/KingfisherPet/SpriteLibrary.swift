import AppKit
import AVFoundation
import Foundation

/// sprites.json 结构
struct SpriteManifest: Codable {
    let fps: [String: Double]
    let sequences: [String: [String]]
}

/// 单帧:图像 + 命中检测用的 alpha 缓冲
struct PetFrame {
    let image: NSImage
    let cgImage: CGImage
    let alpha: [UInt8]      // 行优先,顶行在前,长度 = w*h
    let w: Int
    let h: Int
}

/// 全局 sprite 资源库(启动时一次性加载;切换主题时 reload)
/// 资源按主题分目录打包:Contents/Resources/Sprites/<theme>/{*.png, sprites.json}。
final class SpriteLibrary {
    static let shared = SpriteLibrary()

    /// 所有可用主题 id(与 gen_sprites.py 的 THEME_NAMES 对应)。
    static let themes: [(id: String, name: String)] = [
        ("flat", "扁平卡通"),
        ("clay", "粘土软陶"),
        ("pixel", "像素风"),
        ("neon", "霓虹"),
        ("ink", "水墨国风"),
        ("watercolor", "水彩手绘"),
    ]

    private(set) var frames: [String: PetFrame] = [:]
    private(set) var manifest = SpriteManifest(fps: [:], sequences: [:])
    private var peepPlayers: [AVAudioPlayer] = []
    private(set) var currentTheme = "flat"

    var soundOn = true
    /// 睡眠(锁屏/系统睡眠)期间临时禁声;不影响用户设置 soundOn。由 Behavior 在入睡/醒来时切换。
    var mutedForSleep = false
    var mediaMuted = false   // 听歌/看片时鸟不叫(勿扰;只静叫声,行为正常)

    /// 主题变化时回调(PetView/控制器重取帧、重置贴图)。可多个监听者。
    private var themeObservers: [() -> Void] = []
    func observeThemeChanged(_ block: @escaping () -> Void) {
        themeObservers.append(block)
    }

    private init() {
        loadTheme(currentTheme)
        preparePeeps()
    }

    // MARK: - 主题目录定位
    /// 在 bundle 里定位主题子目录。优先子目录形式 Sprites/<theme>/;
    /// 兼容旧的铺平形式(找不到子目录时,resourceName 直接在 Sprites/ 下找)。
    private func resourceURL(_ name: String, ext: String, theme: String) -> URL? {
        // 子目录形式
        if let url = Bundle.main.url(forResource: name, withExtension: ext,
                                     subdirectory: "Sprites/\(theme)") {
            return url
        }
        // 兜底:铺平形式(旧包/直接跑二进制时,资源可能在 Sprites/ 根或 bundle 根)
        if let url = Bundle.main.url(forResource: name, withExtension: ext,
                                     subdirectory: "Sprites") {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: ext)
    }

    // MARK: - 加载主题
    func loadTheme(_ theme: String) {
        currentTheme = theme
        loadManifest(theme: theme)
        loadFrames(theme: theme)
    }

    /// 切换主题:重载资源并通知监听者(不重新加载音效)
    func reload(theme: String) {
        guard theme != currentTheme else { return }
        loadTheme(theme)
        for o in themeObservers { o() }
    }

    private func loadManifest(theme: String) {
        guard let url = resourceURL("sprites", ext: "json", theme: theme),
              let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(SpriteManifest.self, from: data) else {
            print("[KingfisherPet] 警告:未找到主题 \(theme) 的 sprites.json")
            return
        }
        manifest = m
    }

    private func loadFrames(theme: String) {
        var names = Set<String>()
        for seq in manifest.sequences.values { names.formUnion(seq) }
        names.insert("idle_0") // 兜底

        var newFrames: [String: PetFrame] = [:]
        for name in names {
            guard let url = resourceURL(name, ext: "png", theme: theme),
                  let img = NSImage(contentsOf: url),
                  let cg = cgImage(of: img) else {
                print("[KingfisherPet] 警告:缺少帧 \(name).png(主题 \(theme))")
                continue
            }
            let (alpha, w, h, cleaned) = alphaBuffer(for: cg)
            // 用清理后的位图渲染(窗口形状精确到可见像素),显示效果不变(alpha<16 本就不可见)
            newFrames[name] = PetFrame(image: img, cgImage: cleaned ?? cg, alpha: alpha, w: w, h: h)
        }
        // 若整主题加载失败(newFrames 空),保留旧帧避免崩
        if !newFrames.isEmpty {
            frames = newFrames
        }
    }

    func frame(_ name: String) -> PetFrame? { frames[name] }
    func sequence(_ state: String) -> [String]? { manifest.sequences[state] }
    func fps(_ state: String) -> Double { manifest.fps[state] ?? 8 }

    private func cgImage(of nsImage: NSImage) -> CGImage? {
        nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// 把 cgImage 渲染到 RGBA 缓冲 + 清理低 alpha 光晕,返回 (alpha, w, h, 清理后位图)。
    /// 注意:不要加 flip——ctx.makeImage() 会原样包行,翻转 CTM 画进去的图出来是
    /// 上下颠倒的(实测行宽相关度:翻转 1.0)。默认朝向下内存 row0 = 图像顶行,
    /// 与 PetView(isFlipped)的 alphaAt 顶行优先索引一致。
    private func alphaBuffer(for cg: CGImage) -> ([UInt8], Int, Int, CGImage?) {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return ([], 0, 0, nil) }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &bytes, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return ([], 0, 0, nil)
        }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 清理低 alpha 光晕:抗锯齿边缘 alpha 1..15 的像素让窗口服务器把该点
        // 算作鸟窗(点击发给鸟)而 hitTest(阈值16)返回 nil 无人接 → 点击被吞
        // (hover 穿透但点不动的 bug)。清零后:窗口形状 == 可见像素 == 命中判定。
        var a = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let alpha = bytes[i * 4 + 3]
            if alpha < 16 {
                bytes[i * 4] = 0; bytes[i * 4 + 1] = 0; bytes[i * 4 + 2] = 0; bytes[i * 4 + 3] = 0
            } else {
                a[i] = alpha
            }
        }
        let cleaned = ctx.makeImage()   // 清理后的位图
        return (a, w, h, cleaned)
    }

    // MARK: - 音效(多种叫声,随机选)
    private func preparePeeps() {
        peepPlayers = []
        var i = 0
        while true {
            let name = "peep_\(i)"
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { break }
            if let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay()
                peepPlayers.append(p)
            }
            i += 1
        }
        // 兼容旧资源:没有 peep_* 就试 peep.wav
        if peepPlayers.isEmpty, let url = Bundle.main.url(forResource: "peep", withExtension: "wav"),
           let p = try? AVAudioPlayer(contentsOf: url) {
            p.prepareToPlay()
            peepPlayers = [p]
        }
    }

    /// 入睡时停掉正在播/排队中的叫声(锁屏前一瞬开播的没人管)
    func pauseAllPeeps() {
        for p in peepPlayers { p.pause() }
    }

    func playPeep() {
        guard soundOn, !mutedForSleep, !mediaMuted, !peepPlayers.isEmpty else { return }
        let p = peepPlayers.randomElement()!
        p.currentTime = 0
        p.play()
    }
}
