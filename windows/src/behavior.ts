// 行为状态机 + 移动(走/飞)+ 代际取消。移植自 macOS Behavior.swift。
// 坐标约定(v1.4.12 起):屏幕坐标【全物理像素】——Win32/Rust 命令、area()、
// setOrigin(PhysicalPosition)、各舞台窗事件载荷全部物理;只有窗口内绘制用逻辑。
// 逻辑常量(SIZE/FEET_*)进物理世界必须乘 _scale(SIZE_P()/FEET_TOP_P()/FEET_BOT_P())。

import { getCurrentWindow, PhysicalPosition, availableMonitors } from "@tauri-apps/api/window";
import type { Window as TauriWindow } from "@tauri-apps/api/window";
import { emit } from "@tauri-apps/api/event";
import type { SpriteLibrary } from "./sprite";
import * as effects from "./effects";
import * as poop from "./poop";
import * as crack from "./crack";
import * as branch from "./branch";
import { hideShadow } from "./shadow";
import { invoke } from "@tauri-apps/api/core";
import { settings } from "./settings";
import { setSleepMuted } from "./audio";
import { warnOnce } from "./log";

/// 舞台窗显隐(失败留痕:舞台丢了=树枝/阴影/屎全灭,不能静默)
function stageVis(label: string, show: boolean) {
  invoke("stage_visibility", { label, show }).catch(e => warnOnce("stage_vis " + label + " " + show, e));
}

const win: TauriWindow = getCurrentWindow();
const SIZE = 160;      // 窗口逻辑宽高(sprite 内部逻辑像素)
const FEET_OFFSET = 26;                       // 脚距窗口底(逻辑)
const FEET_FROM_TOP = SIZE - FEET_OFFSET;    // 顶左原点:脚距窗口顶(逻辑)
/// 屏幕坐标全部【物理像素】(Win32 原生、Rust 命令一致);
/// 逻辑→物理换算的唯一出口,杜绝 LogicalPosition 按窗口 DPI 漂移的整类 bug:
const SIZE_P = () => SIZE * _scale;           // 窗口物理宽
const FEET_TOP_P = () => FEET_FROM_TOP * _scale;   // 窗口顶到脚(物理)
const FEET_BOT_P = () => FEET_OFFSET * _scale;     // 窗口底到脚(物理)

let lib: SpriteLibrary;
let setState: (s: string) => void;
let setFacing: (right: boolean) => void;
let playPeep: () => void;
let onMoved: (x: number, y: number) => void;

let gen = 0;
let busy = false;
let busySince: number | null = null;   // 本次动作开始时刻(看门狗卡死检测)
let thinkTimer: ReturnType<typeof setTimeout> | null = null;
let perchTimer: ReturnType<typeof setInterval> | null = null;   // 栖窗跟随轮询

const sp = (s: number) => s / settings.speed;   // 受全局动画速度影响

/// 当前显示器缩放(逻辑 = 物理 / scale)。
/// ⚠️ 必须用 Window.scaleFactor()——currentMonitor 在 @tauri-apps/api 里是
/// 模块级函数不是 Window 方法,当方法调会 TypeError 且被吞掉,
/// 导致 _scale 永远卡 1(200% 屏上窗口 320 物理宽按 160 算,全链错位的根因)。
let _scale = 1;
async function scale(): Promise<number> {
  try {
    const s = await win.scaleFactor();
    if (s && s > 0) { _scale = s; }
  } catch (e) { warnOnce("scale", e); }
  return _scale;
}

async function area(): Promise<{ minX: number; minY: number; maxX: number; maxY: number }> {
  // 物理像素。Rust 直查鸟所在显示器的工作区(MonitorFromWindow + rcWork):
  // 任务栏已真实扣除(任意边),不再猜 70px,DPI 无关
  try {
    await scale();   // 顺带刷新 _scale(供 SIZE_P 等用)
    const wa = await invoke<[number, number, number, number] | null>("work_area_cmd");
    if (wa) {
      const a = { minX: wa[0], minY: wa[1], maxX: wa[0] + wa[2], maxY: wa[1] + wa[3] };
      areaCached = { a, at: performance.now() };
      return a;
    }
  } catch (e) { emit("log", "area " + e); }
  return { minX: 0, minY: 0, maxX: 1920, maxY: 1040 };   // 兜底
}

/// 热路径用:area 结果 2s 缓存(工作区几乎不变),免去每跳 2 次 IPC——
/// 拖拽钳制要每帧检查,之前 area() 的 IPC 往返让快速拖拽钻进任务栏下面。
let areaCached: { a: { minX: number; minY: number; maxX: number; maxY: number }, at: number } | null = null;
async function areaFast() {
  if (areaCached && performance.now() - areaCached.at < 2000) return areaCached.a;
  return area();
}

async function getOrigin(): Promise<{ x: number; y: number }> {
  const p = await win.outerPosition();   // 物理像素,直用
  return { x: p.x, y: p.y };
}

async function setOrigin(x: number, y: number) {
  try {
    await win.setPosition(new PhysicalPosition(Math.round(x), Math.round(y)));   // 物理,免 DPI 漂移
    onMoved(x, y);
    // 位置记忆(节流 1s 存一次,防高频移动刷 localStorage)
    if (!savePosAt) savePosAt = setTimeout(() => {
      savePosAt = null;
      localStorage.setItem("kf_x", String(Math.round(x)));   // 物理
      localStorage.setItem("kf_y", String(Math.round(y)));
    }, 1000);
  } catch (e) { emit("log", "setOrigin err x=" + x + " y=" + y + ": " + e); }
}
let savePosAt: ReturnType<typeof setTimeout> | null = null;

