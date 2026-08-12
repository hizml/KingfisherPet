// Windows 睡眠/锁屏监听 stub。
// Win32 PowerRegisterSuspendResumeNotification 的 callback API 类型复杂(unsafe + windows crate 版本 types),mac dev 无法验证 Win32 编译(CI 才报)。behavior 睡眠/赖床逻辑全在(sleepForUserAbsence/wakeFromUserAbsence),等 emit("sleep"/"wake")接上即生效。后续在 Windows 机器完善 callback 注册,或改简化轮询。

#[cfg(windows)]
pub fn setup_power(_app: tauri::AppHandle) {
    // TODO(Windows): PowerRegisterSuspendResumeNotification callback 注册 → emit sleep/wake
}

#[cfg(not(windows))]
pub fn setup_power(_app: tauri::AppHandle) {
    // mac:用原生 Swift 版,Tauri mac 端不需要
}
