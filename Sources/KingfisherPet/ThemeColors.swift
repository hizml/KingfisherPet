import AppKit
import Foundation

/// 主题色查询:加载当前主题的 colors.json(Sprites/<theme>/colors.json),
/// 提供 effects 的颜色(屎/zzz/音符/太阳/水花/裂纹),自动跟主题走。
/// 主题切换时由 SpriteLibrary.reload 触发重载。
final class ThemeColors {
    static let shared = ThemeColors()

    /// colors.json 的所有色键 → [r,g,b,a](0-255)
    private var colors: [String: [Int]] = [:]

    private init() {
        load(theme: SpriteLibrary.shared.currentTheme)
        // 主题切换时重载
        SpriteLibrary.shared.observeThemeChanged { [weak self] in
            self?.load(theme: SpriteLibrary.shared.currentTheme)
        }
    }

    private func load(theme: String) {
        // 子目录形式
        if let url = Bundle.main.url(forResource: "colors", withExtension: "json",
                                     subdirectory: "Sprites/\(theme)"),
           let data = try? Data(contentsOf: url),
           let m = try? JSONSerialization.jsonObject(with: data) as? [String: [Int]] {
            colors = m
            return
        }
        // 兜底:主 bundle 根
        if let url = Bundle.main.url(forResource: "colors", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let m = try? JSONSerialization.jsonObject(with: data) as? [String: [Int]] {
            colors = m
        }
    }

    /// 取色:name 对应 colors.json 的键;返回 NSColor。找不到用 fallback。
    func color(_ name: String, fallback: NSColor = .white) -> NSColor {
        guard let c = colors[name], c.count >= 3 else { return fallback }
        let r = CGFloat(c[0]) / 255
        let g = CGFloat(c[1]) / 255
        let b = CGFloat(c[2]) / 255
        let a = c.count >= 4 ? CGFloat(c[3]) / 255 : 1
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }

    /// 便利:直接拿 CGColor
    func cgColor(_ name: String, fallback: NSColor = .white) -> CGColor {
        color(name, fallback: fallback).cgColor
    }
}