function beginAction() {
  gen++;
  busy = true;
  busySince = performance.now();
  if (thinkTimer) { clearTimeout(thinkTimer); thinkTimer = null; }
  stopZzzInterval();   // 无条件停打盹 zzz(macOS 同款;之前只在 userSleeping 时停会泄漏)
  // 惊醒:赖床中被新动作打断要清睡眠标志,否则 userSleeping 永久卡 true
  if (userSleeping) { userSleeping = false; setSleepMuted(false); }
  // 注意:不无条件弃栖——静态动作(唱/守候/日光浴/拉屎)在窗口上做时保持栖窗跟随(macOS 同款);
  // 移动类动作自己调 leavePerchWin()
}
function leavePerchWin() { stopPerchCheck(); }
function stopPerchCheck() {
  if (perchTimer) { clearInterval(perchTimer); perchTimer = null; }
  perchedHwnd = null;
  perchMoving = false;   // 不清则 think 永久推迟(区间被杀后无人复位)
}
// 栖窗增量跟随:记住栖的 HWND + 上次矩形,20fps 查窗口位移增量应用到鸟
// (不往窗口中间凑、alt-tab 换前台不拽走鸟;窗口没了 → 飞走)。对应 macOS checkPerch。
let perchedHwnd: number | null = null;
let lastPerchRect: { x: number; y: number } | null = null;
let perchMoving = false, lastPerchMove = 0;
let occlBad = 0, occlTick = 0, detachStreak = 0, fastTicks = 0;   // 飞走条件计数(macOS checkPerch 同款 + 甩下)
function perchFlee(reason: string) {
  emit("log", "perch: 飞走(" + reason + ")");
  stopPerchCheck();
  startFly(300);
}
export function getPerchedHwnd(): number | null { return perchedHwnd; }   // 诊断用:当前栖的窗口
function startPerchCheck() {
  // ⚠️ 只清计时器,不碰 perchedHwnd——stopPerchCheck() 会把它置 null,
  // 之前先调 stop 再判空 = 永远直接返回,栖窗跟随从未启动过
  if (perchTimer) { clearInterval(perchTimer); perchTimer = null; }
  if (perchedHwnd == null) return;
  const hwnd = perchedHwnd;
  occlBad = 0; occlTick = 0; detachStreak = 0; fastTicks = 0;
  perchTimer = setInterval(async () => {
    try {
      const r = await invoke<[number, number, number, number] | null>("window_rect_cmd", { hwndVal: hwnd });
      if (!r) { perchFlee("窗口消失"); return; }   // 窗口没了 → 飞远
      const wx = r[0], wy = r[1];   // 物理直用
      if (!lastPerchRect) { lastPerchRect = { x: wx, y: wy }; return; }
      const dx = wx - lastPerchRect.x, dy = wy - lastPerchRect.y;
      // 剧烈晃动(≥25px/50ms 持续 ~0.4s)→ 被甩下(用户直觉;Mac 无此条)
      if (Math.abs(dx) + Math.abs(dy) > 25) { fastTicks++; if (fastTicks >= 8) { perchFlee("被甩下"); return; } }
      else fastTicks = 0;
      // 拖太高:鸟头要出屏 → 飞走(macOS detach 同款)
      const a = await areaFast();
      if (wy - FEET_TOP_P() < a.minY) { detachStreak++; if (detachStreak >= 3) { perchFlee("拖太高"); return; } }
      else detachStreak = 0;
      // 遮挡:每 10 跳(≈0.5s)查脚点最顶窗,连续 2 次不是栖窗 → 被盖住飞走(macOS occlusion 同款)
      if (++occlTick % 10 === 0) {
        const o0 = await getOrigin();
        const at = await invoke<number | null>("window_at_point_cmd", { x: o0.x + SIZE_P() / 2, y: o0.y + FEET_TOP_P() });
        if (at != null && at !== hwnd) { occlBad++; if (occlBad >= 2) { perchFlee("被盖住"); return; } }
        else occlBad = 0;
      }
      if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) {
        perchMoving = true; lastPerchMove = performance.now();   // 用户拖栖窗 → think 推迟(macOS 同款)
        const o = await getOrigin();
        // 跟随要钳制(macOS clampPerch 同款)——栖窗被拖向屏缘/别的显示器时,
        // 裸跟随会把鸟带出屏幕外(长跑"只见树枝不见鸟"的真凶之一)
        const cx = Math.min(Math.max(o.x + dx, a.minX), a.maxX - SIZE_P());
        const cy = Math.min(Math.max(o.y + dy, a.minY), a.maxY - FEET_TOP_P());
        await setOrigin(cx, cy);
        lastPerchRect = { x: wx, y: wy };
      } else if (perchMoving && performance.now() - lastPerchMove > 600) {
        perchMoving = false;   // 停 0.6s → 恢复思考
      }
    } catch (e) { /* */ }
  }, 50);
}

function enter(s: string) { setState(s); }
function finish() {
  busy = false; busySince = null; stopZzzInterval(); enter("idle"); scheduleThink();
  if (perchedHwnd != null && perchTimer == null) startPerchCheck();   // 静态动作后恢复栖窗跟随
}

function hold(t: number, done: () => void) {
  const g = gen;
  setTimeout(() => { if (gen === g) done(); }, sp(t) * 1000);
}

function scheduleThink() {
  if (thinkTimer) clearTimeout(thinkTimer);
  // 活跃度越高,思考间隔越短(对应 macOS Settings.activity)
  const a = settings.activity;
  const lo = 3.5 - 2 * a, hi = 7 - 3.5 * a;
  thinkTimer = setTimeout(think, (lo + Math.random() * (hi - lo)) * 1000);
}

let wakeGraceUntil = 0;   // 唤醒宽限:此刻前 think 推迟(系统正在恢复,别抢)
async function think() {
  if (busy || perchMoving || performance.now() < wakeGraceUntil) { scheduleThink(); return; }   // 栖窗被用户拖动中:推迟预设动作
  // 权重对齐 macOS think():idle/walk 带随活跃度伸缩(高活跃→少待机多走动),
  // 其余固定:fish 8 / fly 7 / sing 7 / dart 7 / watch 7 / sun 5 / peck 5 / poop 5 / perch 4
  const a = settings.activity;
  const idleBand = Math.round((1 - a) * 22);            // 0→22, 1→0
  const walkEnd = idleBand + Math.max(1, Math.round((1 - a) * 20));   // idle+walk 带
  const r = Math.random() * 100;   // 带宽是 0-100 的计数,不是 0-1 概率(之前忘乘,鸟只发呆)
  // 权重带逐项对齐 macOS think():fly 7 / fish 8 / sing 7 / dart 7 / watch 7 / sun 7 / peck 7 / perch 6 / poop 6
  if (r < idleBand) { enter("idle"); scheduleThink(); }
  else if (r < walkEnd) startWalk();
  else if (r < walkEnd + 7) startFly();
  else if (r < walkEnd + 15) startFish();
  else if (r < walkEnd + 22) startSing();
  else if (r < walkEnd + 29) startDart();
  else if (r < walkEnd + 36) startWatch();
  else if (r < walkEnd + 43) startSun();
  else if (r < walkEnd + 50) startPeck();
  else if (r < walkEnd + 56) startPerchWindow();
  else if (r < walkEnd + 62) startPoop();
  else startSleep();
}

