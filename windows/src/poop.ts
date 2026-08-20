// 屎:独立全屏透明窗(WebviewWindow "poop"),物理下落(屏幕坐标,不跟鸟窗)。
// 对应 macOS PoopController(独立窗 + 物理)。避免 macOS 踩过的「屎跟窗走」坑。
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { availableMonitors } from "@tauri-apps/api/window";
import { emit, listen } from "@tauri-apps/api/event";
import { settings } from "./settings";
import { warnOnce } from "./log";

let win: WebviewWindow | null = null;
let ready: Promise<void> | null = null;
export let stageError: string | null = null;   // 创建失败原因(诊断用;之前静默吞掉 → 树枝/阴影/屎全没了也没人知道)
async function ensure() {
  if (!ready) {
    const attempt = (async () => {
      // 主窗 location.reload()(切主题)后模块重置,但 poop 窗是 app 级、不会被销毁
      // → 同 label 再 new 会 reject,ready 永远失败(切主题后特效/屎全废)。先查再建。
      const existing = await WebviewWindow.getByLabel("poop");
      // 虚拟桌面 bounding box(多屏;固定 3000x2000 会超屏面,单屏又盖不到副屏)
      // ⚠️ availableMonitors 是模块函数,不是 Window 方法(当方法调会 TypeError 被吞)
      const mons = await availableMonitors().catch(() => []);
      const mon = mons[0];
      const sc0 = mon?.scaleFactor ?? 1;
      let ox = 0, oy = 0, rw = 1920, rh = 1080;
      if (mons.length) {
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
        for (const m of mons) {
          x0 = Math.min(x0, m.position.x); y0 = Math.min(y0, m.position.y);
          x1 = Math.max(x1, m.position.x + m.size.width); y1 = Math.max(y1, m.position.y + m.size.height);
        }
        ox = x0 / sc0; oy = y0 / sc0; rw = (x1 - x0) / sc0; rh = (y1 - y0) / sc0;
      }
      const w0 = existing ?? new WebviewWindow("poop", {
        url: "poop.html",
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
        // 创建事件 5s 超时:别让挂死的创建把 ensure 永久吊住(失败要能重试)
        await Promise.race([
          w0.once("tauri://created", () => {}),
          new Promise<void>((_, rej) => setTimeout(() => rej(new Error("stage create timeout")), 5000)),
        ]);
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
    // 创建失败:记原因 + 复位允许下次重试(之前拒绝态被永久缓存,阴影/树枝/屎全哑)
    attempt.catch((e: any) => {
      stageError = String(e?.message ?? e);
      warnOnce("poop stage", e);
      ready = null;
    });
    ready = attempt;
  }
  await ready;
}

export function setupPoop() { ensure().catch((e: any) => { stageError = String(e?.message ?? e); }); }

/// 唤醒宽限:告诉舞台窗 3s 内屎不做承载判定(唤醒瞬间层级混乱)
export async function wakeGrace() {
  await ensure();
  await emit("poop-grace", null);
}

/// 特效舞台也用这个全屏窗(effects.ts 调):确保 ready 后返回
export function ensurePoopStage() { return ensure(); }

export async function dropPoop(x: number, y: number, landingY: number, fallSec: number,
                                hwnd: number | null = null, scale = 1) {
  await ensure();
  await emit("poop-drop", { x, y, landingY, fallSec, spd: settings.speed, hwnd, scale });
}
