// 设置:活跃度 / 动画速度 / 声音。localStorage 持久化。对应 macOS Settings 单例。
// 设置 UI 面板后续做;先持久化 + behavior/audio 读取生效。

/// localStorage 数值读取 + 防护:NaN/越界直接回默认(macOS Settings 有 clamp 同款;
/// 脏数据会让 NaN 传染 think 的随机区间 → 行为链静默瘫痪)
function num(key: string, def: number, lo: number, hi: number): number {
  const n = Number(localStorage.getItem(key));
  return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : def;
}

export const settings = {
  activity: num("kf_activity", 0.5, 0, 1),   // 0..1
  speed: num("kf_speed", 1, 0.5, 1.5),       // 0.5..1.5
  soundOn: localStorage.getItem("kf_sound") !== "0",
  peckScreen: localStorage.getItem("kf_peck") !== "0",   // 自发啄屏幕(关掉免频繁修复屏幕)
  // 天气联动(v1.5.0;默认关 = 明示纪律:开启才发首个网络请求)
  weatherEnabled: localStorage.getItem("kf_weather_on") === "1",
  weatherCity: localStorage.getItem("kf_weather_city") || "",
  weatherProvider: localStorage.getItem("kf_weather_provider") === "qweather" ? "qweather" : "open-meteo",
  weatherKey: localStorage.getItem("kf_weather_key") || "",
  weatherHost: localStorage.getItem("kf_weather_host") || "devapi.qweather.com",
};

export function setActivity(v: number) { settings.activity = v; localStorage.setItem("kf_activity", String(v)); }
export function setSpeed(v: number) { settings.speed = v; localStorage.setItem("kf_speed", String(v)); }
export function setSound(on: boolean) { settings.soundOn = on; localStorage.setItem("kf_sound", on ? "1" : "0"); }
export function setPeckScreen(on: boolean) { settings.peckScreen = on; localStorage.setItem("kf_peck", on ? "1" : "0"); }
export function setWeatherEnabled(on: boolean) { settings.weatherEnabled = on; localStorage.setItem("kf_weather_on", on ? "1" : "0"); }
export function setWeatherCity(v: string) { settings.weatherCity = v; localStorage.setItem("kf_weather_city", v); }
export function setWeatherProvider(v: string) { settings.weatherProvider = v === "qweather" ? "qweather" : "open-meteo"; localStorage.setItem("kf_weather_provider", settings.weatherProvider); }
export function setWeatherKey(v: string) { settings.weatherKey = v; localStorage.setItem("kf_weather_key", v); }
export function setWeatherHost(v: string) { settings.weatherHost = v; localStorage.setItem("kf_weather_host", v); }
