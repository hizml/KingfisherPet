// 裂纹:独立全屏透明窗(WebviewWindow "crack"),裂纹画屏幕坐标,不跟鸟窗走。
// 主窗 emit("crack-at", {x,y}) → crack 窗 canvas 画放射裂。对应 macOS CrackController(独立覆盖层)。

import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { availableMonitors } from "@tauri-apps/api/window";
import { emit, listen } from "@tauri-apps/api/event";
import { warnOnce } from "./log";

let win: WebviewWindow | null = null;
let ready: Promise<void> | null = null;
async function ensure() {
  if (!ready) {
    const attempt = (async () => {
      // 主窗 location.reload()(切主题)后模块重置,但 poop 窗是 app 级、不会被销毁
      // → 同 label 再 new 会 reject,ready 永远失败(切主题后特效/屎全废)。先查再建。
      const existing = await WebviewWindow.getByLabel("crack");
      // 虚拟桌面 bounding box(多屏覆盖;不再单屏 0,0)。⚠️ availableMonitors 是模块函数
      const mons = (await availableMonitors().catch(() => [])) as any[];
      const sc0 = mons[0]?.scaleFactor ?? 1;
      let ox = 0, oy = 0, rw = 1920, rh = 1080;
      if (mons.length) {
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
        for (const m of mons) {
          x0 = Math.min(x0, m.position.x); y0 = Math.min(y0, m.position.y);
          x1 = Math.max(x1, m.position.x + m.size.width); y1 = Math.max(y1, m.position.y + m.size.height);
        }
        ox = x0 / sc0; oy = y0 / sc0; rw = (x1 - x0) / sc0; rh = (y1 - y0) / sc0;
      }
      const w0 = existing ?? new WebviewWindow("crack", {
        url: "crack.html",
        transparent: true, decorations: false, alwaysOnTop: true,
        resizable: false, skipTaskbar: true, focus: false,
        width: Math.ceil(rw), height: Math.ceil(rh),
        x: Math.round(ox), y: Math.round(oy),
      });
      win = w0;
      // 告诉子窗舞台原点:body 平移回 (0,0) 语义,事件里的全局逻辑坐标直接可用
      const emitOrigin = async () => {
        try { await emit("stage-origin", { x: ox, y: oy }); } catch { /* */ }
      };
      await emitOrigin();
      if (!existing) {
        // 创建事件 5s 超时:别让挂死的创建把 ensure 永久吊住
        await Promise.race([
          w0.once("tauri://created", () => {}),
          new Promise<void>((_, rej) => setTimeout(() => rej(new Error("crack stage create timeout")), 5000)),
        ]);
        await w0.setIgnoreCursorEvents(true).catch(e => warnOnce("crack ignore", e));   // 穿透,别挡屏幕
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
    attempt.catch((e: any) => { warnOnce("crack stage", e); ready = null; });   // 失败留痕 + 可重试
    ready = attempt;
  }
  await ready;
}

export function setupCrack() { ensure().catch(e => warnOnce("crack setup", e)); }

export async function crackAt(x: number, y: number) {
  await ensure();
  await emit("crack-at", { x, y });
}

export async function clearCracks() {
  await ensure();
  await emit("crack-clear", null);
}
