// 屎:独立全屏透明窗(WebviewWindow "poop"),物理下落(屏幕坐标,不跟鸟窗)。
// 对应 macOS PoopController(独立窗 + 物理)。避免 macOS 踩过的「屎跟窗走」坑。
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { emit, listen } from "@tauri-apps/api/event";

let win: WebviewWindow | null = null;
let ready: Promise<void> | null = null;
async function ensure() {
  if (!ready) {
    ready = (async () => {
      win = new WebviewWindow("poop", {
        url: "poop.html",
        transparent: true, decorations: false, alwaysOnTop: true,
        resizable: false, skipTaskbar: true, focus: false,
        width: 3000, height: 2000, x: 0, y: 0,
      });
      await win.once("tauri://created", () => {});
      await win.setIgnoreCursorEvents(true).catch(() => {});   // 穿透,别挡屏幕
      // 等 child 页注册完 listener 再返回(否则首次 emit 子窗还没监听,事件丢失)
      await Promise.race([
        new Promise<void>(res => {
          const un = listen("child-ready", (e) => {
            if (e.payload === "poop") { un.then(f => f()); res(); }
          });
        }),
        new Promise<void>(res => setTimeout(res, 2000)),   // 超时兜底(挂了也放行)
      ]);
    })();
  }
  await ready;
}

export function setupPoop() { ensure().catch(() => {}); }

/// 特效舞台也用这个全屏窗(effects.ts 调):确保 ready 后返回
export function ensurePoopStage() { return ensure(); }

export async function dropPoop(x: number, y: number) {
  await ensure();
  await emit("poop-drop", { x, y });
}
