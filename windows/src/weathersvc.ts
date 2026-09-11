// 天气联动服务(v1.5.0 B;macOS WeatherService.swift 对称实现):
// 双 provider(Open-Meteo 默认免 key / 和风 Key+专属 Host 含预警)→ 归一化 11 档
// → 30 分钟刷新 → 通知 behavior。纪律:默认关,开启才发首个请求;失败/断网/key
// 无效一律静默降级 = 无系数,不弹窗不重试轰炸,状态只标设置窗/托盘(状态可见)。
// 纯映射在 weather.mjs(tests/weather.test.mjs 直打同一份源码)。

import { emit } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { settings } from "./settings";
import { mainFromOpenMeteo, mainFromQWeather, tempFlags, weatherFactors } from "./weather.mjs";

export type WeatherMain =
  | "sunny" | "overcast" | "rainLight" | "rainHeavy" | "thunder"
  | "snowLight" | "snowHeavy" | "fog" | "wind";

export interface WeatherNow { main: WeatherMain; hot: boolean; cold: boolean; tempC: number | null; raw: string }
export interface WeatherAlert { id: string; type: string; level: string }

export const weather = {
  now: null as WeatherNow | null,
  alerts: [] as WeatherAlert[],
  status: "off" as "off" | "ok" | "unavailable",
  alertActive(): boolean { return weather.alerts.length > 0; },
  /// 当前行为权重系数(null = 无系数)
  factors(): object | null {
    if (!weather.now) return null;
    const f = weatherFactors(weather.now.main, weather.now.hot, weather.now.cold);
    if (weather.alertActive()) f.overall *= 0.3;   // 预警生效:整体低活跃直至解除
    return f;
  },
};

type UpdateCb = () => void;
const cbs = new Set<UpdateCb>();
export function onWeatherUpdate(cb: UpdateCb) { cbs.add(cb); return () => cbs.delete(cb); }
function notify() { for (const cb of cbs) cb(); }

let timer: ReturnType<typeof setInterval> | null = null;
let refreshing = false;

export function startWeather() {
  stopWeather();
  weather.status = "ok";
  refresh();   // 开启即发首个请求
  timer = setInterval(refresh, 30 * 60 * 1000);
  emit("log", `weather: 启动(源=${settings.weatherProvider} 城市=${settings.weatherCity || "IP定位"})`);
}

export function stopWeather() {
  if (timer) { clearInterval(timer); timer = null; }
  const had = weather.now != null || weather.alerts.length > 0 || weather.status !== "off";
  weather.now = null;
  weather.alerts = [];
  weather.status = "off";
  syncTray();
  if (had) { emit("log", "weather: 停止,行为系数清零"); notify(); }
}

/// 设置变化 → 开着就重启(换源/城市/key 即刷),关就停
export function weatherSettingsChanged() {
  if (settings.weatherEnabled) startWeather();
  else stopWeather();
}

function fail(why: string) {
  weather.now = null;
  weather.alerts = [];
  weather.status = "unavailable";
  syncTray();
  emit("log", "weather: 降级(" + why + ")");
  notify();
}

function succeed(now: WeatherNow, alerts: WeatherAlert[]) {
  weather.now = now;
  weather.alerts = alerts;
  weather.status = "ok";
  syncTray();
  emit("log", `weather: ok ${now.raw} 预警=${alerts.length}`);
  notify();
}

async function refresh() {
  if (refreshing) return;   // 上一次还没回来(唤醒补发/手改设置连触):不叠加
  refreshing = true;
  try {
    if (settings.weatherProvider === "qweather") await refreshQWeather();
    else await refreshOpenMeteo();
  } catch (e) {
    fail(String(e));
  } finally {
    refreshing = false;
  }
}

// ── Open-Meteo(默认源,免 key)──
async function refreshOpenMeteo() {
  const { lat, lon } = await locate();
  const u = `https://api.open-meteo.com/v1/forecast?latitude=${lat.toFixed(4)}&longitude=${lon.toFixed(4)}` +
            `&current=weather_code,temperature_2m,wind_speed_10m&timezone=auto`;
  const cur = (await jget(u))?.current as Record<string, unknown> | undefined;
  const code = cur?.weather_code;
  if (typeof code !== "number") { fail("open-meteo 响应缺 weather_code"); return; }
  const temp = typeof cur?.temperature_2m === "number" ? cur.temperature_2m as number : null;
  const wind = typeof cur?.wind_speed_10m === "number" ? cur.wind_speed_10m as number : 0;
  const main = mainFromOpenMeteo(code, wind);
  if (!main) { fail("open-meteo 未知码 " + code); return; }
  const tf = tempFlags(temp);
  succeed({ main: main as WeatherMain, hot: tf.hot, cold: tf.cold, tempC: temp,
            raw: `OM#${code} v${Math.round(wind)}m/s t${temp == null ? "?" : Math.round(temp)}°` },
          []);   // Open-Meteo 无预警数据
}

// ── 和风(专属口子:Key + Host,含预警)──
function qwHost(): string {
  const h = (settings.weatherHost || "").trim();
  return h ? h : "devapi.qweather.com";   // 以控制台分配的专属 Host 为准
}

