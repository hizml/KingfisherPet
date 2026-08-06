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

/// 全局 sprite 资源库(启动时一次性加载)
final class SpriteLibrary {
    static let shared = SpriteLibrary()

    private(set) var frames: [String: PetFrame] = [:]
    private(set) var manifest = SpriteManifest(fps: [:], sequences: [:])
    private var peepPlayer: AVAudioPlayer?

    var soundOn = true

    private init() {
        loadManifest()
        loadFrames()
        preparePeep()
    }

    // MARK: - 加载
    private func loadManifest() {
        guard let url = Bundle.main.url(forResource: "sprites", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(SpriteManifest.self, from: data) else {
            // 兜底,保证即使资源没找到也能跑(用空序列,后面会回落到 idle_0)
            print("[KingfisherPet] 警告:未找到 sprites.json")
            return
        }
        manifest = m
    }

    private func loadFrames() {
        // 收集所有出现的帧名
        var names = Set<String>()
        for seq in manifest.sequences.values { names.formUnion(seq) }
        names.insert("idle_0") // 兜底

        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let img = NSImage(contentsOf: url),
                  let cg = cgImage(of: img) else {
                print("[KingfisherPet] 警告:缺少帧 \(name).png")
                continue
            }
            let (alpha, w, h) = alphaBuffer(for: cg)
            frames[name] = PetFrame(image: img, cgImage: cg, alpha: alpha, w: w, h: h)
        }
    }

    func frame(_ name: String) -> PetFrame? { frames[name] }
    func sequence(_ state: String) -> [String]? { manifest.sequences[state] }
    func fps(_ state: String) -> Double { manifest.fps[state] ?? 8 }

    private func cgImage(of nsImage: NSImage) -> CGImage? {
        nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// 把 cgImage 渲染到 RGBA 缓冲,提取 alpha 通道(顶行在前)
    private func alphaBuffer(for cg: CGImage) -> ([UInt8], Int, Int) {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return ([], 0, 0) }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &bytes, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return ([], 0, 0)
        }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        // 翻转,使缓冲顶行 == 图像顶行
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var a = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) { a[i] = bytes[i * 4 + 3] }
        return (a, w, h)
    }

    // MARK: - 音效
    private func preparePeep() {
        guard let url = Bundle.main.url(forResource: "peep", withExtension: "wav") else { return }
        peepPlayer = try? AVAudioPlayer(contentsOf: url)
        peepPlayer?.prepareToPlay()
    }

    func playPeep() {
        guard soundOn, let p = peepPlayer else { return }
        p.currentTime = 0
        p.play()
    }
}
