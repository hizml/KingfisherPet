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
        if let m = readColors(theme: theme) {
            colors = m
        } else if let m = readColors(theme: nil) {   // 兜底:主 bundle 根
            colors = m
        }
        NSLog("KF ThemeColors load theme=\(theme) keys=\(colors.count)")
    }

    /// 解析某主题的 colors.json:优先 Sprites/<theme>/,theme=nil 时读 bundle 根。
    /// 用 compactMap 逐个 NSNumber→Int,比 `as? [String:[Int]]` 稳健——后者对 NSArray of NSNumber
    /// 会整批转换,任一元素类型不符就全盘失败,导致 colors 为空、所有特效走 fallback 固定色(主题切了也不变)。
    private func readColors(theme: String?) -> [String: [Int]]? {
        let url: URL?
        if let t = theme {
            url = Bundle.main.url(forResource: "colors", withExtension: "json", subdirectory: "Sprites/\(t)")
        } else {
            url = Bundle.main.url(forResource: "colors", withExtension: "json")
        }
        guard let u = url, let data = try? Data(contentsOf: u),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var m: [String: [Int]] = [:]
        for (k, v) in raw {
            guard let arr = v as? [Any] else { continue }
            let ints = arr.compactMap { ($0 as? NSNumber)?.intValue }
            if ints.count == arr.count { m[k] = ints }
        }
        return m.isEmpty ? nil : m
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
