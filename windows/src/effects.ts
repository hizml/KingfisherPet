// 特效:水花/音符/zzz/太阳。渲染在 poop 全屏窗(屏幕坐标,不受鸟窗 160px 裁剪)。
// 对应 macOS Effects.swift(短命透明窗口,可超屏)。此处 emit 事件 → poop.html 画。
// x/y 传鸟窗本地坐标,这里转屏幕物理坐标发出去。

import { getCurrentWindow } from "@tauri-apps/api/window";
import { emit } from "@tauri-apps/api/event";
import { ensurePoopStage } from "./poop";
import { settings } from "./settings";

const petWin = getCurrentWindow();

async function fx(kind: string, x: number, y: number, dur = 0) {
  try {
    await ensurePoopStage();   // 特效舞台 = 屎全屏窗(已建好,幂等)
    const p = await petWin.outerPosition();   // 窗口物理原点
    const sc = await petWin.scaleFactor();
    // 屏幕物理 = 窗口原点 + 本地逻辑偏移×sc(全链物理,接收侧舞台自会 /dpr)
    await emit("fx", { kind, x: p.x + x * sc, y: p.y + y * sc, dur, spd: settings.speed });
  } catch { /* */ }
}

/// 水花(俯冲捕鱼入水)
export function splash(x: number, y: number) { fx("splash", x, y); }
/// 音符(鸣唱)
export function notes(x: number, y: number) { fx("notes", x, y); }
/// zzz(打盹)
export function zzz(x: number, y: number) { fx("zzz", x, y); }
/// 醒来即收 zzz 气泡(macOS Effects.dismissZzz 同款):不留"睁眼+ZZZ"幽灵——
/// 此前睡醒回 idle 后最后一颗还要飘 ~2s,被看成"睁眼睡觉"
export function zzzClear() { try { void emit("fx", { kind: "zzz_clear" }); } catch { /* */ } }
/// 太阳(日光浴),duration 秒
export function sun(x: number, y: number, duration: number) { fx("sun", x, y, duration); }
/// 抖水水珠(雨停/预警解除,shake 序列配套)
export function droplets(x: number, y: number) { fx("droplets", x, y); }
/// 访客飞过(v1.5.x 成长):x/y=本鸟中心(屏幕物理);舞台侧算进出路径与对唱停留
export function visitorPass(x: number, y: number, onArrive: () => void) { fx2("visitor", x, y, onArrive); }
/// 蛋摇摆(孵化彩蛋):x/y=蛋位(屏幕物理)
export function eggWobble(x: number, y: number) { fx2("egg", x, y, null); }
/// 小鸟跟班绕飞(孵化彩蛋):x/y=本鸟中心(屏幕物理)
export function childFlight(x: number, y: number) { fx2("child", x, y, null); }
/// 屏幕物理坐标直发版(成长演出拿到的已是屏幕坐标,不再做本地→屏幕换算)
async function fx2(kind: string, px: number, py: number, cb: (() => void) | null) {
  try {
    await ensurePoopStage();
    await emit("fx", { kind, x: px, y: py, dur: 0, spd: settings.speed });
    if (cb) setTimeout(cb, 3400);   // 访客落定开唱的大致时刻(路径前段 42%×8s≈3.4s,Mac 同款参数)
  } catch { /* */ }
}
