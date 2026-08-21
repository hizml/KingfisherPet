// Win32 栖窗:找最前面那个普通窗口,返回 (上沿中点 x, 上沿 y),物理坐标。
// mac/linux 走 stub(None)。对应 macOS WindowTracker.frontPerch(CGWindowList)。


/// "普通应用窗口"判定(front_perch 与 surfaces_below 共用):
/// 类名黑名单(桌面/任务栏/托盘弹层)+ TOOLWINDOW(系统弹层宿主)+ DWM 隐身。
/// 幽灵栖窗事故:任务栏"显示隐藏的图标"弹层(TopLevelWindowForOverflowXamlIsland)
/// 菜单关了仍以"可见"窗口存在 → 枚举把它当最顶合格窗 → 鸟停托盘区角落。
#[cfg(windows)]
unsafe fn shell_junk_or_cloaked(hwnd: windows::Win32::Foundation::HWND) -> bool {
    use windows::Win32::Foundation::HWND;
    use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED};
    use windows::Win32::UI::WindowsAndMessaging::{GetClassNameW, GetWindowLongPtrW, GWL_EXSTYLE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST};
    const BAD: [&str; 9] = [
        "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd",
        "NotifyIconOverflowWindow", "TrayNotifyWnd", "TopLevelWindowForOverflowXamlIsland",
        "XamlExplorerHostIslandWindow", "Windows.UI.Core.CoreWindow",
    ];
    let mut cls = [0u16; 64];
    let n = GetClassNameW(hwnd, &mut cls).max(0) as usize;
    let name = String::from_utf16_lossy(&cls[..n.min(cls.len())]);
    if BAD.contains(&name.as_str()) { return true; }
    // 工具窗 + 置顶窗:系统弹层/托盘宿主是 TOOLWINDOW;悬浮/系统常驻层是 TOPMOST——
    // macOS 只认 layer-0 普通窗口,两者对齐(幽灵停靠疑凶多为置顶系统窗)
    let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if (ex & WS_EX_TOOLWINDOW.0 as isize) != 0 { return true; }
    if (ex & WS_EX_TOPMOST.0 as isize) != 0 { return true; }
    // DWM 隐身(UWP 挂起等:窗口在、IsWindowVisible 真、视觉上不在)
    let mut cloaked: u32 = 0;
    if DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED,
        &mut cloaked as *mut u32 as *mut core::ffi::c_void, 4).is_ok() {
        if cloaked != 0 { return true; }
    }
    let _ = HWND::default();
    false
}

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
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId, EnumWindows, GetWindowRect, GetClassNameW};
    use windows::Win32::Foundation::{HWND, LPARAM, RECT};
    use windows::Win32::System::Threading::GetCurrentProcessId;
    use std::cell::{Cell, RefCell};

    // extern fn 不能捕获 → 参数走 thread_local(命令单线程,安全)
    thread_local! {
        static MY_PID: Cell<u32> = Cell::new(0);
        static BIRD_W: Cell<u64> = Cell::new(0);
        static FG: Cell<usize> = Cell::new(0);
        static CAND: RefCell<Option<(f64, f64, isize)>> = RefCell::new(None);
    }

    unsafe fn suitable(hwnd: HWND, my_pid: u32, bird_w: f64) -> Option<(f64, f64, isize)> {
        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == my_pid { return None; }
        if shell_junk_or_cloaked(hwnd) { return None; }   // 统一"普通应用窗口"判定
        // 最小化窗口粗滤(位置 -32000;IsWindowVisible 对最小化窗口仍为真,
        // 不滤的话 Z 序兜底会选中它的陈旧矩形 → "虚空停靠")。surfaces_below 早有此滤,这里漏了。
        let mut raw = RECT::default();
        if GetWindowRect(hwnd, &mut raw).is_err() { return None; }
        if raw.left <= -20000 || raw.top <= -20000 { return None; }
        let r: RECT = visible_rect(hwnd)?;
        if (r.right - r.left) < 260 || (r.bottom - r.top) < 160 { return None; }
        Some(((r.left + r.right) as f64 / 2.0 - bird_w / 2.0, r.top as f64, hwnd.0 as isize))
    }

    unsafe extern "system" fn proc(hwnd: HWND, _l: LPARAM) -> windows::core::BOOL {
        unsafe {
            let my_pid = MY_PID.with(|c| c.get());
            let bird_w = f64::from_bits(BIRD_W.with(|c| c.get()));
            let fg = HWND(FG.with(|c| c.get()) as *mut _);
            if hwnd == fg { return windows::core::BOOL(1); }   // 前台已试过(不合格才到这)
            if let Some(hit) = suitable(hwnd, my_pid, bird_w) {
                CAND.with(|c| *c.borrow_mut() = Some(hit));
                return windows::core::BOOL(0);   // 找到首个(Z 序最顶)即停
            }
            windows::core::BOOL(1)
        }
    }

    unsafe {
        let my_pid = GetCurrentProcessId();
        // 1) 前台窗口。托盘菜单点击后前台常是任务栏(高度不够)/桌面(Progman),
        //    之前直接 None → "停到窗口上"点完没反应
        let fg = GetForegroundWindow();
        if !fg.0.is_null() {
            if let Some(hit) = suitable(fg, my_pid, bird_w) { return Some(hit); }
        }
        // 2) 兜底:Z 序从顶到底第一个合格窗口
        MY_PID.with(|c| c.set(my_pid));
        BIRD_W.with(|c| c.set(bird_w.to_bits()));
        FG.with(|c| c.set(fg.0 as usize));
        CAND.with(|c| *c.borrow_mut() = None);
        let _ = EnumWindows(Some(proc), LPARAM(0));
        let hit = CAND.with(|c| *c.borrow());
        if let Some((_, top, h)) = &hit {
            // 兜底选中打日志:下次诊断直接点名幽灵窗是谁(类名+位置)
            let mut cls = [0u16; 64];
            let n = GetClassNameW(HWND(*h as *mut _), &mut cls).max(0) as usize;
            let name = String::from_utf16_lossy(&cls[..n.min(cls.len())]);
            crate::kflog::kflog(&format!("perch: 兜底选中 hwnd={:?} class={} top={}", h, name, *top as i64));
        }
        hit
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
        if shell_junk_or_cloaked(hwnd) { return windows::core::BOOL(1); }   // 托盘弹层/工具窗/UWP 隐身窗不当表面
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

// ── 诊断(坐标问题定位):Win32 侧地面真值 ──

/// 进程 DPI 感知级别(0=unaware / 1=system / 2=per-monitor)。
/// 非 per-monitor 时 Win32 坐标被虚拟化,和 WebView 的物理坐标错位——整类 bug 的判据。
#[cfg(windows)]
pub fn dpi_awareness() -> i32 {
    use windows::Win32::UI::HiDpi::{
        GetThreadDpiAwarenessContext, GetAwarenessFromDpiAwarenessContext,
    };
    unsafe {
        let ctx = GetThreadDpiAwarenessContext();
        GetAwarenessFromDpiAwarenessContext(ctx).0
    }
}

#[cfg(not(windows))]
pub fn dpi_awareness() -> i32 { -1 }

/// 每台显示器:rcMonitor(l,t,r,b) + rcWork(l,t,r,b) 物理 + 有效 DPI。
#[cfg(windows)]
pub fn diag_monitors() -> Vec<(i32, i32, i32, i32, i32, i32, i32, i32, u32)> {
    use windows::Win32::Foundation::{LPARAM, RECT};
    use windows::Win32::Graphics::Gdi::{EnumDisplayMonitors, GetMonitorInfoW, MONITORINFO, HDC};
    use windows::Win32::UI::HiDpi::{GetDpiForMonitor, MDT_EFFECTIVE_DPI};
    use std::cell::RefCell;
    thread_local! {
        static OUT: RefCell<Vec<(i32, i32, i32, i32, i32, i32, i32, i32, u32)>> =
            RefCell::new(Vec::new());
    }
    unsafe extern "system" fn proc(mon: windows::Win32::Graphics::Gdi::HMONITOR, _dc: HDC, _r: *mut RECT, _l: LPARAM) -> windows::core::BOOL {
        let mut mi = MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
        if GetMonitorInfoW(mon, &mut mi).as_bool() {
            let (mut dx, mut dy) = (0u32, 0u32);
            let _ = GetDpiForMonitor(mon, MDT_EFFECTIVE_DPI, &mut dx, &mut dy);
            let RECT { left: ml, top: mt, right: mr, bottom: mb, .. } = mi.rcMonitor;
            let RECT { left: wl, top: wt, right: wr, bottom: wb, .. } = mi.rcWork;
            OUT.with(|o| o.borrow_mut().push((ml, mt, mr, mb, wl, wt, wr, wb, dx)));
        }
        windows::core::BOOL(1)
    }
    unsafe {
        OUT.with(|o| o.borrow_mut().clear());
        let _ = EnumDisplayMonitors(None, None, Some(proc), LPARAM(0));
        OUT.with(|o| o.borrow_mut().clone())
    }
}

#[cfg(not(windows))]
pub fn diag_monitors() -> Vec<(i32, i32, i32, i32, i32, i32, i32, i32, u32)> { Vec::new() }

/// 鸟窗实测:GetWindowRect(物理)+ 窗口 DPI。诊断"窗口实际在哪/多大"。
#[cfg(windows)]
pub fn diag_main_window(w: &tauri::WebviewWindow) -> Option<(i32, i32, i32, i32, u32)> {
    use windows::Win32::Foundation::RECT;
    use windows::Win32::UI::WindowsAndMessaging::GetWindowRect;
    use windows::Win32::UI::HiDpi::GetDpiForWindow;
    let hwnd = w.hwnd().ok()?;
    unsafe {
        let mut r = RECT::default();
        if GetWindowRect(hwnd, &mut r).is_err() { return None; }
        Some((r.left, r.top, r.right, r.bottom, GetDpiForWindow(hwnd)))
    }
}

#[cfg(not(windows))]
pub fn diag_main_window(_w: &tauri::WebviewWindow) -> Option<(i32, i32, i32, i32, u32)> { None }

/// 屏幕物理坐标 (x,y) 处最顶层的【普通应用窗口】hwnd;没有返回 None。
/// 栖窗遮挡检测用(对应 macOS WindowTracker.frontWindowAt)。
#[cfg(windows)]
pub fn window_at_point(x: f64, y: f64) -> Option<isize> {
    use windows::Win32::Foundation::{HWND, LPARAM, RECT};
    use windows::Win32::UI::WindowsAndMessaging::{EnumWindows, GetWindowRect, GetWindowThreadProcessId};
    use windows::Win32::System::Threading::GetCurrentProcessId;
    use std::cell::Cell;
    thread_local! {
        static HIT: Cell<isize> = Cell::new(0);
        static PT: Cell<(f64, f64)> = Cell::new((0.0, 0.0));
        static MY: Cell<u32> = Cell::new(0);
    }
    unsafe extern "system" fn proc(hwnd: HWND, _l: LPARAM) -> windows::core::BOOL {
        unsafe {
            let mut pid: u32 = 0;
            GetWindowThreadProcessId(hwnd, Some(&mut pid));
            if pid == MY.with(|m| m.get()) { return windows::core::BOOL(1); }
            if crate::windows::shell_junk_or_cloaked(hwnd) { return windows::core::BOOL(1); }
            let mut r = RECT::default();
            if GetWindowRect(hwnd, &mut r).is_err() { return windows::core::BOOL(1); }
            let (px, py) = PT.with(|p| p.get());
            if px >= r.left as f64 && px <= r.right as f64 && py >= r.top as f64 && py <= r.bottom as f64 {
                HIT.with(|h| h.set(hwnd.0 as isize));
                return windows::core::BOOL(0);   // Z 序最顶命中即停
            }
            windows::core::BOOL(1)
        }
    }
    unsafe {
        HIT.with(|h| h.set(0));
        PT.with(|p| p.set((x, y)));
        MY.with(|m| m.set(GetCurrentProcessId()));
        let _ = EnumWindows(Some(proc), LPARAM(0));
        let hit = HIT.with(|h| h.get());
        if hit == 0 { None } else { Some(hit) }
    }
}

#[cfg(not(windows))]
pub fn window_at_point(_x: f64, _y: f64) -> Option<isize> { None }


/// z 序断言:main → poop → crack 依次提到置顶带(不显示、不激活)。
/// 舞台(树枝/阴影)必须稳定在鸟之上(用户要求:树枝层级比鸟高;
/// 各处单独 SetWindowPos 会互相翻转,统一收敛)。
#[cfg(windows)]
pub fn raise_no_show(w: &tauri::WebviewWindow) {
    use windows::Win32::UI::WindowsAndMessaging::{SetWindowPos, HWND_TOPMOST, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, SWP_NOOWNERZORDER};
    if let Ok(h) = w.hwnd() {
        unsafe {
            let _ = SetWindowPos(h, Some(HWND_TOPMOST), 0, 0, 0, 0,
                SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_NOOWNERZORDER);
        }
    }
}

#[cfg(not(windows))]
pub fn raise_no_show(w: &tauri::WebviewWindow) { let _ = w; }

/// 全屏应用检测:前台窗是【普通应用窗口】且矩形与所在显示器的整屏矩形
/// 完全一致(最大化窗口只盖工作区,不会命中)。视频/游戏全屏 → 勿扰。
#[cfg(windows)]
pub fn fullscreen_app_present(bird_hwnd_val: isize) -> bool {
    use windows::Win32::Foundation::HWND;
    use windows::Win32::Graphics::Gdi::{MonitorFromWindow, GetMonitorInfoW, MONITORINFO, MONITOR_DEFAULTTONEAREST};
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};
    use windows::Win32::System::Threading::GetCurrentProcessId;
    unsafe {
        let fg = GetForegroundWindow();
        if fg.0.is_null() { return false; }
        let mut pid: u32 = 0;
        GetWindowThreadProcessId(fg, Some(&mut pid));
        if pid == GetCurrentProcessId() { return false; }
        if shell_junk_or_cloaked(fg) { return false; }
        let Some(r) = visible_rect(fg) else { return false; };
        let fg_mon = MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST);
        if fg_mon.is_invalid() { return false; }
        // 只看【鸟所在显示器】的全屏:多屏时副屏看片,主屏的鸟不该跟着消失
        // (macOS 版即查鸟所在屏,此处对齐)
        let bird_mon = MonitorFromWindow(HWND(bird_hwnd_val as *mut _), MONITOR_DEFAULTTONEAREST);
        if !bird_mon.is_invalid() && bird_mon != fg_mon { return false; }
        let mut mi = MONITORINFO { cbSize: std::mem::size_of::<MONITORINFO>() as u32, ..Default::default() };
        if !GetMonitorInfoW(fg_mon, &mut mi).as_bool() { return false; }
        let m = mi.rcMonitor;
        r.left == m.left && r.top == m.top && r.right == m.right && r.bottom == m.bottom
    }
}

