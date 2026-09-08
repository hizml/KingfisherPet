import AppKit
import CoreGraphics

/// 用 CGWindowList 找最前面那个适合停靠的普通窗口,返回其上沿(鸟落点)+ 窗口 ID。
/// 四个查询共享同一套"普通窗口候选"枚举(评审待办:四函数去重)——
/// 过滤口径一致:layer==0 普通层、排除本进程、bounds 可解析、按 Z 序前到后。
enum WindowTracker {

    struct Perch {
        let point: CGPoint      // 主屏 NS 坐标
        let id: CGWindowID
    }

    /// 普通窗口候选(按 CGWindowList 返回顺序 = Z 序前到后)+ 主屏高(CG→NS 换算锚)。
    /// CG 全局坐标锚定主屏(screens[0]);NSScreen.main 是焦点屏,副屏活动时换算会偏。
    private static func normalWindows() -> (list: [(id: CGWindowID, bounds: CGRect)], mainH: CGFloat)? {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]],
              let screen = NSScreen.screens.first else { return nil }   // CG全局坐标锚定主屏(screens[0]);NSScreen.main 是焦点屏,副屏活动时换算会偏
        let myPID = ProcessInfo.processInfo.processIdentifier
        var out: [(id: CGWindowID, bounds: CGRect)] = []
        for info in infos {
            let layer = info[kCGWindowLayer as String] as? Int ?? 99
            guard layer == 0 else { continue }                      // 只看普通窗口
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            guard pid != myPID else { continue }                    // 排除自己的窗口
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let bnds = parseBounds(info) else { continue }
            out.append((wid, bnds))
        }
        return (out, screen.frame.height)
    }

    private static func parseBounds(_ info: [String: Any]) -> CGRect? {
        if let r = info[kCGWindowBounds as String] as? CGRect { return r }
        if let d = info[kCGWindowBounds as String] as? [String: CGFloat],
           let r = CGRect(dictionaryRepresentation: d as CFDictionary) { return r }
        return nil
    }

    static func frontPerch(birdWidth: CGFloat) -> Perch? {
        guard let (wins, mainH) = normalWindows() else { return nil }
        for w in wins {
            guard w.bounds.width > 260, w.bounds.height > 160 else { continue }
            let perchY = mainH - w.bounds.minY
            let perchX = w.bounds.midX - birdWidth / 2
            return Perch(point: CGPoint(x: perchX, y: perchY), id: w.id)
        }
        return nil
    }

    /// 找 point 正下方最近的落点:某普通窗口的上沿,或地面(Dock 上边)。
    /// 返回 (落点 NS-y, 该窗口 id;id 为 nil 表示落在地面)。
    static func landingSpot(belowX x: CGFloat, fromY y: CGFloat,
                            groundY: CGFloat) -> (y: CGFloat, id: CGWindowID?) {
        guard let (wins, mainH) = normalWindows() else { return (groundY, nil) }
        var bestY = groundY
        var bestID: CGWindowID? = nil
        for w in wins {
            guard w.bounds.width > 200, w.bounds.height > 120 else { continue }
            guard x >= w.bounds.minX, x <= w.bounds.maxX else { continue }     // 水平覆盖该列
            let topNS = mainH - w.bounds.minY                          // 窗口上沿 NS-y
            if topNS < y - 6, topNS > bestY {                          // 在屎下方且更高
                bestY = topNS; bestID = w.id
            }
        }
        return (bestY, bestID)
    }

    /// 屏幕某点(NS 坐标)上最前面的普通窗口 id;没有(桌面)返回 nil。用于判断是否被盖住。
    static func frontWindowAt(nsPoint p: CGPoint) -> CGWindowID? {
        guard let (wins, mainH) = normalWindows() else { return nil }
        let cgX = p.x
        let cgY = mainH - p.y
        for w in wins {                                             // 前到后
            guard w.bounds.width > 200, w.bounds.height > 120 else { continue }
            if w.bounds.contains(CGPoint(x: cgX, y: cgY)) { return w.id }
        }
        return nil
    }

    /// 按 ID 查窗口当前帧(CG 坐标,左上原点);找不到返回 nil
    static func frameOfWindow(id: CGWindowID) -> CGRect? {
        guard let infos = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let info = infos.first else { return nil }
        return parseBounds(info)
    }

    /// 找离 feetY 最近的"可踩表面":水平覆盖 x 的窗口上沿(NS-y)或 Dock 顶。
    /// 上下方都找(鸟脚高于/低于上沿都算),取绝对距离最近的。用于拖动松手吸附。
    /// 返回 (表面 y, 窗口 id;id=nil 表示 Dock/地面)。
    static func nearestSurface(atX x: CGFloat, feetY: CGFloat,
                               groundY: CGFloat) -> (y: CGFloat, id: CGWindowID?) {
        guard let (wins, mainH) = normalWindows() else { return (groundY, nil) }
        // Dock 顶作为候选
        var bestY = groundY
        var bestID: CGWindowID? = nil
        var bestDist = abs(groundY - feetY)
        for w in wins {
            guard w.bounds.width > 200, w.bounds.height > 120 else { continue }
            guard x >= w.bounds.minX, x <= w.bounds.maxX else { continue }     // 水平覆盖该列
            let topNS = mainH - w.bounds.minY                          // 窗口上沿 NS-y
            let dist = abs(topNS - feetY)
            if dist < bestDist { bestDist = dist; bestY = topNS; bestID = w.id }
        }
        return (bestY, bestID)
    }
}
