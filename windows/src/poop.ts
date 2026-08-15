// 屎:独立全屏透明窗(WebviewWindow "poop"),物理下落(屏幕坐标,不跟鸟窗)。
// 对应 macOS PoopController(独立窗 + 物理)。避免 macOS 踩过的「屎跟窗走」坑。
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { emit, listen } from "@tauri-apps/api/event";

let win: WebviewWindow | null = null;
let ready: Promise<void> | null = null;
async function ensure() {
  if (!ready) {
    ready = (async () => {
      // 主窗 location.reload()(切主题)后模块重置,但 poop 窗是 app 级、不会被销毁
      // → 同 label 再 new 会 reject,ready 永远失败(切主题后特效/屎全废)。先查再建。
      const existing = await WebviewWindow.getByLabel("poop");
      const w0 = existing ?? new WebviewWindow("poop", {
        url: "poop.html",
        transparent: true, decorations: false, alwaysOnTop: true,
        resizable: false, skipTaskbar: true, focus: false,
        width: 3000, height: 2000, x: 0, y: 0,
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
            if (e.payload === "poop") { un.then(f => f()); res(); }
          });
        }),
        new Promise<void>(res => setTimeout(res, 2000)),
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