#[cfg(not(windows))]
pub fn fullscreen_app_present(_bird_hwnd_val: isize) -> bool { false }

/// 系统有没有在放声音(WASAPI 默认输出设备峰值;>0 即有应用在出声)。
/// 勿扰之一:听歌/看片时鸟不叫。
#[cfg(windows)]
pub fn audio_active() -> bool {
    use windows::Win32::Media::Audio::{IMMDeviceEnumerator, MMDeviceEnumerator, eRender, eConsole};
    use windows::Win32::Media::Audio::Endpoints::IAudioMeterInformation;
    use windows::core::Interface;
    use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_ALL, COINIT_MULTITHREADED};
    unsafe {
        let hr = CoInitializeEx(None, COINIT_MULTITHREADED);
        let need_uninit = hr.is_ok();
        let result = (|| -> Option<f32> {
            let enumerator: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL).ok()?;
            let dev = enumerator.GetDefaultAudioEndpoint(eRender, eConsole).ok()?;
            let meter: IAudioMeterInformation = dev.cast().ok()?;
            meter.GetPeakValue().ok()
        })();
        if need_uninit { CoUninitialize(); }
        result.unwrap_or(0.0) > 0.001
    }
}

#[cfg(not(windows))]
pub fn audio_active() -> bool { false }