// MARK: 走(线性)。门控:只在"地面"走——任务栏顶,或栖着的窗口上沿(macOS 同款);
// 空中/半空不走路,改飞。沿当前表面高度走,不瞬移 Y。
// 走完检查:栖窗行走时若走出窗口横向范围(脚悬空)→ 飞走(macOS"走到边就飞")。
async function startWalk() {
  const perched = perchedHwnd;   // 先记下
  beginAction();
  leavePerchWin();   // 走 = 自己移动,脱离栖窗跟随
  enter("walk");
  try {
    const a = await area();
    const o = await getOrigin();
    const onGround = o.y + FEET_TOP_P() >= a.maxY - 40 * _scale;      // 脚贴近任务栏顶
    if (!onGround && perched == null) { finish(); return; }   // 空中/半空 → 不走,回 idle(macOS 同款)
    const dir = Math.random() < 0.5 ? 1 : -1;
    const dist = 80 + Math.random() * 120;
    const tx = Math.min(Math.max(o.x + dir * dist, a.minX), a.maxX - SIZE_P());
    if (Math.abs(tx - o.x) < 20) { finish(); return; }
    setFacing(tx > o.x);
    animateMove({ x: tx, y: o.y }, Math.max(0.6, Math.abs(tx - o.x) / 70), async () => {
      // 走完:在窗口上走到边(脚不在窗口横向范围)→ 飞远
      if (perched != null && !(o.y + FEET_TOP_P() >= a.maxY - 40 * _scale)) {
        try {
          await scale();
          const r = await invoke<[number, number, number, number] | null>("window_rect_cmd", { hwndVal: perched });
          if (r) {
            const wx0 = r[0], wx1 = r[0] + r[2];
            const midX = tx + SIZE_P() / 2;
            // 还在窗口横向范围内 → 走完恢复栖窗跟随(macOS afterWalk)
            if (midX >= wx0 - 10 && midX <= wx1 + 10) {
              perchedHwnd = perched; lastPerchRect = null; startPerchCheck();
              finish(); return;
            }
            if (midX < wx0 - 10 || midX > wx1 + 10) {
              if (Math.random() < 0.5) { perchedHwnd = perched; lastPerchRect = null; startPerchCheck(); finish(); }   // 50% 换个窗口
              else { startFly(300); }   // 否则飞远
              return;
            }
          }
        } catch { /* 查不到就正常留下 */ }
      }
      finish();
    });
  } catch (e) { console.error("walk", e); finish(); }
}

// MARK: 飞(三次贝塞尔)。minDist:目标离当前位置的最小距离(被赶走时飞远)
async function startFly(minDist = 0) {
  beginAction();
  leavePerchWin();
  enter("fly");
  try {
    const a = await area();
    const o = await getOrigin();
    let tx = o.x, ty = o.y;
    for (let i = 0; i < 8; i++) {   // 重选直到够远(或用完次数)
      tx = a.minX + Math.random() * (a.maxX - a.minX - SIZE_P());
      ty = Math.random() < 0.5 ? (a.maxY - FEET_TOP_P()) : a.minY;
      if (Math.hypot(tx - o.x, ty - o.y) >= minDist) break;
    }
    setFacing(tx > o.x);
    branch.hideBranch();   // 起飞 → 先收当前树枝
    // 落点悬空(脚高于任务栏区)→ 树枝先到(屏幕坐标预显,对应 macOS perchBranchIfNeeded)
    const feetY = ty + FEET_TOP_P();
    if (feetY < a.maxY - 40 * _scale) branch.showBranchAt(tx + SIZE_P() / 2, feetY);
    // 35% 空中拉屎(macOS 同款):飞行途中从屁股掉一坨
    if (Math.random() < 0.35) {
      const g = gen, ax = o.x + 80 + (tx > o.x ? -50 : 50);
      setTimeout(() => { if (gen === g) dropPoopAt(ax, o.y + (SIZE - 40) * _scale); }, sp(0.3 + Math.random() * 0.4) * 1000);
    }
    animateFlight({ x: tx, y: ty }, 1.3, () => {
      if (feetY >= a.maxY - 40 * _scale) branch.hideBranch();   // 落地(任务栏)→ 确保无枝
      finish();
    });
  } catch (e) { console.error("fly", e); finish(); }
}

