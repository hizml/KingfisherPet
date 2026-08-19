// 地面阴影:锚定鸟所在显示器工作区顶(任务栏已真实扣除)、鸟正下方(macOS ShadowController 语义)。
// 渲染在 poop 全屏舞台窗。全物理:ground/midY/heightAbove 都是物理像素,
// 仅 w/h 换算成 CSS 逻辑(舞台对尺寸直用、对坐标 /DPR,契约见 poop.html)。
// 性能:ground 缓存 1s;emit 节流 ~20fps——之前每帧一次 currentMonitor IPC 纯浪费。
import { getCurrentWindow } from "@tauri-apps/api/window";
import type { Window as TauriWindow } from "@tauri-apps/api/window";
import { emit } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { ensurePoopStage } from "./poop";

const win: TauriWindow = getCurrentWindow();
let theme = localStorage.getItem("kf_theme") || "flat";

export function setupShadow(_lib: unknown) { }
export function setShadowTheme(t: string) { theme = t; }

/// 鸟所在显示器工作区底边(物理,任务栏任意边都已扣除)。
/// 之前用 currentMonitor 底边/sc − 70/sc 猜任务栏:逻辑物理混算 + 猜高度,
/// 高 DPI 下阴影悬空、任务栏不在底部时全错。
let groundCache = -1, groundAt = 0;
async function groundY(): Promise<number> {
  if (groundCache >= 0 && performance.now() - groundAt < 1000) return groundCache;
  try {
    const wa = await invoke<[number, number, number, number] | null>("work_area_cmd");
    if (wa) { groundCache = wa[1] + wa[3]; groundAt = performance.now(); }
  } catch { /* */ }
  return groundCache < 0 ? 1040 : groundCache;
}

let lastEmit = 0;
export async function updateShadow(birdX: number, birdY: number) {
  const now = performance.now();
  if (now - lastEmit < 50) return;   // 20fps 足够(阴影是渐变量)
  lastEmit = now;
  try {
    await ensurePoopStage();
    const ground = await groundY();   // 物理
    const sc = await win.scaleFactor();
    const midY = birdY + 80 * sc;   // 鸟身中心(物理)
    const heightAbove = Math.max(0, ground - midY);   // 物理
    const w = (150 + Math.min(heightAbove * 0.12, 70 * sc)) / sc;   // CSS 逻辑
    const h = (40 + Math.min(heightAbove * 0.02, 16 * sc)) / sc;
    const opacity = Math.max(0.16, 0.85 * (1 - heightAbove / (700 * sc)));
    await emit("shadow", { show: true, x: birdX + 80 * sc, y: ground, w, h, opacity, theme });
  } catch { /* */ }
}

export async function hideShadow() {
  try {
    await ensurePoopStage();
    await emit("shadow", { show: false });
  } catch { /* */ }
}
