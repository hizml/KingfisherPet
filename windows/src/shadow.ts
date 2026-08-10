// 地面阴影:shadow.png,窗内 local(鸟脚下),跟鸟窗走。简化版(固定 opacity;随高度变淡 Phase 4)。

import type { SpriteLibrary } from "./sprite";
import { getCurrentWindow } from "@tauri-apps/api/window";

let shadowEl: HTMLImageElement;

export function setupShadow(lib: SpriteLibrary) {
  shadowEl = document.createElement("img");
  shadowEl.src = `${import.meta.env.BASE_URL}Sprites/${lib.theme}/shadow.png`;
  Object.assign(shadowEl.style, {
    position: "absolute", bottom: "-6px", left: "5px", width: "150px", height: "40px",
    opacity: "0.45", pointerEvents: "none",
  });
  document.body.appendChild(shadowEl);
}

/// 鸟飞越高 → 阴影越淡(对应 macOS ShadowController 随高度变淡)
export async function updateShadow(_birdX: number, birdY: number) {
  if (!shadowEl) return;
  try {
    const m = await getCurrentWindow().currentMonitor();
    const screenH = m?.size.height ?? 800;
    const heightAbove = Math.max(0, screenH - birdY - 160);   // 鸟底距屏底
    shadowEl.style.opacity = String(Math.max(0.16, 0.85 * (1 - heightAbove / 700)));
  } catch (e) { /* */ }
}
