// Windows 睡眠/锁屏检测。两条机制,同一个后台线程(2s 一跳):
// 1) 系统睡眠:GetTickCount64 跳变(醒来观测到"睡了远超 2s")→ 先 sleep 后 wake
//    (前端 sleepForUserAbsence→wakeFromUserAbsence 赖床)。
// 2) 锁屏(不睡眠的场景):OpenInputDesktop 探测——锁屏时输入桌面切到 winlogon,
//    普通进程打不开 ⇒ 判定已锁。锁 → emit sleep;解锁 → emit wake。
//    没有它,锁屏走人机器不睡时鸟会整天空转(60fps+IPC 轮询),纯耗电。

#[cfg(windows)]
pub fn setup_power(app: tauri::AppHandle) {
    use tauri::Emitter;
    std::thread::spawn(move || {
        use windows::Win32::System::SystemInformation::GetTickCount64;
        use windows::Win32::System::StationsAndDesktops::{OpenInputDesktop, CloseDesktop, DESKTOP_READOBJECTS, DESKTOP_CONTROL_FLAGS};
        let mut last_tick = unsafe { GetTickCount64() };
        let mut locked = false;
        loop {
            std::thread::sleep(std::time::Duration::from_secs(2));

            // --- 真睡眠唤醒(时钟跳变) ---
            let now = unsafe { GetTickCount64() };
            let gap = now - last_tick;
            last_tick = now;
            if gap > 15_000 {
                let _ = app.emit("sleep", ());
                let _ = app.emit("wake", ());
                continue;
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
                let _ = app.emit("sleep", ());
            } else if !is_locked && locked {
                locked = false;
                let _ = app.emit("wake", ());
            }
        }
    });
}

#[cfg(not(windows))]
pub fn setup_power(_app: tauri::AppHandle) {
    // mac:用原生 Swift 版,Tauri mac 端不需要
}
