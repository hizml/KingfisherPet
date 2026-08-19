// Win32 栖窗:找最前面那个普通窗口,返回 (上沿中点 x, 上沿 y),物理坐标。
// mac/linux 走 stub(None)。对应 macOS WindowTracker.frontPerch(CGWindowList)。

/// 窗口【可见】矩形(物理)。GetWindowRect 对最大化窗口返回含隐形调整边框的
/// 矩形(典型上/左/右各多 7-8px),鸟停上去脚下悬空;DWM 扩展边框才是真可见区。
/// DWM 查询失败(极少数窗口)退回 GetWindowRect。
#[cfg(windows)]
unsafe fn visible_rect(hwnd: windows::Win32::Foundation::HWND) -> Option<windows::Win32::Foundation::RECT> {
    use windows::Win32::Foundation::RECT;
    use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_EXTENDED_FRAME_BOUNDS};
    use windows::Win32::UI::WindowsAndMessaging::GetWindowRect;
    let mut r = RECT::default();
    let ok = DwmGetWindowAttribute(
        hwnd,
        DWMWA_EXTENDED_FRAME_BOUNDS,
        &mut r as *mut RECT as *mut core::ffi::c_void,
        std::mem::size_of::<RECT>() as u32,
    );
    if ok.is_ok() && r.right > r.left && r.bottom > r.top { return Some(r); }
    if GetWindowRect(hwnd, &mut r).is_ok() { Some(r) } else { None }
}

#[cfg(windows)]
pub fn front_perch(bird_w: f64) -> Option<(f64, f64, isize)> {
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};
    use windows::Win32::Foundation::RECT;
    use windows::Win32::System::Threading::GetCurrentProcessId;
    unsafe {
        let hwnd = GetForegroundWindow();
        if hwnd.0.is_null() { return None; }   // windows crate V0.61 HWND.0 是 *mut c_void
        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == GetCurrentProcessId() { return None; }   // 排除自己
        let r: RECT = visible_rect(hwnd)?;
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
    use windows::Win32::UI::WindowsAndMessaging::IsWindow;
    use windows::Win32::Foundation::HWND;
    unsafe {
        let hwnd = HWND(hwnd_val as *mut _);
        if !IsWindow(Some(hwnd)).as_bool() { return None; }
        let r = visible_rect(hwnd)?;
        Some((r.left as f64, r.top as f64, (r.right - r.left) as f64, (r.bottom - r.top) as f64))
    }
}

#[cfg(not(windows))]
pub fn window_rect(_hwnd_val: isize) -> Option<(f64, f64, f64, f64)> {
    None
}

/// 枚举水平覆盖 x 的普通可见窗口,返回 (left, top, width, hwnd) 物理坐标。
/// 拖拽松手"吸附最近表面(窗口上沿/任务栏)"用。对应 macOS nearestSurface。
#[cfg(windows)]
pub fn surfaces_below(x: f64) -> Vec<(f64, f64, f64, isize)> {
    use windows::Win32::UI::WindowsAndMessaging::{EnumWindows, IsWindowVisible, GetWindowThreadProcessId};
    use windows::Win32::Foundation::{HWND, LPARAM, RECT};
    use windows::Win32::System::Threading::GetCurrentProcessId;
    use std::cell::RefCell;
    thread_local! {
        static OUT: RefCell<Vec<(f64, f64, f64, isize)>> = RefCell::new(Vec::new());
    }
    unsafe extern "system" fn proc(hwnd: HWND, _lparam: LPARAM) -> windows::core::BOOL {
        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == GetCurrentProcessId() { return windows::core::BOOL(1); }   // 排除自己
        if !IsWindowVisible(hwnd).as_bool() { return windows::core::BOOL(1); }
        // 最小化窗口位置在 (-32000,-32000),先粗滤掉再进 DWM 查询
        let mut raw = RECT::default();
        if windows::Win32::UI::WindowsAndMessaging::GetWindowRect(hwnd, &mut raw).is_err() { return windows::core::BOOL(1); }
        if raw.left <= -20000 || raw.top <= -20000 { return windows::core::BOOL(1); }
        let Some(r) = visible_rect(hwnd) else { return windows::core::BOOL(1); };
        let (w, h) = (r.right - r.left, r.bottom - r.top);
        if w < 200 || h < 120 { return windows::core::BOOL(1); }   // 只要普通尺寸窗口
        // WS_EX_TOOLWINDOW(9?) 不查了:用可见+尺寸过滤已够
        OUT.with(|o| o.borrow_mut().push((r.left as f64, r.top as f64, w as f64, hwnd.0 as isize)));
        windows::core::BOOL(1)
    }
    unsafe {
        OUT.with(|o| o.borrow_mut().clear());
        let _ = EnumWindows(Some(proc), LPARAM(0));
        let mut v: Vec<(f64, f64, f64, isize)> = OUT.with(|o| o.borrow_mut().clone());
        // 水平覆盖 x 的才留
        v.retain(|s| x >= s.0 && x <= s.0 + s.2);
        v
    }
}

