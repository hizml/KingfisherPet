// 地面阴影:锚定任务栏顶、鸟正下方(macOS ShadowController 语义)。
// 之前画在鸟窗内贴脚跟着飞——语义错(阴影应留地面)。现在渲染在 poop 全屏舞台窗。
// 鸟飞越高 → 阴影越大越淡。

import { getCurrentWindow } from "@tauri-apps/api/window";
import type { Window as TauriWindow } from "@tauri-apps/api/window";
import { emit } from "@tauri-apps/api/event";
import { ensurePoopStage } from "./poop";

const win: TauriWindow = getCurrentWindow();
let theme = localStorage.getItem("kf_theme") || "flat";

export function setupShadow(_lib: unknown) {   // 主题从 localStorage 读(切主题 reload)
  // 窗内不再画阴影;舞台窗按事件渲染
}

export function setShadowTheme(t: string) { theme = t; }

/// 鸟移动时调(逻辑坐标)。算地面阴影参数并推给舞台窗。
export async function updateShadow(birdX: number, birdY: number) {
  try {
    await ensurePoopStage();
    const m = await (win as any).currentMonitor();
    if (!m) return;
    const sc = m.scaleFactor ?? 1;
    // 地面 = 显示器底 - 任务栏(70 物理);全部逻辑
    const ground = (m.position.y + m.size.height) / sc - 70 / sc;
    const midY = birdY + 80;   // 鸟身中心(窗口 160 逻辑)
    const heightAbove = Math.max(0, ground - midY);
    const w = 150 + Math.min(heightAbove * 0.12, 70);
    const h = 40 + Math.min(heightAbove * 0.02, 16);
    const opacity = Math.max(0.16, 0.85 * (1 - heightAbove / 700));
    await emit("shadow", { show: true, x: birdX + 80, y: ground, w, h, opacity, theme });
  } catch { /* */ }
}

/// 隐藏阴影(鸟隐藏时)
export async function hideShadow() {
  try {
    await ensurePoopStage();
    await emit("shadow", { show: false });
  } catch { /* */ }
}