// MARK: 静态动作
let facingRight = false;   // 朝向(effects/poop/crack 出口随朝向偏移,macOS 同款)
async function perchBranchHere() {   // 用户触发的静态动作补枝规则(用户定):
  // 只有【真空中】才出枝——栖在窗口上/站在任务栏上/脚下有任何表面都不出。
  if (perchedHwnd != null) return;   // 栖着窗口:脚下是窗口
  try {
    const a = await areaFast();
    const o = await getOrigin();
    const feetY = o.y + FEET_TOP_P();
    if (feetY >= a.maxY - 40 * _scale) return;   // 地面(任务栏顶)
    // 脚下有普通窗口(刚落上还没登记栖窗等场景):也不出枝
    const at = await invoke<number | null>("window_at_point_cmd", { x: o.x + SIZE_P() / 2, y: feetY + 4 });
    if (at != null) return;
    branch.showBranchAt(o.x + SIZE_P() / 2, feetY);   // 真空 → 出枝
  } catch { /* */ }
}
function startSing() {
  beginAction(); perchBranchHere(); enter("sing"); playPeep();
  effects.notes(facingRight ? 110 : 50, 34);   // 音符从头上方出(macOS 同款:距顶 34)
  hold(1.2 + Math.random() * 0.4, () => finish());
}
function startSleep() {   // 打盹持续飘 zzz(macOS 每 0.9s,从头上方出)
  beginAction(); enter("sleep");
  const zx = facingRight ? 110 : 50;
  const emitZzz = () => effects.zzz(zx, 50);
  emitZzz();
  if (zzzTimer) clearInterval(zzzTimer);
  zzzTimer = setInterval(emitZzz, 900);
  hold(5 + Math.random() * 4, () => finish());
}
function startEat() { beginAction(); perchBranchHere(); enter("eat"); playPeep(); hold(1.1, () => finish()); }
function startSun() {
  beginAction(); enter("sun");
  // 太阳在鸟斜上方、偏向空的一侧(macOS ±92);local y=-64(鸟头顶上方 64px)
  const sx = facingRight ? -12 : 172;   // 80±92
  const dur = 3 + Math.random() * 2;
  effects.sun(sx, -64, dur);
  hold(dur, () => finish());   // 同一随机数(macOS 同款,晒完太阳正好走)
}
function startPeck() {
  beginAction(); perchBranchHere(); playPeep();   // 先叫一声再啄(macOS:啄时不叫);空中啄脚下补枝
  const count = 3 + Math.floor(Math.random() * 3);        // 连啄 3-5 次
  const willCrack = Math.random() < 0.12;                  // 12% 啄裂(macOS 同款)
  peckBurst(count, willCrack);
}
function peckBurst(remaining: number, willCrack: boolean) {
  enter("peck");
  if (willCrack) {
    getOrigin().then(o => {
      // 鸟嘴屏幕坐标:嘴尖在朝向一侧(macOS: minX + facingRight ? 156 : 4)
      const bx = o.x + (facingRight ? 156 : 4) * _scale;
      crack.crackAt(bx, o.y + (SIZE - 72) * _scale);   // Mac 距底 72 → 顶 88
    }).catch(() => {});
  }
  hold(0.3, () => {
    if (remaining > 1) peckBurst(remaining - 1, willCrack);
    else finish();
  });
}
function startWatch() { beginAction(); enter("watch"); hold(1.4 + Math.random() * 0.8, () => finish()); }
function startPoop() {
  beginAction(); enter("poop");
  getOrigin().then(async o => {
    // 屁股在朝向反侧(macOS: midX + facingRight ? -50 : 50)
    const buttX = o.x + (80 + (facingRight ? -50 : 50)) * _scale;
    await dropPoopAt(buttX, o.y + (SIZE - 58) * _scale);   // 屁股距窗底 58(macOS 同款;顶左原点要翻)
  }).catch(() => {});
  hold(0.8, () => finish());
}

/// 拉屎(含物理):找 (x, y) 正下方最近落点(窗口上沿/任务栏顶),交给舞台窗下落-落定-淡出
async function dropPoopAt(x: number, y: number) {
  let landingY = y + 400, landHwnd: number | null = null, sc = 1;
  try {
    sc = await scale();
    const a = await area();
    let best = a.maxY;   // 任务栏顶(兜底)
    try {
      const list = await invoke<[number, number, number, number][]>("surfaces_below_cmd", { x });   // x 已是物理(调用方换算过),不能再乘 sc
      for (const s of list) {
        const top = s[1];
        // 表面在屎下方(top > y)且取最近的一条(top 最小)。
        // ⚠️ Mac 原比较符是 NS 底原点语义,顶左原点必须翻转——之前照抄,屎永远忽略窗口直落任务栏
        if (top > y + 6 && top < best) { best = top; landHwnd = s[3]; }
      }
    } catch { /* */ }
    landingY = best;
  } catch { /* */ }
  const dist = Math.max(0, landingY - y);
  const fallSec = Math.max(0.15, dist / 220);   // 220px/s(macOS 同款);近距也留 0.15s 可见下落
  try { await poop.dropPoop(x, y, landingY, fallSec, landHwnd, sc); } catch (e) { warnOnce("dropPoop", e); }
}

// 栖窗:飞到最前窗口的上沿歇脚(Win32 front_perch;mac stub 返回 null → finish)
async function startPerchWindow() {
  beginAction(); enter("fly");
  branch.hideBranch();   // 目标是窗口上沿(不用枝):不收会留"幽灵树枝"(用户报告)
  try {
    const sc = await scale();
    const perch = await invoke<[number, number, number] | null>("front_perch_cmd", { birdW: SIZE * sc });   // Rust 收物理
    if (!perch) { finish(); return; }
    const px = perch[0], py = perch[1];   // 物理直用
    if (py - FEET_TOP_P() < (await area()).minY) { startFly(300); return; }   // 窗台太高,头会出屏 → 不停
    const o = await getOrigin();
    setFacing(px > o.x);
    emit("log", `perch: 目标 px=${Math.round(px)} py=${Math.round(py)}(窗沿) 鸟origin应为 py-${Math.round(FEET_TOP_P())}`);
    animateFlight({ x: px, y: py - FEET_TOP_P() }, 1.1, () => {   // 脚踩窗口上沿
      // 记住栖的窗口(HWND+矩形),增量跟随
      perchedHwnd = perch[2];
      lastPerchRect = null;
      startPerchCheck();
      getOrigin().then(l => emit("log", `perch: 落定 origin=${Math.round(l.x)},${Math.round(l.y)} 脚=${Math.round(l.y + FEET_TOP_P())}(应≈${Math.round(py)})`)).catch(() => {});
      finish();
    });
  } catch (e) { finish(); }
}

