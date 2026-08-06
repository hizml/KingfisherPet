import AppKit
import CoreGraphics

/// 用 CGWindowList 找最前面那个适合停靠的普通窗口,返回其上沿(鸟落点)+ 窗口 ID。
enum WindowTracker {

    struct Perch {
        let point: CGPoint      // 主屏 NS 坐标
        let id: CGWindowID
    }

    static func frontPerch(birdWidth: CGFloat) -> Perch? {
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
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            var bnds = CGRect.zero
            if let r = info[kCGWindowBounds as String] as? CGRect {
                bnds = r
            } else if let d = info[kCGWindowBounds as String] as? [String: CGFloat],
                      let r = CGRect(dictionaryRepresentation: d as CFDictionary) {
                bnds = r
            } else {
                continue
            }
            guard bnds.width > 260, bnds.height > 160 else { continue }
            let perchY = sf.height - bnds.minY
            let perchX = bnds.midX - birdWidth / 2
            return Perch(point: CGPoint(x: perchX, y: perchY), id: wid)
        }
        return nil
    }

    /// 找 point 正下方最近的落点:某普通窗口的上沿,或地面(Dock 上边)。
    /// 返回 (落点 NS-y, 该窗口 id;id 为 nil 表示落在地面)。
    static func landingSpot(belowX x: CGFloat, fromY y: CGFloat,
                            groundY: CGFloat) -> (y: CGFloat, id: CGWindowID?) {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]],
              let screen = NSScreen.main else { return (groundY, nil) }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let sf = screen.frame
        var bestY = groundY
        var bestID: CGWindowID? = nil

        for info in infos {
            let layer = info[kCGWindowLayer as String] as? Int ?? 99
            guard layer == 0 else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            guard pid != myPID else { continue }
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            var bnds = CGRect.zero
            if let r = info[kCGWindowBounds as String] as? CGRect { bnds = r }
            else if let d = info[kCGWindowBounds as String] as? [String: CGFloat],
                    let r = CGRect(dictionaryRepresentation: d as CFDictionary) { bnds = r }
            else { continue }
            guard bnds.width > 200, bnds.height > 120 else { continue }
            guard x >= bnds.minX, x <= bnds.maxX else { continue }     // 水平覆盖该列
            let topNS = sf.height - bnds.minY                          // 窗口上沿 NS-y
            if topNS < y - 6, topNS > bestY {                          // 在屎下方且更高
                bestY = topNS; bestID = wid
            }
        }
        return (bestY, bestID)
    }

    /// 按 ID 查窗口当前帧(CG 坐标,左上原点);找不到返回 nil
    static func frameOfWindow(id: CGWindowID) -> CGRect? {
        guard let infos = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let info = infos.first else { return nil }
        if let r = info[kCGWindowBounds as String] as? CGRect { return r }
        if let d = info[kCGWindowBounds as String] as? [String: CGFloat],
           let r = CGRect(dictionaryRepresentation: d as CFDictionary) { return r }
        return nil
    }
}
