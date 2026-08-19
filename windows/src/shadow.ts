// 地面阴影:锚定任务栏顶、鸟正下方(macOS ShadowController 语义)。渲染在 poop 全屏舞台窗。
// 性能:monitor(地面)缓存 1s;emit 节流 ~20fps——之前每帧(60fps)一次 currentMonitor IPC
// + 广播 emit,走/飞全程 ~120 IPC/s 纯浪费。
import { getCurrentWindow } from "@tauri-apps/api/window";
import type { Window as TauriWindow } from "@tauri-apps/api/window";
import { emit } from "@tauri-apps/api/event";
import { ensurePoopStage } from "./poop";

const win: TauriWindow = getCurrentWindow();
let theme = localStorage.getItem("kf_theme") || "flat";

export function setupShadow(_lib: unknown) { }
export function setShadowTheme(t: string) { theme = t; }

let groundCache = -1, groundAt = 0;
async function groundY(): Promise<number> {
  if (groundCache >= 0 && performance.now() - groundAt < 1000) return groundCache;
  try {
    const m = await (win as any).currentMonitor();
    if (m) {
      const sc = m.scaleFactor ?? 1;
      groundCache = (m.position.y + m.size.height) / sc - 70 / sc;
      groundAt = performance.now();
    }
  } catch { /* */ }
  return groundCache < 0 ? 800 : groundCache;
}

let lastEmit = 0;
export async function updateShadow(birdX: number, birdY: number) {
  const now = performance.now();
  if (now - lastEmit < 50) return;   // 20fps 足够(阴影是渐变量)
  lastEmit = now;
  try {
    await ensurePoopStage();
    const ground = await groundY();
    const sc = await win.scaleFactor();
    const midY = birdY + 80 * sc;   // 鸟身中心(物理)
    const heightAbove = Math.max(0, ground - midY);
    const w = (150 + Math.min(heightAbove * 0.12, 70 * sc)) / sc;   // 尺寸随 sc 缩放保持视觉一致
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