// 低空掠过(水平快速飞过)
async function startDart() {
  beginAction(); leavePerchWin(); enter("fly");
  try {
    const a = await area();
    const o = await getOrigin();
    const toLeft = Math.random() < 0.5;
    const tx = toLeft ? a.minX + 20 : a.maxX - SIZE_P() - 20;
    setFacing(!toLeft);
    // 落点悬空 → 树枝先到(macOS perchBranchIfNeeded;之前掠飞后旧枝留在原地成"幽灵枝")
    const feetY = o.y + FEET_TOP_P();
    if (feetY < a.maxY - 40 * _scale) branch.showBranchAt(tx + SIZE_P() / 2, feetY);
    else branch.hideBranch();
    animateMove({ x: tx, y: o.y }, 0.55, () => finish());
  } catch (e) { finish(); }
}

// 俯冲捕鱼:飞屏顶 → 俯冲屏底 → 水花 → 飞回吃(招牌动作)
async function startFish() {
  beginAction();
  leavePerchWin();
  branch.hideBranch();   // 起飞收枝(和 startFly/dart 一致;之前漏了 → 鸟飞走旧枝悬空)
  enter("fly");
  try {
    const a = await area();
    const o = await getOrigin();
    const half = SIZE_P() / 2;
    // 全物理(之前钳制用逻辑 SIZE,125%/150% 缩放下鸟整个探出右缘 = "飞到屏幕外")
    const targetX = Math.min(Math.max(a.minX + half + 40 * _scale + Math.random() * (a.maxX - a.minX - SIZE_P() - 80 * _scale), a.minX), a.maxX - SIZE_P());   // 随机俯冲列
    setFacing(targetX + half > o.x + 80);
    animateFlight({ x: targetX, y: a.minY }, 1.0, () => {
      enter("hover");                                   // 悬停瞄准(macOS 同款)
      hold(0.7, () => {
        enter("dive");
        animateMove({ x: targetX, y: a.maxY - FEET_TOP_P() }, 0.45, () => {  // 俯冲到地面(macOS 0.45)
          enter("fly_fish");
          effects.splash(80, 140);                        // 水花(鸟嘴 local)
          hold(0.5, () => {
            const perchX = a.minX + 30 + Math.random() * (a.maxX - a.minX - SIZE_P() - 60);
            const high = Math.random() < 0.5;
            const perchY = high ? a.minY : (a.maxY - FEET_TOP_P());   // 随机高度歇脚
            setFacing(perchX > targetX);   // 叼鱼返航朝向落点(macOS 同款;之前漏了 → 倒着飞)
            if (high) branch.showBranchAt(perchX + half, perchY + FEET_TOP_P());   // 高处 → 树枝先到
            animateFlight({ x: perchX, y: perchY }, 0.95, () => {   // macOS 0.95
              enter("eat");
              playPeep();
              hold(1.1, () => {
                finish();
                schedulePoopAfter(4 + Math.random() * 3);   // 吃完过会儿拉一坨
              });
            });
          });
        });
      });
    });
  } catch (e) { emit("log", "fish " + e); finish(); }
}

/// 吃完拉屎的延时排程(gen 守卫,新动作自动取消)
let poopAfterTimer: ReturnType<typeof setTimeout> | null = null;
function schedulePoopAfter(sec: number) {
  if (poopAfterTimer) clearTimeout(poopAfterTimer);
  const g = gen;
  poopAfterTimer = setTimeout(() => {
    if (gen !== g) return;
    startPoop();
  }, sec * 1000);
}

// MARK: 移动(线性;代际取消:新动作/拖拽 beginAction 后,旧动画 RAF 循环自动停)
function animateMove(to: { x: number; y: number }, duration: number, done: () => void) {
  const g = gen;
  getOrigin().then(start => {
    const t0 = performance.now();
    const dur = sp(duration) * 1000;
    const step = () => {
      if (gen !== g) return;   // 被取消:不再推进也不回调(防两循环打架/幽灵 done)
      const t = Math.min(1, (performance.now() - t0) / dur);
      const x = start.x + (to.x - start.x) * t;
      const y = start.y + (to.y - start.y) * t;
      setOrigin(x, y);
      if (t < 1) requestAnimationFrame(step); else done();
    };
    requestAnimationFrame(step);
  });
}

// MARK: 飞(贝塞尔;代际取消)
function animateFlight(end: { x: number; y: number }, duration: number, done: () => void) {
  const g = gen;
  getOrigin().then(start => {
    const c1 = { x: start.x + (end.x - start.x) * 0.35, y: start.y + (end.y - start.y) * 0.15 };
    const c2 = { x: end.x - (end.x - start.x) * 0.15, y: end.y - (end.y - start.y) * 0.10 };
    const t0 = performance.now();
    const dur = sp(duration) * 1000;
    const step = () => {
      if (gen !== g) return;
      const t = Math.min(1, (performance.now() - t0) / dur);
      const mt = 1 - t;
      let x = mt*mt*mt*start.x + 3*mt*mt*t*c1.x + 3*mt*t*t*c2.x + t*t*t*end.x;
      let y = mt*mt*mt*start.y + 3*mt*mt*t*c1.y + 3*mt*t*t*c2.y + t*t*t*end.y;
      const bob = Math.sin(t * Math.PI * 6);   // 拍翅起伏(macOS 同款)
      y += bob * 4; x += bob * 1.5;
      setOrigin(x, y);
      if (t < 1) requestAnimationFrame(step); else done();
    };
    requestAnimationFrame(step);
  });
}

// MARK: 拖拽(main 调)
// 睡眠/锁屏(对应 macOS sleepForUserAbsence / wakeFromUserAbsence;赖床 2–4 秒)
let userSleeping = false;
let zzzTimer: ReturnType<typeof setInterval> | null = null;
function startZzzInterval() {
  if (zzzTimer) clearInterval(zzzTimer);
  const zx = facingRight ? 110 : 50;   // 从头上方出,随朝向(macOS 同款)
  zzzTimer = setInterval(() => effects.zzz(zx, 50), 900);
}
function stopZzzInterval() { if (zzzTimer) { clearInterval(zzzTimer); zzzTimer = null; } }

