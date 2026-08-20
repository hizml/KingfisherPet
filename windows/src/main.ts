// 逐帧渲染 + 拖拽(startDragging 原生)+ 行为状态机。日志通过 emit 发 Rust 终端。

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
  emit("log", "reject: " + ((e.reason as any)?.stack || String(e.reason))));

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
    });
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

// 拖拽:Tauri 原生 startDragging(系统跟手,绕开 DPI/坐标坑)
// Windows 上 startDragging 进入 Win32 模态移动循环,webview 常收不到 mouseup
// → 用窗口移动事件停息判定兜底(300ms 不动 = 拖拽结束)
let dragWaiter: ReturnType<typeof setTimeout> | null = null;
let dragging = false;
let movedDuringDrag = false;                                 // 拖拽中是否真的移动过(判点击)
let dragStartPos: { x: number; y: number } | null = null;   // 按下时窗口位置(判点击/拖拽)
let clickFallbackFired = false;                              // 400ms 点击回退已触发(慢启动拖拽自愈用)
function setupDrag() {
  img.draggable = false;
  img.addEventListener("mousedown", async (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    try { const p = await petWin.outerPosition(); dragStartPos = { x: p.x, y: p.y }; } catch { dragStartPos = null; }
    behavior.dragBegin();
    dragging = true;
    movedDuringDrag = false;
    clickFallbackFired = false;
    petWin.startDragging().catch((err: any) => emit("log", "startDragging err: " + err));
    // 兜底 1:纯点击(无移动)时 startDragging 模态可能吃掉 mouseup 且 onMoved 不触发
    // → 400ms 后仍未结束且没动过,按点击收尾,防 busy=true 永久卡死
    setTimeout(() => { if (dragging && !movedDuringDrag) { clickFallbackFired = true; endDrag(); } }, 400);
  });
  window.addEventListener("mouseup", () => { if (dragging) endDrag(); });
  // 兜底 2:窗口移动事件停息 = 松手(mouseup 丢失也能恢复);拖拽中同步地面阴影 + hittest 缓存 + 边界钳制
  petWin.onMoved(async (ev) => {
    const p = ev.payload as { x: number; y: number };   // 事件自带物理坐标(免一次 IPC)
    if (!dragging) {
      // 慢启动拖拽自愈:400ms 回退已按点击收尾,但用户其实还按着并真的拖起来了
      // → 重新进入拖拽态,恢复钳制 + 松手走正常收尾(否则这段拖动完全脱管,能拖出屏)
      if (!clickFallbackFired) return;
      clickFallbackFired = false;
      dragging = true;
      movedDuringDrag = true;
    }
    movedDuringDrag = true;
    if (dragWaiter) clearTimeout(dragWaiter);
    dragWaiter = setTimeout(endDrag, 300);
    try {
      updateShadow(p.x, p.y);      // 物理直传(shadow 内部自己算)
      updateHitOrigin(p.x, p.y);   // hittest 原点缓存同步(模态拖拽不走 setOrigin)
      // 钳制:脚不进任务栏下面、头不彻底出屏顶、横向不出屏(macOS 拖拽 clamp 同款;入参物理)
      behavior.clampDragFrame(p.x, p.y);
    } catch { /* */ }
  });
}
async function endDrag() {
  dragging = false;
  if (dragWaiter) { clearTimeout(dragWaiter); dragWaiter = null; }
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
  report.saved_pos = { x: localStorage.getItem("kf_x"), y: localStorage.getItem("kf_y") };
  try { await invoke("diag_append", { payload: JSON.stringify(report, null, 2) }); }
  catch (e: any) { emit("log", "diag append err: " + String(e)); }
}

main();
