// 睡眠/唤醒监听 stub。mac(NSWorkspace willSleep/didWake,Rust objc)和 Win32(WM_POWERBROADCAST)
// 都是平台特定、unsafe/objc,后续在 Windows CI 真机完善:监听到 → emit("sleep"/"wake")。
// 这里留 stub,前端 behavior 已有 sleepForUserAbsence/wakeFromUserAbsence 接收。

pub fn setup_power() {
    // TODO: 平台监听 → app.emit("sleep" / "wake")
}