export function sleepForUserAbsence() {
  if (userSleeping) return;
  if (!onScreen) return;   // 隐藏着不睡(否则隐形 zzz/醒来满血复活)
  beginAction();
  userSleeping = true;
  setSleepMuted(true);   // 睡眠期间不叫(macOS 同款);正在播的也停
  // 节能:舞台窗隐藏 → WebView2 挂起(全屏透明层不合成);唤醒时恢复
  stageVis("poop", false);
  stageVis("crack", false);
  enter("sleep");
  // 不 startZzz:锁屏后是安全桌面看不见,整天 0.9s/次的 DOM churn 纯耗电;解锁赖床时再飘
}

export async function wakeFromUserAbsence() {
  if (!userSleeping) return;
  if (dndActive) {   // 勿扰中(全屏应用):只清睡眠状态,不 zzz 不恢复——zzz 会盖在视频上
    userSleeping = false;
    setSleepMuted(false);
    busy = false;
    enter("idle");
    return;
  }
  if (!onScreen) { userSleeping = false; return; }   // 隐藏鸟不复活(macOS 同款守卫)
  wakeGraceUntil = performance.now() + 2000;   // 唤醒宽限:窗口层级未稳,先别急着动作
  setSleepMuted(false);
  stageVis("poop", true);   // 舞台恢复(鸟要阴影/特效)
  stageVis("crack", true);
  try { await poop.wakeGrace(); } catch { /* */ }   // 坐着的屎 3s 内不误判重落
  enter("sleep");
  startZzzInterval();
  hold(2 + Math.random() * 2, () => {   // 赖床
    userSleeping = false;
    stopZzzInterval();
    finish();
  });
}

export function dragBegin() { beginAction(); leavePerchWin(); branch.hideBranch(); enter("idle"); }   // 拖拽收枝(macOS 同款)

/// JS 驱动拖拽的每帧落位:目标 = 光标 - 抓取偏移,钳到允许范围后落位。
/// 【每次都钳】→ 窗口物理上不可能出界(macOS 同款"框住范围"手感:
/// 拖到任务栏以下时鸟顶在边界线上,其他区域不响应)。
/// 返回实际落位(调用方作为下一帧的窗口原点缓存)。
let lastDragTo: { x: number; y: number } | null = null;
export async function dragMoveTo(x: number, y: number) {
  const a = await areaFast();
  const cx = Math.min(Math.max(x, a.minX), a.maxX - SIZE_P());
  const cy = Math.min(Math.max(y, a.minY), a.maxY - FEET_TOP_P());   // 脚不进任务栏下
  if (lastDragTo && Math.abs(lastDragTo.x - cx) < 0.5 && Math.abs(lastDragTo.y - cy) < 0.5) return lastDragTo;
  await setOrigin(cx, cy);   // 阴影/命中缓存经 onMoved 链路自带
  lastDragTo = { x: cx, y: cy };
  return lastDragTo;
}
export function dragResetCache() { lastDragTo = null; }

export async function dragDidEnd() {
  try {
    const sc = await scale();
    const o = await getOrigin();
    const a = await area();
    const feetY = o.y + FEET_TOP_P();
    // 吸附候选:任务栏顶 + 水平覆盖鸟的所有窗口上沿(macOS nearestSurface)
    type Surf = { y: number; hwnd: number | null; left: number; topPhys: number };
    const cands: Surf[] = [{ y: a.maxY, hwnd: null, left: 0, topPhys: 0 }];
    try {
      const list = await invoke<[number, number, number, number][]>("surfaces_below_cmd", { x: o.x + SIZE_P() / 2 });   // 物理直传
      for (const s of list) cands.push({ y: s[1], hwnd: s[3], left: s[0], topPhys: s[1] });
    } catch { /* 枚举失败只试任务栏 */ }
    let best: Surf | null = null, bestD = 1e9;
    for (const c of cands) {
      if (c.y - FEET_TOP_P() < a.minY) continue;   // 太高:踩上去鸟头出屏(macOS wouldOvershootTop)
      const d = Math.abs(c.y - feetY);
      if (d < bestD) { bestD = d; best = c; }
    }
    if (best && bestD <= 70 * _scale) {   // 吸附范围 70 逻辑点(物理比较要乘缩放,高 DPI 下否则范围缩水)
      const cx = Math.min(Math.max(o.x, a.minX), a.maxX - SIZE_P());   // X 也钳回屏内(右缘松手别停在屏外)
      const ty = best.y - FEET_TOP_P();
      await setOrigin(cx, ty);   // 脚精确踩表面(x 保持松手位置)
      // 验证+重试:setPosition 是异步 SetWindowPos,与模态拖拽竞速偶发丢失
      // → 之前"松手有时候回不到任务栏上"的根源
      const p = await getOrigin();
      if (Math.abs(p.y - ty) > 2 || Math.abs(p.x - cx) > 2) {
        await setOrigin(cx, ty);
      }
      if (best.hwnd != null) {
        // 吸到窗口上沿:接管栖窗增量跟随(不居中)
        perchedHwnd = best.hwnd;
        lastPerchRect = { x: best.left, y: best.topPhys };
        startPerchCheck();
      }
      finish();
    } else {
      startFly(300);   // 空中松手:飞远
    }
  } catch (e) { finish(); }
}

