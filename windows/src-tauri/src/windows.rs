// Win32 窗口枚举(栖窗/落点)。mac dev 用 stub(返回 None),Windows CI 上实现 EnumWindows。
// 对应 macOS WindowTracker(CGWindowListCopyWindowInfo)。

/// 找最前面那个适合停靠的普通窗口,返回 (上沿中点 x, 上沿 y),物理坐标。无则 None。
#[cfg(windows)]
pub fn front_perch(_bird_w: f64) -> Option<(f64, f64)> {
    // TODO(Windows):用 windows crate 的 EnumWindows + GetWindowRect,
    // 过滤 layer 0 / 非自己 / 宽>260 高>160,返回最前窗口上沿中点。
    None
}

#[cfg(not(windows))]
pub fn front_perch(_bird_w: f64) -> Option<(f64, f64)> {
    None   // mac/linux dev:无栖窗
}
