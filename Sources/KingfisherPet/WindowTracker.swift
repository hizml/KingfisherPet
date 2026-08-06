import AppKit
import CoreGraphics

/// 用 CGWindowList 找最前面那个适合停靠的普通窗口,返回其上沿(鸟落点)在主屏 NS 坐标。
enum WindowTracker {
    static func frontPerch(birdWidth: CGFloat) -> CGPoint? {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]],
              let screen = NSScreen.main else { return nil }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let sf = screen.frame

        for info in infos {
            let layer = info[kCGWindowLayer as String] as? Int ?? 99
            guard layer == 0 else { continue }                      // 只看普通窗口
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            guard pid != myPID else { continue }                    // 排除自己的窗口
            // 稳健取 bounds:可能是 CGRect 也可能是字典
            var bnds = CGRect.zero
            if let r = info[kCGWindowBounds as String] as? CGRect {
                bnds = r
            } else if let d = info[kCGWindowBounds as String] as? [String: CGFloat],
                      let r = CGRect(dictionaryRepresentation: d as CFDictionary) {
                bnds = r
            } else {
                continue
            }
            // 只排除过小的(菜单条/小面板),允许最大化/全屏窗口
            guard bnds.width > 260, bnds.height > 160 else { continue }
            // CG 原点在左上角:窗口上沿 = bnds.minY;转主屏 NS 坐标 = 高度 - cgY
            let perchY = sf.height - bnds.minY
            let perchX = bnds.midX - birdWidth / 2
            return CGPoint(x: perchX, y: perchY)
        }
        return nil
    }
}