// MARK: 外部控制(菜单)
/// 召唤:飞向鼠标位置(水平对齐,高度取屏中;macOS 同款)
export async function callOver() {
  if (dndActive) return;   // 勿扰中不召唤(窗口已隐藏,召唤=在全屏上飞)
  if (!onScreen) return;   // 隐藏时不响应(用户方案:唯一恢复入口=显示/隐藏)
  leavePerchWin();
  enter("fly");
  try {
    const sc = await scale();
    const a = await area();
    const cur = await invoke<[number, number] | null>("cursor_pos_cmd");
    const mx = cur ? cur[0] : (a.minX + a.maxX) / 2;   // 物理直用
    const target = {
      x: Math.min(Math.max(mx - SIZE_P() / 2, a.minX), a.maxX - SIZE_P()),
      y: a.minY + (a.maxY - a.minY) * 0.45,
    };
    const o = await getOrigin();
    setFacing(target.x > o.x);
    branch.hideBranch();
    branch.showBranchAt(target.x + SIZE_P() / 2, target.y + FEET_TOP_P());   // 树枝先到(全物理;之前用逻辑常量,高 DPI 下树枝飘错位)
    animateFlight(target, 1.0, () => finish());
  } catch (e) { startFly(); }
}
/// 菜单动作:隐藏时先完整破壳再执行(一次点击=显示+动作;Mac 同款缺失一并修)
/// 隐藏时点动作:先"替用户点一下显示"再执行(用户方案)。
/// 关键实现:显示走 Rust 直操(show_window_bottom_right),不依赖可能被
/// WebView2 挂起的 JS 定时器——之前 hatchIn().await 在窗口隐藏后 hold 的
/// setTimeout 不回调,Promise 永不 resolve → 动作链断裂 → 鸟"运动中消失"
/// + 看门狗 busy 熔断(日志实证:开始破壳×4 无完成,2min 后熔断×2)。
/// 流程:Rust 置右下角+显示 → JS 切蛋帧跑破壳动画 → 1.4s 真实定时器完成后执行动作。
export function doSing() { if (!onScreen) return; startSing(); }   // 隐藏时不响应(用户方案)
export function doEat() { if (!onScreen) return; startEat(); }
export function doFish() { if (!onScreen) return; startFish(); }


export function doPerch() { if (!onScreen) return; startPerchWindow(); }
export function doPeck() { if (!onScreen) return; startPeck(); }

export function setup(ops: {
  lib: SpriteLibrary;
  setState: (s: string) => void;
  setFacing: (right: boolean) => void;
  playPeep?: () => void;
  onMoved?: (x: number, y: number) => void;
}) {
  lib = ops.lib;
  setState = ops.setState;
  const rawFacing = ops.setFacing;
  setFacing = (right: boolean) => { facingRight = right; rawFacing(right); };   // 记录朝向(effects 出口偏移用)
  playPeep = ops.playPeep ?? (() => {});
  onMoved = ops.onMoved ?? (() => {});
}

export async function start() {
  try {
    const a = await area();
    // 位置记忆:恢复上次位置,但【悬空位置不恢复】——上次停在窗口上沿的位置,
    // 重启恢复会出生在半空、脚下没树枝(用户报告"出生偏左悬空")。
    // 只有脚在地面附近(任务栏顶 ±40px)的位置才恢复,否则出生右下角。
    const sx = Number(localStorage.getItem("kf_x")), sy = Number(localStorage.getItem("kf_y"));
    const feetY = sy + FEET_TOP_P();
    if (localStorage.getItem("kf_x") && sx >= a.minX && sx <= a.maxX - SIZE_P() && sy >= a.minY && sy <= a.maxY - FEET_TOP_P()
        && Math.abs(feetY - a.maxY) <= 40 * _scale) {   // 出生必须脚踏实地(悬空 → 右下角)
      // Y 强制贴任务栏顶:恢复位置可能有 ±40 点容差,出生即精确踏地(用户:脚悬空 18px)
      await setOrigin(sx, a.maxY - FEET_TOP_P());
      emit("log", `start: 恢复上次位置 ${Math.round(sx)},Y 贴地 ${Math.round(a.maxY - FEET_TOP_P())}(工作区 ${a.maxX}x${a.maxY})`);
    } else {
      const dx = a.maxX - SIZE_P() - 30 * _scale, dy = a.maxY - FEET_TOP_P();
      await setOrigin(dx, dy);
      emit("log", `start: 出生右下角 ${Math.round(dx)},${Math.round(dy)} 脚=${Math.round(dy + FEET_TOP_P())}(应=${Math.round(a.maxY)})${localStorage.getItem("kf_x") ? " (上次位置悬空,不回)" : ""}`);
    }
    // 坐标自愈:校验窗口(物理)确实落在某台显示器内;不在 → 回当前显示器安全位。
    // 防 DPI/多屏换算错位把鸟丢屏外("没在屏幕里"的逃生口,启动即自愈)
    try {
      const p = await win.outerPosition();
      const mons = await availableMonitors();   // 模块函数(Window 上没有此方法),返回带类型
      const inside = mons.some(m =>
        p.x >= m.position.x - 20 && p.x <= m.position.x + m.size.width + 20 &&
        p.y >= m.position.y - 20 && p.y <= m.position.y + m.size.height + 20);
      if (!inside) {
        emit("log", "start: 窗口在所有显示器外,自愈回安全位");
        await setOrigin(a.maxX - SIZE_P() - 30 * _scale, a.maxY - FEET_TOP_P());
      }
    } catch { /* 校验失败不阻塞 */ }
  } catch (e) { console.error("start", e); }
  // 破壳登场:整蛋→裂纹→探头(macOS hatchIn 同款)再开始活动
  enter("egg");
  await new Promise<void>(r => hold(1.4, () => { enter("idle"); scheduleThink(); emit("log", "hatchIn: 破壳完成"); r(); }));   // 破壳完成才 resolve
}

/// 点击(非拖拽)→ 啾一声 + 心眼害羞 0.8s(macOS petViewWasClicked)
export function happyAction() {
  beginAction();
  playPeep();
  enter("happy");
  hold(0.8, () => finish());
}

// 显示/隐藏 toggle(macOS:隐藏=死掉掉出屏幕,显示=破壳而出)
let onScreen = true;
export function isVisible() { return onScreen; }
export function isSleeping() { return userSleeping; }   // main.ts 睡眠时跳过渲染用

// ── 勿扰模式(全屏应用:鸟不能盖在视频上、不叫;对应 macOS dnd)──
let dndActive = false;
export function isDnd() { return dndActive; }
export async function dndSet(on: boolean) {
  if (on === dndActive) return;
  dndActive = on;
  if (on) {
    emit("log", "dnd: 进入勿扰(鸟隐身+静音)");
    gen++; busy = false; busySince = null;   // 静默打断一切(不能在全屏上播放死亡动画)
    userSleeping = false;
    setSleepMuted(true);
    stopZzzInterval(); stopPerchCheck();
    branch.hideBranch();
    try { await hideShadow(); } catch { /* */ }
    stageVis("poop", false); stageVis("crack", false);
    await setMainVisible(false, "dnd进入");
    enter("sleep");   // 隐藏着,恢复时重置
  } else {
    emit("log", "dnd: 退出勿扰");
    wakeGraceUntil = performance.now() + 1500;
    await setMainVisible(true, "dnd退出");
    stageVis("poop", true); stageVis("crack", true);
    setSleepMuted(false);
    enter("idle");
    busy = false;
    scheduleThink();
  }
}

