// Windows 睡眠/锁屏检测。两条机制,同一个后台线程(2s 一跳):
// 1) 系统睡眠:GetTickCount64 跳变(醒来观测到"睡了远超 2s")→ 先 sleep 后 wake
//    (前端 sleepForUserAbsence→wakeFromUserAbsence 赖床)。
// 2) 锁屏(不睡眠的场景):OpenInputDesktop 探测——锁屏时输入桌面切到 winlogon,
//    普通进程打不开 ⇒ 判定已锁。锁 → emit sleep;解锁 → emit wake。
//    没有它,锁屏走人机器不睡时鸟会整天空转(60fps+IPC 轮询),纯耗电。

use tauri::Manager;   // get_webview_window 需要 Manager trait
#[cfg(windows)]
pub fn setup_power(app: tauri::AppHandle) {
    use tauri::Emitter;
    std::thread::spawn(move || {
        use windows::Win32::System::SystemInformation::GetTickCount64;
        use windows::Win32::System::StationsAndDesktops::{OpenInputDesktop, CloseDesktop, DESKTOP_READOBJECTS, DESKTOP_CONTROL_FLAGS};
        let mut last_tick = unsafe { GetTickCount64() };
        let mut locked = false;
        // 勿扰检测(去抖计数):全屏应用 → dnd(鸟隐身+静音);系统在放声音 → media(不叫)
        let mut fs_on = 0u32; let mut fs_off = 0u32; let mut dnd = false;
        let mut au_on = 0u32; let mut au_off = 0u32; let mut media = false;
        loop {
            std::thread::sleep(std::time::Duration::from_secs(2));

            // --- 真睡眠唤醒(时钟跳变) ---
            let now = unsafe { GetTickCount64() };
            let gap = now - last_tick;
            last_tick = now;
            if gap > 15_000 {
                crate::kflog::kflog(&format!("power: 系统睡眠唤醒(间隔 {}s),sleep 即发、wake 延迟 3s(系统未稳不动,Mac 同款保守性)", gap / 1000));
                let _ = app.emit("sleep", ());
                // wake 延迟 3s:唤醒瞬间层级/输入未稳,别抢(对齐 macOS resumeAfterWake 的 3s 延迟哲学)
                let h = app.clone();
                std::thread::spawn(move || {
                    std::thread::sleep(std::time::Duration::from_secs(3));
                    crate::kflog::kflog("power: 延迟 wake 已发");
                    use tauri::Emitter;
                    let _ = h.emit("wake", ());
                });
                continue;
            }

            // --- 勿扰:全屏应用(视频/游戏全屏,鸟不能盖上去也不能叫) ---
            let bird_hwnd = app.get_webview_window("main")
                .and_then(|w| w.hwnd().ok())
                .map(|h| h.0 as isize)
                .unwrap_or(0);
            let fs = crate::windows::fullscreen_app_present(bird_hwnd);
            if fs { fs_on += 1; fs_off = 0; } else { fs_off += 1; fs_on = 0; }
            if !dnd && fs_on >= 2 {
                dnd = true;
                crate::DND.store(true, std::sync::atomic::Ordering::Relaxed);
                crate::kflog::kflog("dnd: 全屏应用,进入勿扰");
                let _ = app.emit("dnd", true);
            } else if dnd && fs_off >= 2 {
                dnd = false;
                crate::DND.store(false, std::sync::atomic::Ordering::Relaxed);
                crate::kflog::kflog("dnd: 全屏退出,恢复");
                let _ = app.emit("dnd", false);
            }
            // --- 勿扰:系统在放声音(听歌/看片,鸟不叫) ---
            let au = crate::windows::audio_active();
            if au { au_on += 1; au_off = 0; } else { au_off += 1; au_on = 0; }
            if !media && au_on >= 3 {
                media = true;
                crate::kflog::kflog("media: 检测到放音,鸟静音");
                let _ = app.emit("media", true);
            } else if media && au_off >= 3 {
                media = false;
                crate::kflog::kflog("media: 放音结束,恢复叫声");
                let _ = app.emit("media", false);
            }

            // --- 锁屏探测 ---
            let is_locked = unsafe {
                match OpenInputDesktop(DESKTOP_CONTROL_FLAGS(0), false, DESKTOP_READOBJECTS) {
                    Ok(h) => { let _ = CloseDesktop(h); false }
                    Err(_) => true,   // 打不开输入桌面(winlogon)= 已锁屏
                }
            };
            if is_locked && !locked {
                locked = true;
                crate::kflog::kflog("power: 锁屏 → sleep");
                let _ = app.emit("sleep", ());
            } else if !is_locked && locked {
                locked = false;
                crate::kflog::kflog("power: 解锁 → wake");
                let _ = app.emit("wake", ());
            }
        }
    });
}

/// 远程桌面会话监听:WM_WTSSESSION_CHANGE(解锁/远程重连)时通知前端重载。
/// 动机:WebView2 在 RDP 会话切换后合成器会丢失,页面活着但贴图不显示
/// (用户报告"运行一会儿贴图消失,疑似远程桌面");页面内无法自检,
/// 只能靠会话事件触发 location.reload() 自愈。
#[cfg(windows)]
pub fn setup_session_monitor(app: tauri::AppHandle) {
    use tauri::Emitter;
    std::thread::spawn(move || {
        use windows::Win32::UI::WindowsAndMessaging::{GetMessageW, CreateWindowExW, MSG, WS_OVERLAPPED, WINDOW_EX_STYLE};
        use windows::Win32::System::RemoteDesktop::WTSRegisterSessionNotification;
        use windows::Win32::Foundation::HWND;
        use windows::core::PCWSTR;
        const WM_WTSSESSION_CHANGE: u32 = 0x02B1;
        const NOTIFY_FOR_THIS_SESSION: u32 = 0;
        const WTS_SESSION_UNLOCK: u32 = 0x8;
        const WTS_SESSION_REMOTE_CONNECT: u32 = 0x9;
        unsafe {
            // 隐藏消息窗:用内置 STATIC 类(免注册/WndProc),只收会话通知
            let hwnd = CreateWindowExW(
                WINDOW_EX_STYLE(0),
                PCWSTR(windows::core::w!("STATIC").as_ptr()),
                PCWSTR(windows::core::w!("").as_ptr()),
                WS_OVERLAPPED, 0, 0, 0, 0,
                None, None, None, None,
            );
            let Ok(hwnd) = hwnd else { return };
            let _ = WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION);
            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).as_bool() {
                if msg.message == WM_WTSSESSION_CHANGE {
                    let evt = msg.wParam.0 as u32;
                    // 解锁或远程重连:合成器可能已丢,通知前端重载自愈
                    if evt == WTS_SESSION_UNLOCK || evt == WTS_SESSION_REMOTE_CONNECT {
                        crate::kflog::kflog(&format!("session: 会话恢复(evt={evt}),通知前端重载"));
                        let _ = app.emit("session-change", ());
                    }
                }
            }
            let _ = HWND::default();
        }
    });
}

#[cfg(not(windows))]
pub fn setup_session_monitor(_app: tauri::AppHandle) {}

#[cfg(not(windows))]
pub fn setup_power(_app: tauri::AppHandle) {
    // mac:用原生 Swift 版,Tauri mac 端不需要
}
