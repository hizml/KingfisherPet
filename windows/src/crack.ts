// 裂纹:独立全屏透明窗(WebviewWindow "crack"),裂纹画屏幕坐标,不跟鸟窗走。
// 主窗 emit("crack-at", {x,y}) → crack 窗 canvas 画放射裂。对应 macOS CrackController(独立覆盖层)。

import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { emit } from "@tauri-apps/api/event";

let win: WebviewWindow | null = null;
async function ensure() {
  if (!win) {
    win = new WebviewWindow("crack", {
      url: "crack.html",
      transparent: true, decorations: false, alwaysOnTop: true,
      resizable: false, skipTaskbar: true, focus: false,
      width: 3000, height: 2000, x: 0, y: 0,
    });
    await win.once("tauri://created").catch(() => {});
    await win.setIgnoreCursorEvents(true).catch(() => {});   // 点击穿透,别挡屏幕内容区
  }
}

export function setupCrack() { ensure().catch(() => {}); }

export async function crackAt(x: number, y: number) {
  await ensure();
  await emit("crack-at", { x, y });
}

export async function clearCracks() {
  await ensure();
  await emit("crack-clear", null);
}
