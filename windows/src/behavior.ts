// 行为状态机 + 移动(走/飞)+ 代际取消。移植自 macOS Behavior.swift。
// 坐标统一用物理像素(PhysicalPosition),和 outerPosition/screenX 一致,避免 logical/physical 混淆。

import { getCurrentWindow, PhysicalPosition } from "@tauri-apps/api/window";
import type { Window as TauriWindow } from "@tauri-apps/api/window";
import { emit } from "@tauri-apps/api/event";
import type { SpriteLibrary } from "./sprite";
import * as effects from "./effects";
import * as poop from "./poop";
import * as crack from "./crack";
import * as branch from "./branch";
import { invoke } from "@tauri-apps/api/core";
import { settings } from "./settings";

const win: TauriWindow = getCurrentWindow();
const SIZE = 160;
const FEET_OFFSET = 26;

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

async function area(): Promise<{ minX: number; minY: number; maxX: number; maxY: number }> {
  try {
    const m = await (win as any).currentMonitor();   // Tauri Window.currentMonitor(TS lib DOM Window 类型冲突,局部 cast)
    // 多屏:monitor.position 是全局物理原点(副屏可能是负),clamp 必须用它,否则鸟被推出屏外
    if (m) return {
      minX: m.position.x, minY: m.position.y,
      maxX: m.position.x + m.size.width,
      maxY: m.position.y + m.size.height - 70,   // -70 预留任务栏
    };
  } catch (e) { emit("log", "area " + e); }
  return { minX: 0, minY: 0, maxX: 1280, maxY: 730 };
}

async function getOrigin(): Promise<{ x: number; y: number }> {
  const p = await win.outerPosition();
  return { x: p.x, y: p.y };
}

async function setOrigin(x: number, y: number) {
  try {
    await win.setPosition(new PhysicalPosition(Math.round(x), Math.round(y)));   // PhysicalPosition 要 i32
    onMoved(x, y);
  } catch (e) { emit("log", "setOrigin err x=" + x + " y=" + y + ": " + e); }
}

