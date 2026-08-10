// Win32 栖窗:找最前面那个普通窗口,返回 (上沿中点 x, 上沿 y),物理坐标。
// mac/linux 走 stub(None)。对应 macOS WindowTracker.frontPerch(CGWindowList)。

#[cfg(windows)]
pub fn front_perch(bird_w: f64) -> Option<(f64, f64)> {
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowRect, GetWindowThreadProcessId};
    use windows::Win32::Foundation::RECT;
    use windows::Win32::System::Threading::GetCurrentProcessId;
    unsafe {
        let hwnd = GetForegroundWindow();
        if hwnd.0 == 0 { return None; }
        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == GetCurrentProcessId() { return None; }   // 排除自己
        let mut r = RECT::default();
        if GetWindowRect(hwnd, &mut r).is_err() { return None; }
        if (r.right - r.left) < 260 || (r.bottom - r.top) < 160 { return None; }
        let cx = (r.left + r.right) as f64 / 2.0 - bird_w / 2.0;
        Some((cx, r.top as f64))
    }
}

#[cfg(not(windows))]
pub fn front_perch(_bird_w: f64) -> Option<(f64, f64)> {
    None   // mac/linux dev:无栖窗
}
