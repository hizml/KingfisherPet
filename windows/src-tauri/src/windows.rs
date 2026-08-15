// Win32 栖窗:找最前面那个普通窗口,返回 (上沿中点 x, 上沿 y),物理坐标。
// mac/linux 走 stub(None)。对应 macOS WindowTracker.frontPerch(CGWindowList)。

#[cfg(windows)]
pub fn front_perch(bird_w: f64) -> Option<(f64, f64, isize)> {
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowRect, GetWindowThreadProcessId};
    use windows::Win32::Foundation::RECT;
    use windows::Win32::System::Threading::GetCurrentProcessId;
    unsafe {
        let hwnd = GetForegroundWindow();
        if hwnd.0.is_null() { return None; }   // windows crate V0.61 HWND.0 是 *mut c_void
        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == GetCurrentProcessId() { return None; }   // 排除自己
        let mut r = RECT::default();
        if GetWindowRect(hwnd, &mut r).is_err() { return None; }
        if (r.right - r.left) < 260 || (r.bottom - r.top) < 160 { return None; }
        let cx = (r.left + r.right) as f64 / 2.0 - bird_w / 2.0;
        Some((cx, r.top as f64, hwnd.0 as isize))
    }
}

#[cfg(not(windows))]
pub fn front_perch(_bird_w: f64) -> Option<(f64, f64, isize)> {
    None   // mac/linux dev:无栖窗
}

/// 全局光标位置(物理像素)。穿透模式下 webview 收不到 mousemove,
/// 前端轮询此命令判断光标是否在鸟身上(alpha 命中)→ 切换 setIgnoreCursorEvents。
#[cfg(windows)]
pub fn cursor_pos() -> Option<(f64, f64)> {
    use windows::Win32::UI::WindowsAndMessaging::GetCursorPos;
    use windows::Win32::Foundation::POINT;
    unsafe {
        let mut p = POINT::default();
        if GetCursorPos(&mut p).is_err() { return None; }
        Some((p.x as f64, p.y as f64))
    }
}

#[cfg(not(windows))]
pub fn cursor_pos() -> Option<(f64, f64)> {
    None
}

/// 按 HWND 查窗口矩形(物理像素),栖窗增量跟随用。窗口不存在返回 None。
#[cfg(windows)]
pub fn window_rect(hwnd_val: isize) -> Option<(f64, f64, f64, f64)> {
    use windows::Win32::UI::WindowsAndMessaging::{GetWindowRect, IsWindow};
    use windows::Win32::Foundation::{HWND, RECT};
    unsafe {
        let hwnd = HWND(hwnd_val as *mut _);
        if !IsWindow(Some(hwnd)).as_bool() { return None; }
        let mut r = RECT::default();
        if GetWindowRect(hwnd, &mut r).is_err() { return None; }
        Some((r.left as f64, r.top as f64, (r.right - r.left) as f64, (r.bottom - r.top) as f64))
    }
}

#[cfg(not(windows))]
pub fn window_rect(_hwnd_val: isize) -> Option<(f64, f64, f64, f64)> {
    None
}
