// Windows 睡眠/锁屏监听 → emit "sleep"/"wake"(behavior 接收,鸟睡觉/赖床)。
// 对应 macOS AppDelegate 的 NSWorkspace willSleep/didWake(mac 用原生 Swift 版,不需 Tauri 做)。

#[cfg(windows)]
pub fn setup_power(app: tauri::AppHandle) {
    use std::sync::Arc;
    use windows::Win32::System::Power::{PowerRegisterSuspendResumeNotification, DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS, POWER_REGISTER_CALLBACK};
    use windows::Win32::Foundation::{HANDLE, PDEVICE_NOTIFY_SUBSCRIBE_PARAMETERS};
    use windows::core::PCWSTR;

    // 线程内持有 AppHandle,睡眠/唤醒回调 emit
    let app = Arc::new(app);

    // PowerRegisterSuspendResumeNotification 回调(unsafe)
    // callback 收到 PBT_APMSUSPEND("suspend")/ PBT_APMRESUME("resume")
    // 简化:用 PowerRegisterSuspendResumeNotification(Windows 8+ callback API)
    unsafe extern "system" fn power_callback(
        context: *const std::ffi::c_void,
        change_type: u32,
    ) -> u32 {
        // change_type: 0 = resume, 1 = suspend
        let app_ptr = context as *const Arc<tauri::AppHandle>;
        if app_ptr.is_null() {
            return 0;
        }
        let app = &*app_ptr;
        match change_type {
            0 => { let _ = app.emit("wake", ()); }    // 唤醒
            1 => { let _ = app.emit("sleep", ()); }   // 睡眠
            _ => {}
        }
        0
    }

    let ctx = Box::leak(Box::new(app.clone()));
    let params = DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS {
        Callback: POWER_REGISTER_CALLBACK(Some(power_callback)),
        Context: ctx as *const _ as *const std::ffi::c_void,
    };

    unsafe {
        let _handle = PowerRegisterSuspendResumeNotification(
            2, // DEVICE_NOTIFY_CALLBACK
            &params as *const _ as *const std::ffi::c_void,
            std::ptr::null_mut(),
        );
    }
}

#[cfg(not(windows))]
pub fn setup_power(_app: tauri::AppHandle) {
    // mac/linux:不需要(用户用原生 Swift 版;Tauri 只冲 Windows)
}