async function refreshQWeather() {
  const key = (settings.weatherKey || "").trim();
  if (!key) { fail("和风未填 Key"); return; }
  const host = qwHost();
  const { lat, lon } = await locate();
  const loc = `${lon.toFixed(2)},${lat.toFixed(2)}`;   // 和风 location = 经,纬
  const wobj = await jget(`https://${host}/v7/weather/now?location=${encodeURIComponent(loc)}&key=${encodeURIComponent(key)}`);
  if (wobj?.code !== "200") { fail("和风天气不可用(code/key)"); return; }
  const n = (wobj.now ?? {}) as Record<string, unknown>;
  const code = parseInt(String(n.code ?? ""), 10);
  if (!Number.isInteger(code)) { fail("和风响应缺 code"); return; }
  const temp = Number(n.temp);
  const windScale = parseInt(String(n.windScale ?? "0"), 10) || 0;
  const main = mainFromQWeather(code, windScale);
  if (!main) { fail("和风未知码 " + code); return; }
  const tf = tempFlags(Number.isFinite(temp) ? temp : null);
  // 预警同一周期同查(和风口子专属福利);预警失败不拖垮天气本身
  let alerts: WeatherAlert[] = [];
  try {
    const aobj = await jget(`https://${host}/v7/warning/now?location=${encodeURIComponent(loc)}&key=${encodeURIComponent(key)}`);
    if (aobj?.code === "200" && Array.isArray(aobj.warning)) {
      alerts = (aobj.warning as Array<Record<string, unknown>>)
        .filter((w) => typeof w.id === "string")
        .map((w) => ({
          id: w.id as string,
          type: typeof w.typeName === "string" ? w.typeName : "",
          level: typeof w.level === "string" ? w.level : "",
        }));
    }
  } catch { /* 预警查不到就当没有 */ }
  succeed({ main: main as WeatherMain, hot: tf.hot, cold: tf.cold, tempC: Number.isFinite(temp) ? temp : null,
            raw: `QW#${code} wind${windScale} t${Number.isFinite(temp) ? Math.round(temp) : "?"}°` },
          alerts);
}

// ── 定位(城市 → 各源 geocoding;留空 → ipapi.co IP 粗定位)──
async function locate(): Promise<{ lat: number; lon: number }> {
  const city = (settings.weatherCity || "").trim();
  if (!city) {
    const ip = await jget("https://ipapi.co/json/");
    if (typeof ip?.latitude !== "number" || typeof ip?.longitude !== "number") {
      throw new Error("IP 定位失败(断网?)");
    }
    return { lat: ip.latitude, lon: ip.longitude };
  }
  if (settings.weatherProvider === "qweather") {
    const obj = await jget(`https://geoapi.qweather.com/v2/city/lookup?location=${encodeURIComponent(city)}&key=${encodeURIComponent((settings.weatherKey || "").trim())}`);
    const first = (obj?.location as Array<Record<string, unknown>> | undefined)?.[0];
    const lat = Number(first?.lat), lon = Number(first?.lon);
    if (obj?.code !== "200" || !Number.isFinite(lat) || !Number.isFinite(lon)) {
      throw new Error("和风城市查找失败(名字/Key)");
    }
    return { lat, lon };
  }
  const obj = await jget(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(city)}&count=1&language=zh&format=json`);
  const first = (obj?.results as Array<Record<string, unknown>> | undefined)?.[0];
  if (typeof first?.latitude !== "number" || typeof first?.longitude !== "number") {
    throw new Error("Open-Meteo 城市查找失败(名字?)");
  }
  return { lat: first.latitude, lon: first.longitude };
}

async function jget(url: string): Promise<Record<string, unknown> | null> {
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(15000) });
    if (!r.ok) { emit("log", "weather: HTTP " + r.status + " " + new URL(url).host); return null; }
    return await r.json();
  } catch (e) {
    emit("log", "weather: 请求失败 " + new URL(url).host + " " + String(e));
    return null;
  }
}

// ── 托盘菜单状态行(Rust 侧 set_weather_status;title null = 隐藏)──
const zhUI = () => (localStorage.getItem("kf_lang") || "system") === "zh"
  || ((localStorage.getItem("kf_lang") || "system") === "system"
      && (navigator.language || "en").toLowerCase().startsWith("zh"));
const EMOJI: Record<string, string> = { sunny: "☀️", overcast: "☁️", rainLight: "🌦", rainHeavy: "🌧",
  thunder: "⛈", snowLight: "🌨", snowHeavy: "❄️", fog: "🌫", wind: "💨" };
const ZH: Record<string, string> = { sunny: "晴", overcast: "阴", rainLight: "小雨", rainHeavy: "大雨",
  thunder: "雷暴", snowLight: "小雪", snowHeavy: "大雪", fog: "雾", wind: "大风" };
const EN: Record<string, string> = { sunny: "Sunny", overcast: "Overcast", rainLight: "Light rain",
  rainHeavy: "Heavy rain", thunder: "Thunderstorm", snowLight: "Light snow", snowHeavy: "Heavy snow",
  fog: "Fog", wind: "Windy" };
const alertRank = (lv: string) => /红/.test(lv) ? 5 : /橙/.test(lv) ? 4 : /黄/.test(lv) ? 3 : /蓝/.test(lv) ? 2 : /白/.test(lv) ? 1 : 0;

function syncTray() {
  let title: string | null = null;
  if (weather.status === "unavailable") {
    title = zhUI() ? "🌧 天气源不可用" : "🌧 Weather unavailable";
  } else if (weather.now) {
    const now = weather.now;
    const top = weather.alerts.slice().sort((a, b) => alertRank(b.level) - alertRank(a.level))[0];
    if (top) {
      const suffix = alertRank(top.level) > 0 ? top.level + "色预警" : top.level;
      title = zhUI() ? `⚠️ ${top.type}${suffix} · 鸟躲起来了` : `⚠️ ${top.type} ${suffix} · hiding`;
    } else {
      const zh = zhUI();
      title = `${EMOJI[now.main]} ${zh ? ZH[now.main] : EN[now.main]}` +
              (now.tempC != null ? ` · ${Math.round(now.tempC)}°` : "");
    }
  }
  invoke("set_weather_status", { title }).catch(() => {});
}
