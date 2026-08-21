// 逐帧渲染 + 拖拽(JS 驱动,macOS 同构)+ 行为状态机。日志通过 emit 发 Rust 终端。

import { getCurrentWindow, LogicalSize, currentMonitor, availableMonitors } from "@tauri-apps/api/window";
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { listen, emit } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { SpriteLibrary } from "./sprite";
import { setupHitTest, updateHitOrigin } from "./hittest";
import { setupShadow, updateShadow } from "./shadow";
import { setupPoop } from "./poop";
import { clearCracks } from "./crack";   // crack 窗懒创建:首次 crackAt 才建(省一个常驻全屏层)
import { setupBranch } from "./branch";
import { setupTheme, setTheme } from "./theme";
import { setupAudio, playPeep, setSoundOn } from "./audio";
import { settings, setSound, setActivity, setSpeed } from "./settings";
import * as behavior from "./behavior";

const lib = new SpriteLibrary();
const petWin = getCurrentWindow();
const img = document.getElementById("sprite") as HTMLImageElement;
const effectLayer = document.getElementById("effects") as HTMLElement;

let state = "idle";
let facingRight = false;
let animTime = 0;
let last = 0;
let currentFrame = "idle_0";

// 全局错 / 未捕获 promise → emit 给 Rust 终端(我自主看 webview 错)
window.addEventListener("error", (e: ErrorEvent) =>
  emit("log", "error: " + (e.error?.stack || e.message)));
window.addEventListener("unhandledrejection", (e: PromiseRejectionEvent) =>
  emit("log", "reject: " + (e.reason?.stack || String(e.reason))));

async function main() {
  try {
    await lib.load(localStorage.getItem("kf_theme") || "flat");
    const first = lib.frame("idle_0");
    if (first) img.src = first.img.src;

    behavior.setup({
      lib,
      setState: (s) => { if (s !== state) { state = s; animTime = 0; last = 0; } },
      setFacing: (r) => { facingRight = r; img.style.transform = r ? "scaleX(-1)" : "none"; },
      playPeep: playPeep,
      onMoved: (x: number, y: number) => { updateShadow(x, y); updateHitOrigin(x, y); },   // 同步喂 hittest 缓存(零 IPC)
    });
    setupHitTest(lib, () => currentFrame, 160, () => dragging);
    setupShadow(lib);
    setupPoop();
    setupBranch(lib);
    setupTheme(lib);
    setupAudio();
    setSoundOn(settings.soundOn);
    setupDrag();
    listen<string>("menu", (e) => {
      const id = e.payload;
      if (id === "call") behavior.callOver();
      else if (id === "sing") behavior.doSing();
      else if (id === "eat") behavior.doEat();
      else if (id === "fish") behavior.doFish();
      else if (id === "recall") behavior.recallToScreen();   // 找回小鸟(坐标自愈逃生口)
      else if (id === "diag") collectDiagnostics();   // 诊断信息(写文件+记事本打开,定位坐标问题)
      else if (id === "perch") behavior.doPerch();
      else if (id === "peck") behavior.doPeck();
      else if (id === "show") { behavior.isVisible() ? behavior.fallAway() : behavior.hatchIn(); }   // 显示/隐藏 toggle
      else if (id === "repair") { clearCracks(); }   // 托盘"修复屏幕"
    });
    listen<string>("theme", (e) => setTheme(e.payload));   // 托盘主题菜单 → 切换 + reload
    listen<string>("setting", (e) => {
      const v = e.payload;
      if (v.startsWith("sound:")) { const on = v.split(":")[1] === "true"; setSound(on); setSoundOn(on); }
      else if (v.startsWith("activity:")) { setActivity(Number(v.split(":")[1])); }
      else if (v.startsWith("speed:")) { setSpeed(Number(v.split(":")[1])); }
      syncSettingsOutlets();   // 回推:托盘勾选(Rust ui-state)+ 设置窗滑杆
    });
    listen("settings-open", () => syncSettingsOutlets());   // 设置窗打开/已开 → 推当前真实值
    function syncSettingsOutlets() {
      const snap = { theme: localStorage.getItem("kf_theme") || "flat",
                     activity: settings.activity, speed: settings.speed, sound: settings.soundOn };
      emit("ui-state", snap);
      emit("settings-sync", snap);
    }
    // 启动上报状态 → Rust 菜单勾选反映真实值
    emit("ui-state", { theme: localStorage.getItem("kf_theme") || "flat",
                      activity: settings.activity, speed: settings.speed, sound: settings.soundOn });
    listen("sleep", () => behavior.sleepForUserAbsence());   // Rust 监听到睡眠 → 鸟睡
    listen("wake", () => behavior.wakeFromUserAbsence());     // 唤醒 → 赖床 2–4 秒
    await behavior.start();
    requestAnimationFrame(tick);
    // 跨不同 DPI 显示器:窗口物理尺寸不会自动跟着变(160 物理 ≠ 新屏的 160 逻辑),
    // 而坐标全链按新 scale 算 → 脚位/树枝/钳制整体错位。这里重设为 160 逻辑
    petWin.onScaleChanged(async () => {
      try { await petWin.setSize(new LogicalSize(160, 160)); } catch { /* */ }
    });
    if (import.meta.env.DEV) {
      // 开发模式:启动 8s 自动收集诊断打到终端(坐标/舞台窗问题本机即可复现)
      setTimeout(async () => {
        await collectDiagnostics();
        const { stageError } = await import("./poop");
        const po = await WebviewWindow.getByLabel("poop");
        emit("log", `DEV diag: stage_poop=${po ? "EXISTS" : "NULL"} stageError=${stageError ?? "none"}`);
      }, 8000);
    }
    setupWatchdog();
  } catch (e: any) {
    emit("log", "main err: " + (e?.stack || String(e)));
  }
}