function clampX(o: { x: number; y: number }, a: { minX: number; maxX: number; minY: number; maxY: number }) {
  return {
    x: Math.min(Math.max(o.x, a.minX), a.maxX - SIZE),
    y: Math.min(Math.max(o.y, a.minY), a.maxY - SIZE),
  };
}

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
function startPerchCheck() {
  stopPerchCheck();
  if (perchedHwnd == null) return;
  const hwnd = perchedHwnd;
  perchTimer = setInterval(async () => {
    try {
      const r = await invoke<[number, number, number, number] | null>("window_rect_cmd", { hwndVal: hwnd });
      if (!r) { stopPerchCheck(); startFly(300); return; }   // 窗口没了 → 飞远
      if (!lastPerchRect) { lastPerchRect = { x: r[0], y: r[1] }; return; }
      const dx = r[0] - lastPerchRect.x, dy = r[1] - lastPerchRect.y;
      if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) {
        const o = await getOrigin();
        await setOrigin(o.x + dx, o.y + dy);   // 增量跟随,保持相对位置(不往窗口中间凑)
        lastPerchRect = { x: r[0], y: r[1] };
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
  if (busy) { scheduleThink(); return; }
  const r = Math.random();
  if (r < 0.25) { enter("idle"); scheduleThink(); }
  else if (r < 0.45) startWalk();
  else if (r < 0.60) startFly();
  else if (r < 0.70) startSing();
  else if (r < 0.78) startSleep();
  else if (r < 0.85) startEat();
  else if (r < 0.92) startSun();
  else if (r < 0.95) startWatch();
  else if (r < 0.975) startPerchWindow();
  else if (r < 0.99) startFish();
  else if (r < 0.997) startPoop();
  else if (r < 0.999) startDart();
  else startPeck();
}

// MARK: 走(线性;沿当前表面高度走,macOS 同款不瞬移 Y)
async function startWalk() {
  beginAction();
  enter("walk");
  try {
    const a = await area();
    const o = await getOrigin();
    const dir = Math.random() < 0.5 ? 1 : -1;
    const dist = 80 + Math.random() * 120;
    const tx = Math.min(Math.max(o.x + dir * dist, a.minX), a.maxX - SIZE);
    if (Math.abs(tx - o.x) < 20) { finish(); return; }
    setFacing(tx > o.x);
    animateMove({ x: tx, y: o.y }, Math.max(0.6, Math.abs(tx - o.x) / 70), () => finish());
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
    animateFlight({ x: tx, y: ty }, 1.3, () => {
      if (feetY >= a.maxY - 40) branch.hideBranch();   // 落地(任务栏)→ 确保无枝
      finish();
    });
  } catch (e) { console.error("fly", e); finish(); }
}

// MARK: 静态动作
let facingRight = false;   // 朝向(effects/poop/crack 出口随朝向偏移,macOS 同款)
function startSing() { beginAction(); enter("sing"); playPeep(); effects.notes(80, 50); hold(1.2 + Math.random() * 0.4, () => finish()); }
function startSleep() { beginAction(); enter("sleep"); startZzzInterval(); hold(5 + Math.random() * 4, () => finish()); }   // 打盹持续飘 zzz(macOS 每 0.9s)
function startEat() { beginAction(); enter("eat"); playPeep(); hold(1.1, () => finish()); }
function startSun() { beginAction(); enter("sun"); effects.sun(80, 30, 3 + Math.random() * 2); hold(3 + Math.random() * 2, () => finish()); }
function startPeck() {
  beginAction(); playPeep(); enter("peck");
  getOrigin().then(o => {
    // 鸟嘴屏幕坐标:嘴尖在朝向一侧(macOS: minX + facingRight ? 156 : 4)
    const bx = o.x + (facingRight ? 156 : 4);
    crack.crackAt(bx, o.y + 72);
  }).catch(() => {});
  hold(0.5, () => finish());
}
function startWatch() { beginAction(); enter("watch"); hold(1.4 + Math.random() * 0.8, () => finish()); }
function startPoop() {
  beginAction(); enter("poop");
  getOrigin().then(o => {
    // 屁股在朝向反侧(macOS: midX + facingRight ? -50 : 50)
    const buttX = o.x + 80 + (facingRight ? -50 : 50);
    poop.dropPoop(buttX, o.y + 58);
  }).catch(() => {});
  hold(0.8, () => finish());
}

// 栖窗:飞到最前窗口的上沿歇脚(Win32 front_perch;mac stub 返回 null → finish)
async function startPerchWindow() {
  beginAction(); enter("fly");
  try {
    const perch = await invoke<[number, number, number] | null>("front_perch_cmd", { birdW: SIZE });
    if (!perch) { finish(); return; }
    const o = await getOrigin();
    setFacing(perch[0] > o.x);
    animateFlight({ x: perch[0], y: perch[1] }, 1.1, () => {
      // 记住栖的窗口(HWND+矩形),增量跟随
      perchedHwnd = perch[2];
      lastPerchRect = { x: 0, y: 0 };
      invoke<[number, number, number, number] | null>("window_rect_cmd", { hwndVal: perch[2] }).then(r => {
        if (r) lastPerchRect = { x: r[0], y: r[1] };
        startPerchCheck();
      }).catch(() => {});
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
    const targetX = Math.max(a.minX, Math.min(o.x, a.maxX - SIZE));
    setFacing(targetX > o.x);
    animateFlight({ x: targetX, y: a.minY }, 1.0, () => {       // 飞到屏顶
      enter("dive");
      animateMove({ x: targetX, y: a.maxY - FEET_OFFSET }, 0.5, () => {  // 俯冲到地面(脚贴任务栏顶)
        enter("fly_fish");
        effects.splash(80, 140);                                   // 水花(鸟嘴 local)
        hold(0.5, () => {
          const perchX = a.minX + 30 + Math.random() * (a.maxX - a.minX - SIZE - 60);
          animateFlight({ x: perchX, y: a.maxY - FEET_OFFSET }, 1.0, () => {  // 飞回地面
            enter("eat");
            playPeep();
            hold(1.1, () => finish());
          });
        });
      });
    });
  } catch (e) { emit("log", "fish " + e); finish(); }
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
      const x = mt*mt*mt*start.x + 3*mt*mt*t*c1.x + 3*mt*t*t*c2.x + t*t*t*end.x;
      const y = mt*mt*mt*start.y + 3*mt*mt*t*c1.y + 3*mt*t*t*c2.y + t*t*t*end.y;
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
  zzzTimer = setInterval(() => effects.zzz(80, 50), 900);
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
export async function dragDidEnd() {
  try {
    const o = await getOrigin();
    const a = await area();
    const feetY = o.y + FEET_OFFSET;
    if (Math.abs(feetY - a.maxY) <= 70) {
      await setOrigin(o.x, a.maxY - FEET_OFFSET);   // 地面(任务栏顶)±70 内:吸附到精确位置
      finish();
    } else {
      startFly(300);   // 空中松手:飞远
    }
  } catch (e) { finish(); }
}

// MARK: 外部控制(菜单)
export function callOver() { startFly(); }
export function doSing() { if (!busy) startSing(); }
export function doEat() { if (!busy) startEat(); }

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
    await setOrigin(a.maxX - SIZE - 30, a.maxY - FEET_OFFSET);   // 脚贴任务栏顶
  } catch (e) { console.error("start", e); }
  enter("idle");
  scheduleThink();
}
