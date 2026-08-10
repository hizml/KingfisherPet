// 屎:独立全屏透明窗(WebviewWindow "poop"),物理下落(屏幕坐标,不跟鸟窗)。
// 对应 macOS PoopController(独立窗 + 物理)。避免 macOS 踩过的「屎跟窗走」坑。
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { emit } from "@tauri-apps/api/event";

let win: WebviewWindow | null = null;
async function ensure() {
  if (!win) {
    win = new WebviewWindow("poop", {
      url: "poop.html",
      transparent: true, decorations: false, alwaysOnTop: true,
      resizable: false, skipTaskbar: true, focus: false,
      width: 3000, height: 2000, x: 0, y: 0,
    });
    await win.once("tauri://created").catch(() => {});
    await win.setIgnoreCursorEvents(true).catch(() => {});   // 穿透,别挡屏幕
  }
}

export function setupPoop() { ensure().catch(() => {}); }

export async function dropPoop(x: number, y: number) {
  await ensure();
  await emit("poop-drop", { x, y });
}