function tick(now?: number) {
  if (behavior.isSleeping()) {   // 睡眠:停 RAF,降为 1Hz 慢轮询(省电;wake 时 RAF 自然恢复)
    last = 0;
    setTimeout(tick, 1000);
    return;
  }
  if (now === undefined) { requestAnimationFrame(tick); return; }   // 1Hz 慢轮询唤醒 RAF
  if (last === 0) last = now;
  animTime += (now - last) / 1000 * settings.speed;   // 帧速受全局动画速度影响(macOS 同款)
  last = now;
  const seq = lib.sequence(state);
  const f = Math.max(1, lib.fps(state));
  const idx = Math.floor(animTime * f) % seq.length;
  const fr = lib.frame(seq[idx]);
  if (fr) {
    currentFrame = seq[idx];
    if (img.src !== fr.img.src) img.src = fr.img.src;
  }
  requestAnimationFrame(tick);
}

// 拖拽:JS 驱动(macOS 同构)。弃用 Tauri 原生 startDragging——那是 Win32 模态
// 移动循环,窗口直接跟鼠标走,我们只能事后追着纠正,永远堵不住出界。
// 这里用 Pointer Events + 指针捕获:每次移动都先钳到允许范围再落位,
// 窗口物理上不可能出界(拖到边界外 = 鸟顶在边界线上,"框住范围")。
// 捕获保证 pointerup 必达(光标离开窗口也不丢),不再需要任何模态循环补丁。
let dragging = false;
let movedDuringDrag = false;                                 // 拖拽中是否真的移动过(判点击)
let dragStartPos: { x: number; y: number } | null = null;   // 按下时窗口位置(判点击/拖拽)
let dragOrigin = { x: 0, y: 0 };   // 窗口当前原点(我们自己设的,物理;每帧滚动更新)
let grabGX = 0, grabGY = 0;        // 按下时 全局光标−窗口原点(物理;拖拽期间保持)
let dragSc = 1;                    // 拖拽期间缩放(本地 CSS → 全局物理)
let dragTickBusy = false;          // 落位在途时跳过本帧(下一帧补上)

function setupDrag() {
  img.draggable = false;
  img.addEventListener("pointerdown", async (e: PointerEvent) => {
    if (e.button !== 0) return;
    e.preventDefault();
    try { img.setPointerCapture(e.pointerId); } catch { /* */ }
    try {
      const p = await petWin.outerPosition();
      const sc = await petWin.scaleFactor();
      const cur = await invoke<[number, number] | null>("cursor_pos_cmd");
      dragSc = sc;
      dragStartPos = { x: p.x, y: p.y };
      dragOrigin = { x: p.x, y: p.y };
      const gx = cur ? cur[0] : p.x + 80 * sc;
      const gy = cur ? cur[1] : p.y + 80 * sc;
      grabGX = gx - p.x; grabGY = gy - p.y;
    } catch { dragStartPos = null; }
    behavior.dragBegin();
    behavior.dragResetCache();
    dragging = true;
    movedDuringDrag = false;
    dragTickBusy = false;
  });
  img.addEventListener("pointermove", async (e: PointerEvent) => {
    if (!dragging || !dragStartPos || dragTickBusy) return;
    dragTickBusy = true;
    try {
      // 全局光标 = 窗口原点(自维护)+ 本地 CSS × 缩放(零 IPC)
      const gx = dragOrigin.x + e.clientX * dragSc;
      const gy = dragOrigin.y + e.clientY * dragSc;
      const t = await behavior.dragMoveTo(gx - grabGX, gy - grabGY);   // 钳制+落位
      dragOrigin = t;
      if (Math.hypot(t.x - dragStartPos.x, t.y - dragStartPos.y) > 3) movedDuringDrag = true;
    } catch { /* */ } finally { dragTickBusy = false; }
  });
  const up = () => { if (dragging) endDrag(); };
  img.addEventListener("pointerup", up);
  img.addEventListener("pointercancel", up);
  window.addEventListener("blur", up);   // 焦点被抢走等极端场景兜底收尾
}

async function endDrag() {
  dragging = false;
  // 点击 vs 拖拽:没移动过 或 位移 <5px(物理)→ 害羞+啾(macOS 同款)
  try {
    if (!movedDuringDrag && dragStartPos) {
      const p = await petWin.outerPosition();
      if (Math.hypot(p.x - dragStartPos.x, p.y - dragStartPos.y) < 5) {
        behavior.happyAction();
        return;
      }
    }
  } catch { /* */ }
  behavior.dragDidEnd();
}

