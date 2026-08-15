// 特效:水花/音符/zzz/太阳。渲染在 poop 全屏窗(屏幕坐标,不受鸟窗 160px 裁剪)。
// 对应 macOS Effects.swift(短命透明窗口,可超屏)。此处 emit 事件 → poop.html 画。
// x/y 传鸟窗本地坐标,这里转屏幕物理坐标发出去。

import { getCurrentWindow } from "@tauri-apps/api/window";
import { emit } from "@tauri-apps/api/event";
import { ensurePoopStage } from "./poop";

const petWin = getCurrentWindow();

async function fx(kind: string, x: number, y: number, dur = 0) {
  try {
    await ensurePoopStage();   // 特效舞台 = 屎全屏窗(已建好,幂等)
    const p = await petWin.outerPosition();   // 物理像素
    await emit("fx", { kind, x: p.x + x, y: p.y + y, dur });
  } catch { /* */ }
}

/// 水花(俯冲捕鱼入水)
export function splash(x: number, y: number) { fx("splash", x, y); }
/// 音符(鸣唱)
export function notes(x: number, y: number) { fx("notes", x, y); }
/// zzz(打盹)
export function zzz(x: number, y: number) { fx("zzz", x, y); }
/// 太阳(日光浴),duration 秒
export function sun(x: number, y: number, duration: number) { fx("sun", x, y, duration); }
