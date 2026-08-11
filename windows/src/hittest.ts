// 逐像素点击穿透:mousemove 查当前帧像素 alpha,透明 → setIgnoreCursorEvents(true) 穿透,实体 → false 接收。
// 对应 macOS PetView.hitTest。Tauri forward=ignore(穿透时转发 mousemove 供判断)。
import { getCurrentWindow } from "@tauri-apps/api/window";
import type { SpriteLibrary } from "./sprite";

const petWin = getCurrentWindow();
let ignoring = false;

async function setIgnore(b: boolean) {
  if (b === ignoring) return;
  ignoring = b;
  try { await petWin.setIgnoreCursorEvents(b, b); }     // forward=ignore
  catch { try { await petWin.setIgnoreCursorEvents(b); } catch { /* */ } }
}

export function setupHitTest(lib: SpriteLibrary, getCurrentFrame: () => string, size = 160) {
  setIgnore(true);
  document.addEventListener("mousemove", (e) => {
    const alpha = lib.alphaAt(getCurrentFrame(), e.offsetX / size, e.offsetY / size);
    setIgnore(alpha < 16);   // 透明区穿透,实体区接收
  });
}
