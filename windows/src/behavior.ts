// 行为状态机 + 移动(走/飞)+ 代际取消。移植自 macOS Behavior.swift。
// 坐标统一用【逻辑像素】:Rust(Win32)返回物理,这里统一 /scale 转逻辑;
// 窗口定位用 LogicalPosition。之前物理/逻辑混用,在 125%/150% 缩放下
// 脚位、树枝、地面全部错位(鸟落不到树枝上的根源之一)。

import { getCurrentWindow, LogicalPosition } from "@tauri-apps/api/window";
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

const win: TauriWindow = getCurrentWindow();
const SIZE = 160;      // 窗口逻辑宽高
const FEET_OFFSET = 26; // 脚距窗口底(逻辑;256 sprite 的脚 ≈ 42/256*160)

let lib: SpriteLibrary;
let setState: (s: string) => void;
let setFacing: (right: boolean) => void;
let playPeep: () => void;
let onMoved: (x: number, y: number) => void;

let gen = 0;
let busy = false;
let thinkTimer: ReturnType<typeof setTimeout> | null = null;
let perchTimer: ReturnType<typeof setInterval> | null = null;   // 栖窗跟随轮询

const sp = (s: number) => s / settings.speed;   // 受全局动画速度影响

/// 当前显示器缩放(逻辑 = 物理 / scale)。缓存,变化少。
let _scale = 1;
async function scale(): Promise<number> {
  try {
    const m = await (win as any).currentMonitor();
    if (m && m.scaleFactor) { _scale = m.scaleFactor; }
  } catch { /* */ }
  return _scale;
}
const toLog = (v: number) => v / _scale;   // 物理 → 逻辑(先 await scale() 过)

async function area(): Promise<{ minX: number; minY: number; maxX: number; maxY: number }> {
  try {
    const sc = await scale();
    const m = await (win as any).currentMonitor();   // Tauri Window.currentMonitor(TS lib DOM Window 类型冲突,局部 cast)
    // 多屏:monitor.position 是全局物理原点(副屏可能为负),转逻辑后 clamp
    if (m) return {
      minX: toLog(m.position.x), minY: toLog(m.position.y),
      maxX: toLog(m.position.x + m.size.width),
      maxY: toLog(m.position.y + m.size.height) - 70 / sc,   // -70 物理预留任务栏 → 逻辑
    };
  } catch (e) { emit("log", "area " + e); }
  return { minX: 0, minY: 0, maxX: 1280, maxY: 730 };
}

async function getOrigin(): Promise<{ x: number; y: number }> {
  await scale();                 // 刷新 _scale(物理→逻辑换算用)
  const p = await win.outerPosition();
  return { x: toLog(p.x), y: toLog(p.y) };
}

async function setOrigin(x: number, y: number) {
  try {
    await win.setPosition(new LogicalPosition(Math.round(x), Math.round(y)));
    onMoved(x, y);
    // 位置记忆(节流 1s 存一次,防高频移动刷 localStorage)
    if (!savePosAt) savePosAt = setTimeout(() => {
      savePosAt = null;
      localStorage.setItem("kf_x", String(Math.round(x)));
      localStorage.setItem("kf_y", String(Math.round(y)));
    }, 1000);
  } catch (e) { emit("log", "setOrigin err x=" + x + " y=" + y + ": " + e); }
}
let savePosAt: ReturnType<typeof setTimeout> | null = null;

