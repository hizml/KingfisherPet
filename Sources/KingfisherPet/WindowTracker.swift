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
              let screen = NSScreen.screens.first else { return nil }   // CG全局坐标锚定主屏(screens[0]);NSScreen.main 是焦点屏,副屏活动时换算会偏
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
              let screen = NSScreen.screens.first else { return (groundY, nil) }   // 同上:换算锚必须是主屏
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

    /// 屏幕某点(NS 坐标)上最前面的普通窗口 id;没有(桌面)返回 nil。用于判断是否被盖住。
    static func frontWindowAt(nsPoint p: CGPoint) -> CGWindowID? {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]],
              let screen = NSScreen.screens.first else { return nil }   // CG全局坐标锚定主屏(screens[0]);NSScreen.main 是焦点屏,副屏活动时换算会偏
        let myPID = ProcessInfo.processInfo.processIdentifier
        let cgX = p.x
        let cgY = screen.frame.height - p.y
        for info in infos {                                       // 前到后
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
            if bnds.contains(CGPoint(x: cgX, y: cgY)) { return wid }
        }
        return nil
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

    /// 找离 feetY 最近的"可踩表面":水平覆盖 x 的窗口上沿(NS-y)或 Dock 顶。
    /// 上下方都找(鸟脚高于/低于上沿都算),取绝对距离最近的。用于拖动松手吸附。
    /// 返回 (表面 y, 窗口 id;id=nil 表示 Dock/地面)。
    static func nearestSurface(atX x: CGFloat, feetY: CGFloat,
                               groundY: CGFloat) -> (y: CGFloat, id: CGWindowID?) {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]],
              let screen = NSScreen.screens.first else { return (groundY, nil) }   // 同上:换算锚必须是主屏
        let myPID = ProcessInfo.processInfo.processIdentifier
        let sf = screen.frame
        // Dock 顶作为候选
        var bestY = groundY
        var bestID: CGWindowID? = nil
        var bestDist = abs(groundY - feetY)
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
            let dist = abs(topNS - feetY)
            if dist < bestDist { bestDist = dist; bestY = topNS; bestID = wid }
        }
        return (bestY, bestID)
    }
}
