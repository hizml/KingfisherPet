// 设置:活跃度 / 动画速度 / 声音。localStorage 持久化。对应 macOS Settings 单例。
// 设置 UI 面板后续做;先持久化 + behavior/audio 读取生效。

export const settings = {
  activity: Number(localStorage.getItem("kf_activity") ?? 0.5),   // 0..1
  speed: Number(localStorage.getItem("kf_speed") ?? 1),            // 0.5..1.5
  soundOn: localStorage.getItem("kf_sound") !== "0",
};

export function setActivity(v: number) { settings.activity = v; localStorage.setItem("kf_activity", String(v)); }
export function setSpeed(v: number) { settings.speed = v; localStorage.setItem("kf_speed", String(v)); }
export function setSound(on: boolean) { settings.soundOn = on; localStorage.setItem("kf_sound", on ? "1" : "0"); }