#[cfg(not(windows))]
pub fn surfaces_below(_x: f64) -> Vec<(f64, f64, f64, isize)> {
    Vec::new()
}

/// 显示窗口但不激活(SetWindowPos SHOWWINDOW|NOACTIVATE),防 show() 抢前台焦点。
#[cfg(windows)]
pub fn show_no_activate(w: &tauri::WebviewWindow) {
    use windows::Win32::UI::WindowsAndMessaging::{SetWindowPos, HWND_TOPMOST, SWP_SHOWWINDOW, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE};
    use windows::Win32::Foundation::HWND;
    if let Ok(h) = w.hwnd() {
        unsafe {
            let _ = SetWindowPos(HWND(h.0 as _), Some(HWND_TOPMOST), 0, 0, 0, 0,
                SWP_SHOWWINDOW | SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
        }
    }
}

#[cfg(not(windows))]
pub fn show_no_activate(w: &tauri::WebviewWindow) {
    let _ = w.show();   // 非 Windows 退化为普通显示
}

/// 鸟所在显示器的【工作区】(物理像素,已扣任务栏;任务栏在任意边都对)。
/// MonitorFromWindow(最近的显示器) + GetMonitorInfoW.rcWork。
/// 返回 (x, y, w, h)。屏幕坐标统一物理化的基石。
#[cfg(windows)]
pub fn work_area(hwnd_val: isize) -> Option<(i32, i32, i32, i32)> {
    use windows::Win32::Graphics::Gdi::{MonitorFromWindow, GetMonitorInfoW, MONITORINFO, MONITOR_DEFAULTTONEAREST};
    use windows::Win32::Foundation::{HWND, RECT};
    unsafe {
        let hwnd = HWND(hwnd_val as *mut _);
        let mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
        if mon.is_invalid() { return None; }
        let mut mi = MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
        if !GetMonitorInfoW(mon, &mut mi).as_bool() { return None; }
        let RECT { left, top, right, bottom, .. } = mi.rcWork;
        Some((left, top, right - left, bottom - top))
    }
}

/// 找回小鸟(Rust 侧自愈,不经过 webview——鸟窗隐藏/前端状态废掉时 TS 指令不可靠):
/// 光标所在显示器的工作区右下角,脚踩任务栏顶,原子地 移动+显示+置顶+不抢焦点。
/// 返回落点物理坐标(日志/前端缓存用)。
#[cfg(windows)]
pub fn recall_show(w: &tauri::WebviewWindow) -> Option<(i32, i32)> {
    use windows::Win32::Foundation::{POINT, RECT};
    use windows::Win32::Graphics::Gdi::{MonitorFromPoint, GetMonitorInfoW, MONITORINFO, MONITOR_DEFAULTTONEAREST};
    use windows::Win32::UI::WindowsAndMessaging::{
        GetCursorPos, GetWindowRect, SetWindowPos, HWND_TOPMOST,
        SWP_NOACTIVATE, SWP_SHOWWINDOW, SWP_NOSIZE,
    };
    let hwnd = w.hwnd().ok()?;
    unsafe {
        // 光标所在显示器(用户正看着的那块);查不到光标就主屏原点
        let mut pt = POINT::default();
        if GetCursorPos(&mut pt).is_err() { pt = POINT { x: 0, y: 0 }; }
        let mon = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
        if mon.is_invalid() { return None; }
        let mut mi = MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
        if !GetMonitorInfoW(mon, &mut mi).as_bool() { return None; }
        let RECT { right, bottom, .. } = mi.rcWork;
        // 鸟窗物理尺寸实测;脚在窗底上方 26/160、右边距 30/160(比例 DPI 无关)
        let mut wr = RECT::default();
        if GetWindowRect(hwnd, &mut wr).is_err() { return None; }
        let wpx = (wr.right - wr.left).max(1);
        let hpx = (wr.bottom - wr.top).max(1);
        let x = right - wpx - wpx * 30 / 160;
        let y = bottom - hpx + hpx * 26 / 160;   // 窗底越过工作区底 26/160 → 脚正好踩任务栏顶
        let _ = SetWindowPos(hwnd, Some(HWND_TOPMOST), x, y, 0, 0,
            SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_NOSIZE);
        Some((x, y))
    }
}

#[cfg(not(windows))]
pub fn recall_show(w: &tauri::WebviewWindow) -> Option<(i32, i32)> {
    let _ = w.show();
    None
}