/// 诊断:收集前端可见的坐标/DPI 状态 → Rust 追加进诊断文件
/// (主报告由 Rust 生成并打开记事本;这里每字段独立容错,一处失败不影响其余)
async function collectDiagnostics() {
  const g = async <T>(k: string, f: () => Promise<T>): Promise<any> => {
    try { return await f(); } catch (e: any) { return "ERR: " + String(e); }
  };
  const report: Record<string, any> = { time: new Date().toISOString() };
  report.devicePixelRatio = window.devicePixelRatio;
  report.screen_css = { w: screen.width, h: screen.height };
  report.scaleFactor_api = await g("sf", () => petWin.scaleFactor());
  report.outerPosition = await g("pos", async () => {
    const p = await petWin.outerPosition(); return { x: p.x, y: p.y };
  });
  report.outerSize = await g("size", async () => {
    const s = await petWin.outerSize(); return { w: s.width, h: s.height };
  });
  report.currentMonitor = await g("mon", () => currentMonitor());
  report.availableMonitors = await g("mons", () => availableMonitors());
  report.work_area_cmd = await g("wa", () => invoke("work_area_cmd"));
  report.cursor_pos_cmd = await g("cur", () => invoke("cursor_pos_cmd"));
  report.stage_poop = await g("poop", async () => {
    const po = await WebviewWindow.getByLabel("poop");
    if (!po) return null;
    const p = await po.outerPosition(); const s = await po.outerSize();
    return { pos: { x: p.x, y: p.y }, size: { w: s.width, h: s.height }, scale: await po.scaleFactor() };
  });
  report.stage_poop_error = (await import("./poop")).stageError;   // 创建失败原因(之前静默)
  report.stage_handshaken = (await import("./poop")).stageHandshaken;   // 舞台页面是否在听(页面活着与否)
  report.stage_pong = await g("pong", async () => {   // 实锤探针:发 ping 等 pong(页面渲染/事件链是否通)
    await (await import("./poop")).ensurePoopStage();
    return await new Promise<string>((res) => {
      const un = listen<string>("stage-pong", (e) => { un.then(f => f()); res(e.payload); });
      emit("stage-ping", null);
      setTimeout(() => { un.then(f => f()); res("TIMEOUT"); }, 1500);
    });
  });
  {   // 当前栖的窗口实测矩形(验证"停窗脚位"):鸟脚 Y 应≈窗口上沿
    const h = behavior.getPerchedHwnd();
    report.perched = h == null ? null : await g("perched", () => invoke("window_rect_cmd", { hwndVal: h }));
  }
  report.saved_pos = { x: localStorage.getItem("kf_x"), y: localStorage.getItem("kf_y") };
  try { await invoke("diag_append", { payload: JSON.stringify(report, null, 2) }); }
  catch (e: any) { emit("log", "diag append err: " + String(e)); }
}

/// 看门狗(15s 巡检;macOS watchdog 同款自愈哲学:假设自己会坏)
/// 1) busy 卡死:动作最长 ~9s,>120s 必是卡死 → 熔断复位
/// 2) 心跳丢失:不 busy 且无排程持续 >60s(思考链断了)→ 重排
/// 3) 窗口数熔断:常驻 main/poop/crack(+settings),>8 或出现陌生窗 → 关掉(5min 冷却)
let wdLastAlive = 0;
let wdLeakCooldownUntil = 0;
function setupWatchdog() {
  wdLastAlive = performance.now();
  setInterval(async () => {
    try {
      if (behavior.isSleeping() || !behavior.isVisible()) { wdLastAlive = performance.now(); return; }   // 睡眠/隐藏是正常静止
      const st = behavior.watchdogState();
      if (st.busy && st.busySince && performance.now() - st.busySince > 120_000) {
        emit("log", "watchdog: busy 卡死 >120s,熔断复位");
        behavior.watchdogKick();
        wdLastAlive = performance.now();
        return;
      }
      if (st.busy || st.thinkArmed) {
        wdLastAlive = performance.now();   // 行为链正常运转
      } else if (performance.now() - wdLastAlive > 60_000) {
        emit("log", "watchdog: 思考心跳丢失 >60s,重排");
        behavior.watchdogKick();
        wdLastAlive = performance.now();
      }
      if (performance.now() > wdLeakCooldownUntil) {
        const all: any[] = await WebviewWindow.getAll();
        const legal = new Set(["main", "poop", "crack", "settings"]);
        const stray = all.filter(w => !legal.has(w.label));
        if (all.length > 8 || stray.length > 0) {
          emit("log", `watchdog: 窗口异常(共 ${all.length},陌生 ${stray.length}),关闭泄漏窗`);
          for (const w of stray) { w.close().catch(() => {}); }
          wdLeakCooldownUntil = performance.now() + 300_000;
        }
      }
    } catch { /* */ }
  }, 15000);
}

main();
