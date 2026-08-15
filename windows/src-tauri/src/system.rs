// Windows 睡眠/唤醒检测:后台线程 2s 一跳 GetTickCount64。
// 系统睡眠时时钟停走 → 醒来后观测到"睡了远超 2s" → 判定经历了一次睡眠,
// 先 emit("sleep") 再 emit("wake")(前端 sleepForUserAbsence→wakeFromUserAbsence 赖床)。
// 比 PowerRegisterSuspendResumeNotification 的 unsafe callback 简单且稳(无类型坑),
// 代价是睡眠前的通知变成醒来后补发——进程挂起期间本来就做不了事,等效。

#[cfg(windows)]
pub fn setup_power(app: tauri::AppHandle) {
    use tauri::Emitter;   // app.emit 需要 trait 在作用域(mac cargo check 编不到这段,CI 才暴露)
    std::thread::spawn(move || {
        use windows::Win32::System::SystemInformation::GetTickCount64;
        let mut last = unsafe { GetTickCount64() };
        loop {
            std::thread::sleep(std::time::Duration::from_secs(2));
            let now = unsafe { GetTickCount64() };
            let gap = now - last;
            last = now;
            if gap > 15_000 {   // 预期 ~2000ms;>15s 说明机器刚从睡眠醒来
                let _ = app.emit("sleep", ());
                let _ = app.emit("wake", ());
            }
        }
    });
}

#[cfg(not(windows))]
pub fn setup_power(_app: tauri::AppHandle) {
    // mac:用原生 Swift 版,Tauri mac 端不需要
}