function beginAction() {
  gen++;
  busy = true;
  if (thinkTimer) { clearTimeout(thinkTimer); thinkTimer = null; }
  stopPerchCheck();   // 新动作 → 停栖窗跟随
  // 惊醒:macOS beginAction 同款——赖床中被新动作(拖拽/菜单)打断要清睡眠标志,
  // 否则 wake 的 hold 被 gen 作废,userSleeping 永久卡 true
  if (userSleeping) { userSleeping = false; stopZzzInterval(); }
}
function stopPerchCheck() {
  if (perchTimer) { clearInterval(perchTimer); perchTimer = null; }
  perchedHwnd = null;
}
// 栖窗增量跟随:记住栖的 HWND + 上次矩形,20fps 查窗口位移增量应用到鸟
// (不往窗口中间凑、alt-tab 换前台不拽走鸟;窗口没了 → 飞走)。对应 macOS checkPerch。
let perchedHwnd: number | null = null;
let lastPerchRect: { x: number; y: number } | null = null;
let perchMoving = false, lastPerchMove = 0;
function startPerchCheck() {
  stopPerchCheck();
  if (perchedHwnd == null) return;
  const hwnd = perchedHwnd;
  perchTimer = setInterval(async () => {
    try {
      const r = await invoke<[number, number, number, number] | null>("window_rect_cmd", { hwndVal: hwnd });
      if (!r) { stopPerchCheck(); startFly(300); return; }   // 窗口没了 → 飞远
      const wx = toLog(r[0]), wy = toLog(r[1]);   // 物理 → 逻辑
      if (!lastPerchRect) { lastPerchRect = { x: wx, y: wy }; return; }
      const dx = wx - lastPerchRect.x, dy = wy - lastPerchRect.y;
      if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) {
        perchMoving = true; lastPerchMove = performance.now();   // 用户拖栖窗 → think 推迟(macOS 同款)
        const o = await getOrigin();
        await setOrigin(o.x + dx, o.y + dy);   // 增量跟随,保持相对位置(不往窗口中间凑)
        lastPerchRect = { x: wx, y: wy };
      } else if (perchMoving && performance.now() - lastPerchMove > 600) {
        perchMoving = false;   // 停 0.6s → 恢复思考
      }
    } catch (e) { /* */ }
  }, 50);
}

function enter(s: string) { setState(s); }
function finish() { busy = false; stopZzzInterval(); enter("idle"); scheduleThink(); }

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

async function think() {
  if (busy || perchMoving) { scheduleThink(); return; }   // 栖窗被用户拖动中:推迟预设动作
  // 权重对齐 macOS think():idle/walk 带随活跃度伸缩(高活跃→少待机多走动),
  // 其余固定:fish 8 / fly 7 / sing 7 / dart 7 / watch 7 / sun 5 / peck 5 / poop 5 / perch 4
  const a = settings.activity;
  const idleBand = Math.round((1 - a) * 22);            // 0→22, 1→0
  const walkEnd = idleBand + Math.max(1, Math.round((1 - a) * 20));   // idle+walk 带
  const r = Math.random();
  if (r < idleBand) { enter("idle"); scheduleThink(); }
  else if (r < walkEnd) startWalk();
  else if (r < walkEnd + 8) startFish();
  else if (r < walkEnd + 15) startFly();
  else if (r < walkEnd + 22) startSing();
  else if (r < walkEnd + 29) startDart();
  else if (r < walkEnd + 36) startWatch();
  else if (r < walkEnd + 41) startSun();
  else if (r < walkEnd + 46) startPeck();
  else if (r < walkEnd + 51) startPoop();
  else if (r < walkEnd + 55) startPerchWindow();
  else startSleep();
}