// ── 看门狗暴露(main.ts 15s 巡检;macOS watchdog 同款哲学:假设自己会坏)──
export function watchdogState() {
  return { busy, busySince, thinkArmed: thinkTimer != null, userSleeping, onScreen };
}
/// 强制复位(卡死熔断):等价"惊醒+回 idle",不清位置
export function watchdogKick() {
  emit("log", "watchdog: 强制复位(busy 卡死或心跳丢失)");
  userSleeping = false;
  setSleepMuted(false);
  stopZzzInterval();
  busy = false;
  busySince = null;
  enter("idle");
  scheduleThink();
}
let visBusy = false;   // 显隐切换串行锁:一次切换完整走完才接受下一次(连点时切换互相穿插是历次竞态的根源)
export function isVisBusy() { return visBusy; }
export async function fallAway() {
  if (!onScreen) return;
  if (visBusy) { emit("log", "vis: 切换进行中,忽略隐藏请求"); return; }
  visBusy = true;
  onScreen = false;
  beginAction(); leavePerchWin();
  const g = gen;   // 代际快照:隐藏链任何 await 之后都要复查——被显示抢进就让位(见动画完成处)
  invoke("anim_guard").catch(() => {});   // 通知 Rust 看门狗:死亡下坠中(4s 内不做出屏找回——否则动画期间被拽回,和 hide 打架)
  enter("dead");
  try {
    const o = await getOrigin();
    branch.hideBranch();
    const a = await area();
    // 掉出屏幕底(线性下坠)后隐藏窗口
    animateMove({ x: o.x, y: a.maxY + SIZE_P() + 40 * _scale }, 0.85, async () => {
      // 【根修】隐藏前把最后一帧画成蛋:WebView2 挂起时合成器冻结保留
      // "隐藏前最后画的那帧"——之前保留的是死亡动画的鸟本体,显示瞬间先亮鸟
      // 再画蛋 = "先见鸟后破壳"。隐藏期间 JS 完全暂停,显示前不可能改这帧,
      // 唯一时机就是现在(窗口已在屏外,重绘无人看见)。macOS fallAway 一直
      // 有同款(applyNow egg)。
      enter("egg");
      await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));   // 等两帧,确保合成器拿到蛋帧
      // 竞态关键点:这 2 帧窗口(~33ms)内若用户点了"显示",hatchIn 已显示窗口并接管状态
      // ——此处隐藏再落地就会把窗口藏死而状态=可见 = 卡隐身(鸟隐形飞行"消失",用户实测)。
      // 复查代际,被取代就让位(隐藏由对方拥有,不再执行)
      if (gen !== g) { emit("log", "fallAway: 隐藏被显示抢进,让位"); visBusy = false; return; }
      await setMainVisible(false, "fallAway");
      hideShadow();
      stageVis("poop", false);   // 隐藏鸟:特效舞台挂起(零耗);裂纹不动——屏幕裂纹与鸟无关(用户定)
      busy = false;   // 状态保持 egg(保留帧一致),不回 idle
      visBusy = false;
    });
  } catch { onScreen = true; visBusy = false; finish(); }
}
/// 主窗显隐统一出口(全程留痕:消失类问题的日志定位——之前 hide/show 散落
/// 各处且失败静默,鸟"有几率消失"后无从查证)
async function setMainVisible(on: boolean, why: string) {
  try {
    if (on) {
      await invoke("show_no_activate");
      // 验证:显示后窗口真的可见(RDP/托盘菜单竞速下有概率失败,失败重试一次)
      let ok = false;
      try { ok = await win.isVisible(); } catch { /* */ }
      if (!ok) {
        emit("log", `vis: 显示未生效(${why}),重试`);
        await invoke("show_no_activate");
        try { ok = await win.isVisible(); } catch { /* */ }
        if (!ok) { warnOnce("show 失败 " + why, new Error("不可见")); return false; }
      }
      emit("log", `vis: 显示 ✓ (${why})`);
      return true;
    } else {
      await win.hide();
      emit("log", `vis: 隐藏 ✓ (${why})`);
      return true;
    }
  } catch (e) {
    warnOnce("vis " + (on ? "show" : "hide") + " " + why, e);
    return false;
  }
}

export async function hatchIn() {
  if (onScreen) return;
  if (dndActive) return;   // 勿扰中不复活(同 recall)
  if (visBusy) { emit("log", "vis: 切换进行中,忽略显示请求"); return; }
  visBusy = true;
  onScreen = true;
  beginAction();
  const g = gen;   // 代际快照:下方 await 之后复查(被隐藏抢进就让位,对称防竞态)
  emit("log", "hatchIn: 开始破壳(隐藏后复活/召唤)");
  enter("egg");   // 先切蛋帧再显示——之前先亮窗(上一帧 idle)再变蛋,"先出来再破壳"的错序
  try {
    const a = await area();
    await setOrigin(a.maxX - SIZE_P() - 30 * _scale, a.maxY - FEET_TOP_P());
    if (gen !== g) { emit("log", "hatchIn: 显示被隐藏抢进,让位"); visBusy = false; return; }   // fallAway 已接管,窗口将由它隐藏
    await setMainVisible(true, "hatchIn");   // 显示+验证(之前失败被静默吞 → onScreen=true 但窗口隐藏 = 卡隐身,点动作全部隐形执行,"鸟消失")
    stageVis("poop", true);   // 裂纹舞台不跟显隐(用户定)
    visBusy = false;   // 显示完成即解锁(破壳动画期间允许下一次切换;串行的是窗口级显示/隐藏)
  } catch (e) { warnOnce("hatchIn", e); visBusy = false; }
  hold(1.4, () => { enter("idle"); scheduleThink(); emit("log", "hatchIn: 破壳完成"); });
}
