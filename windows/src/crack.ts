// 裂纹:独立全屏透明窗(WebviewWindow "crack"),裂纹画屏幕坐标,不跟鸟窗走。
// 主窗 emit("crack-at", {x,y}) → crack 窗 canvas 画放射裂。对应 macOS CrackController(独立覆盖层)。

import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { emit, listen } from "@tauri-apps/api/event";

let win: WebviewWindow | null = null;
let ready: Promise<void> | null = null;
async function ensure() {
  if (!ready) {
    ready = (async () => {
      // 主窗 location.reload()(切主题)后模块重置,但 poop 窗是 app 级、不会被销毁
      // → 同 label 再 new 会 reject,ready 永远失败(切主题后特效/屎全废)。先查再建。
      const existing = await WebviewWindow.getByLabel("crack");
      // 按主显示器逻辑尺寸建(固定 3000x2000 会分配超屏表面,150% 缩放下 ≈54MB/层)
      const mon = await (getCurrentWindow() as any).currentMonitor().catch(() => null);
      const sc0 = mon?.scaleFactor ?? 1;
      const w0 = existing ?? new WebviewWindow("crack", {
        url: "crack.html",
        transparent: true, decorations: false, alwaysOnTop: true,
        resizable: false, skipTaskbar: true, focus: false,
        width: Math.ceil((mon?.size.width ?? 1920) / sc0),
        height: Math.ceil((mon?.size.height ?? 1080) / sc0),
        x: 0, y: 0,
      });
      win = w0;
      if (!existing) {
        await w0.once("tauri://created", () => {});
        await w0.setIgnoreCursorEvents(true).catch(() => {});   // 穿透,别挡屏幕
      }
      // 等 child 页注册完 listener(否则首次 emit 子窗还没监听,事件丢失)。
      // reload 后子窗 listener 已在,此握手立即满足/超时放行,均安全。
      await Promise.race([
        new Promise<void>(res => {
          const un = listen("child-ready", (e) => {
            if (e.payload === "crack") { un.then(f => f()); res(); }
          });
        }),
        new Promise<void>(res => setTimeout(res, 2000)),
      ]);
    })();
  }
  await ready;
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