// MARK: 走(线性)。门控:只在"地面"走——任务栏顶,或栖着的窗口上沿(macOS 同款);
// 空中/半空不走路,改飞。沿当前表面高度走,不瞬移 Y。
// 走完检查:栖窗行走时若走出窗口横向范围(脚悬空)→ 飞走(macOS"走到边就飞")。
async function startWalk() {
  const perched = perchedHwnd;   // 先记下(beginAction→stopPerchCheck 会清)
  beginAction();
  enter("walk");
  try {
    const a = await area();
    const o = await getOrigin();
    const onGround = o.y + FEET_OFFSET >= a.maxY - 40;      // 脚贴近任务栏顶
    if (!onGround && perched == null) { finish(); return; }   // 空中/半空 → 不走,回 idle(macOS 同款)
    const dir = Math.random() < 0.5 ? 1 : -1;
    const dist = 80 + Math.random() * 120;
    const tx = Math.min(Math.max(o.x + dir * dist, a.minX), a.maxX - SIZE);
    if (Math.abs(tx - o.x) < 20) { finish(); return; }
    setFacing(tx > o.x);
    animateMove({ x: tx, y: o.y }, Math.max(0.6, Math.abs(tx - o.x) / 70), async () => {
      // 走完:在窗口上走到边(脚不在窗口横向范围)→ 飞远
      if (perched != null && !(o.y + FEET_OFFSET >= a.maxY - 40)) {
        try {
          await scale();
          const r = await invoke<[number, number, number, number] | null>("window_rect_cmd", { hwndVal: perched });
          if (r) {
            const wx0 = toLog(r[0]), wx1 = toLog(r[0] + r[2]);
            const midX = tx + SIZE / 2;
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
  enter("fly");
  try {
    const a = await area();
    const o = await getOrigin();
    let tx = o.x, ty = o.y;
    for (let i = 0; i < 8; i++) {   // 重选直到够远(或用完次数)
      tx = a.minX + Math.random() * (a.maxX - a.minX - SIZE);
      ty = Math.random() < 0.5 ? (a.maxY - FEET_OFFSET) : a.minY;
      if (Math.hypot(tx - o.x, ty - o.y) >= minDist) break;
    }
    setFacing(tx > o.x);
    branch.hideBranch();   // 起飞 → 先收当前树枝
    // 落点悬空(脚高于任务栏区)→ 树枝先到(屏幕坐标预显,对应 macOS perchBranchIfNeeded)
    const feetY = ty + FEET_OFFSET;
    if (feetY < a.maxY - 40) branch.showBranchAt(tx + SIZE / 2, feetY);
    // 35% 空中拉屎(macOS 同款):飞行途中从屁股掉一坨
    if (Math.random() < 0.35) {
      const g = gen, ax = o.x + 80 + (tx > o.x ? -50 : 50);
      setTimeout(() => { if (gen === g) dropPoopAt(ax, o.y + (SIZE - 40)); }, sp(0.3 + Math.random() * 0.4) * 1000);
    }
    animateFlight({ x: tx, y: ty }, 1.3, () => {
      if (feetY >= a.maxY - 40) branch.hideBranch();   // 落地(任务栏)→ 确保无枝
      finish();
    });
  } catch (e) { console.error("fly", e); finish(); }
}

// MARK: 静态动作
let facingRight = false;   // 朝向(effects/poop/crack 出口随朝向偏移,macOS 同款)
function startSing() {
  beginAction(); enter("sing"); playPeep();
  effects.notes(facingRight ? 110 : 50, 50);   // 音符从头侧上方出(macOS 同款)
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
function startEat() { beginAction(); enter("eat"); playPeep(); hold(1.1, () => finish()); }
function startSun() {
  beginAction(); enter("sun");
  // 太阳在鸟斜上方、偏向空的一侧(macOS ±92);local y=-64(鸟头顶上方 64px)
  const sx = facingRight ? -12 : 172;   // 80±92
  effects.sun(sx, -64, 3 + Math.random() * 2);
  hold(3 + Math.random() * 2, () => finish());
}
function startPeck() {
  beginAction(); playPeep();   // 先叫一声再啄(macOS:啄时不叫)
  const count = 3 + Math.floor(Math.random() * 3);        // 连啄 3-5 次
  const willCrack = Math.random() < 0.12;                  // 12% 啄裂(macOS 同款)
  peckBurst(count, willCrack);
}
function peckBurst(remaining: number, willCrack: boolean) {
  enter("peck");
  if (willCrack) {
    getOrigin().then(o => {
      // 鸟嘴屏幕坐标:嘴尖在朝向一侧(macOS: minX + facingRight ? 156 : 4)
      const bx = o.x + (facingRight ? 156 : 4);
      crack.crackAt(bx, o.y + 72);   // crackAt 自带 55px 合并生长
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
    const buttX = o.x + 80 + (facingRight ? -50 : 50);
    await dropPoopAt(buttX, o.y + (SIZE - 58));   // 屁股距窗底 58(macOS 同款;顶左原点要翻)
  }).catch(() => {});
  hold(0.8, () => finish());
}

/// 拉屎(含物理):找 (x, y) 正下方最近落点(窗口上沿/任务栏顶),交给舞台窗下落-落定-淡出
async function dropPoopAt(x: number, y: number) {
  let landingY = y + 400;   // 兜底
  try {
    const sc = await scale();
    const a = await area();
    let best = a.maxY;   // 任务栏顶
    try {
      const list = await invoke<[number, number, number, number][]>("surfaces_below_cmd", { x: x * sc });
      for (const s of list) {
        const top = toLog(s[1]);
        if (top < y - 6 && top > best) best = top;   // 在屎下方且更高的表面
      }
    } catch { /* */ }
    landingY = best;
  } catch { /* */ }
  const dist = Math.max(0, landingY - y);
  const fallSec = dist / 220;   // 220px/s(macOS 同款)
  try { await poop.dropPoop(x, y, landingY, fallSec); } catch { /* */ }
}

// 栖窗:飞到最前窗口的上沿歇脚(Win32 front_perch;mac stub 返回 null → finish)
async function startPerchWindow() {
  beginAction(); enter("fly");
  try {
    const sc = await scale();
    const perch = await invoke<[number, number, number] | null>("front_perch_cmd", { birdW: SIZE * sc });   // Rust 收物理
    if (!perch) { finish(); return; }
    const px = toLog(perch[0]), py = toLog(perch[1]);   // 物理 → 逻辑
    if (py - FEET_OFFSET < (await area()).minY) { startFly(300); return; }   // 窗台太高,头会出屏 → 不停
    const o = await getOrigin();
    setFacing(px > o.x);
    animateFlight({ x: px, y: py - FEET_OFFSET }, 1.1, () => {   // 脚踩窗口上沿
      // 记住栖的窗口(HWND+矩形),增量跟随
      perchedHwnd = perch[2];
      lastPerchRect = null;
      startPerchCheck();
      finish();
    });
  } catch (e) { finish(); }
}

// 低空掠过(水平快速飞过)
async function startDart() {
  beginAction(); enter("fly");
  try {
    const a = await area();
    const o = await getOrigin();
    const toLeft = Math.random() < 0.5;
    const tx = toLeft ? a.minX + 20 : a.maxX - SIZE - 20;
    setFacing(!toLeft);
    animateMove({ x: tx, y: o.y }, 0.55, () => finish());
  } catch (e) { finish(); }
}

// 俯冲捕鱼:飞屏顶 → 俯冲屏底 → 水花 → 飞回吃(招牌动作)
async function startFish() {
  beginAction();
  enter("fly");
  try {
    const a = await area();
    const o = await getOrigin();
    const half = SIZE / 2;
    const targetX = Math.min(Math.max(a.minX + half + 40 + Math.random() * (a.maxX - a.minX - SIZE - 80), a.minX), a.maxX - SIZE);   // 随机俯冲列
    setFacing(targetX + half > o.x + 80);
    animateFlight({ x: targetX, y: a.minY }, 1.0, () => {
      enter("hover");                                   // 悬停瞄准(macOS 同款)
      hold(0.7, () => {
        enter("dive");
        animateMove({ x: targetX, y: a.maxY - FEET_OFFSET }, 0.5, () => {  // 俯冲到地面
          enter("fly_fish");
          effects.splash(80, 140);                        // 水花(鸟嘴 local)
          hold(0.5, () => {
            const perchX = a.minX + 30 + Math.random() * (a.maxX - a.minX - SIZE - 60);
            const high = Math.random() < 0.5;
            const perchY = high ? a.minY : (a.maxY - FEET_OFFSET);   // 随机高度歇脚
            if (high) branch.showBranchAt(perchX + half, perchY + FEET_OFFSET);   // 高处 → 树枝先到
            animateFlight({ x: perchX, y: perchY }, 1.0, () => {
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
  beginAction();
  userSleeping = true;
  enter("sleep");
  startZzzInterval();
}

export function wakeFromUserAbsence() {
  if (!userSleeping) return;
  enter("sleep");
  startZzzInterval();
  hold(2 + Math.random() * 2, () => {   // 赖床
    userSleeping = false;
    stopZzzInterval();
    finish();
  });
}

export function dragBegin() { beginAction(); branch.hideBranch(); enter("idle"); }   // 拖拽收枝(macOS 同款)

/// 原生拖拽中的边界钳制(逻辑坐标):脚不进任务栏下、头不出屏顶、横向不出屏。
/// 节流 100ms——和 Win32 模态移动循环互 setPosition 打架会抖。
let lastClamp = 0;
export async function clampDragFrame(x: number, y: number) {
  const now = performance.now();
  if (now - lastClamp < 100) return;
  lastClamp = now;
  try {
    const a = await area();
    const cx = Math.min(Math.max(x, a.minX), a.maxX - SIZE);
    const cy = Math.min(Math.max(y, a.minY), a.maxY - FEET_OFFSET);   // 脚最低到任务栏顶
    if (Math.abs(cx - x) > 1 || Math.abs(cy - y) > 1) {
      await setOrigin(cx, cy);
    }
  } catch { /* */ }
}
export async function dragDidEnd() {
  try {
    const sc = await scale();
    const o = await getOrigin();
    const a = await area();
    const feetY = o.y + FEET_OFFSET;
    // 吸附候选:任务栏顶 + 水平覆盖鸟的所有窗口上沿(macOS nearestSurface)
    type Surf = { y: number; hwnd: number | null; left: number; topPhys: number };
    const cands: Surf[] = [{ y: a.maxY, hwnd: null, left: 0, topPhys: 0 }];
    try {
      const list = await invoke<[number, number, number, number][]>("surfaces_below_cmd", { x: (o.x + SIZE / 2) * sc });
      for (const s of list) cands.push({ y: toLog(s[1]), hwnd: s[3], left: toLog(s[0]), topPhys: s[1] });
    } catch { /* 枚举失败只试任务栏 */ }
    let best: Surf | null = null, bestD = 1e9;
    for (const c of cands) {
      if (c.y - FEET_OFFSET < a.minY) continue;   // 太高:踩上去鸟头出屏(macOS wouldOvershootTop)
      const d = Math.abs(c.y - feetY);
      if (d < bestD) { bestD = d; best = c; }
    }
    if (best && bestD <= 70) {
      await setOrigin(o.x, best.y - FEET_OFFSET);   // 脚精确踩表面(x 保持松手位置)
      if (best.hwnd != null) {
        // 吸到窗口上沿:接管栖窗增量跟随(不居中)
        perchedHwnd = best.hwnd;
        lastPerchRect = { x: best.left, y: toLog(best.topPhys) };
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
  beginAction();
  enter("fly");
  try {
    const sc = await scale();
    const a = await area();
    const cur = await invoke<[number, number] | null>("cursor_pos_cmd");
    const mx = cur ? toLog(cur[0]) : (a.minX + a.maxX) / 2;   // 拿不到鼠标就屏中
    const target = {
      x: Math.min(Math.max(mx - SIZE / 2, a.minX), a.maxX - SIZE),
      y: a.minY + (a.maxY - a.minY) * 0.45,
    };
    const o = await getOrigin();
    setFacing(target.x > o.x);
    branch.hideBranch();
    branch.showBranchAt(target.x + SIZE / 2, target.y + FEET_OFFSET);   // 树枝先到
    animateFlight(target, 1.0, () => finish());
  } catch (e) { startFly(); }
}
export function doSing() { if (!busy) startSing(); }
export function doEat() { if (!busy) startEat(); }
export function doFish() { if (!busy) startFish(); }
export function doPerch() { startPerchWindow(); }   // 菜单指定动作打断当前(macOS 同款不判 busy)
export function doPeck() { startPeck(); }

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
    // 位置记忆:有存过位置就恢复,否则右下角脚贴任务栏(macOS 同款)
    const sx = Number(localStorage.getItem("kf_x")), sy = Number(localStorage.getItem("kf_y"));
    if (localStorage.getItem("kf_x") && sx >= a.minX && sx <= a.maxX - SIZE && sy >= a.minY && sy <= a.maxY - SIZE) {
      await setOrigin(sx, sy);
    } else {
      await setOrigin(a.maxX - SIZE - 30, a.maxY - FEET_OFFSET);
    }
  } catch (e) { console.error("start", e); }
  // 破壳登场:整蛋→裂纹→探头(macOS hatchIn 同款)再开始活动
  enter("egg");
  hold(1.4, () => { enter("idle"); scheduleThink(); });
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
export async function fallAway() {
  if (!onScreen) return;
  onScreen = false;
  beginAction();
  enter("dead");
  try {
    const o = await getOrigin();
    branch.hideBranch();
    const a = await area();
    // 掉出屏幕底(线性下坠)后隐藏窗口
    animateMove({ x: o.x, y: a.maxY + SIZE + 40 }, 0.85, async () => {
      try { await (win as any).hide(); } catch { /* */ }
      hideShadow();
      enter("idle");
      busy = false;
    });
  } catch { onScreen = true; finish(); }
}
export async function hatchIn() {
  if (onScreen) return;
  onScreen = true;
  beginAction();
  try {
    const a = await area();
    await setOrigin(a.maxX - SIZE - 30, a.maxY - FEET_OFFSET);
    await invoke("show_no_activate");   // 显示但不抢前台焦点
  } catch { /* */ }
  enter("egg");
  hold(1.4, () => { enter("idle"); scheduleThink(); });
}
