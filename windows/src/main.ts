// 逐帧渲染 + 拖拽(startDragging 原生)+ 行为状态机。日志通过 emit 发 Rust 终端。

import { getCurrentWindow } from "@tauri-apps/api/window";
import { listen, emit } from "@tauri-apps/api/event";
import { SpriteLibrary } from "./sprite";
import { setupHitTest } from "./hittest";
import { setupShadow, updateShadow } from "./shadow";
import { setupPoop } from "./poop";
import { setupCrack, clearCracks } from "./crack";
import { setupBranch } from "./branch";
import { setupTheme, setTheme } from "./theme";
import { setupAudio, playPeep, setSoundOn } from "./audio";
import { settings, setSound, setActivity } from "./settings";
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
      onMoved: (x: number, y: number) => updateShadow(x, y),
    });
    setupHitTest(lib, () => currentFrame, 160);
    setupShadow(lib);
    setupPoop();
    setupCrack();
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
      else if (id === "repair") { clearCracks(); }   // 托盘"修复屏幕"
    });
    listen<string>("theme", (e) => setTheme(e.payload));   // 托盘主题菜单 → 切换 + reload
    listen<string>("setting", (e) => {
      const v = e.payload;
      if (v === "sound") { setSound(!settings.soundOn); setSoundOn(settings.soundOn); }
      else if (v.startsWith("activity:")) { setActivity(Number(v.split(":")[1])); }
    });
    listen("sleep", () => behavior.sleepForUserAbsence());   // Rust 监听到睡眠 → 鸟睡
    listen("wake", () => behavior.wakeFromUserAbsence());     // 唤醒 → 赖床 2–4 秒
    await behavior.start();
    requestAnimationFrame(tick);
  } catch (e: any) {
    emit("log", "main err: " + (e?.stack || String(e)));
  }
}

function tick(now: number) {
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
function setupDrag() {
  img.draggable = false;
  img.addEventListener("mousedown", (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    behavior.dragBegin();
    dragging = true;
    petWin.startDragging().catch((err: any) => emit("log", "startDragging err: " + err));
  });
  window.addEventListener("mouseup", () => { if (dragging) endDrag(); });
  // 兜底:窗口移动事件停息 = 松手(mouseup 丢失也能恢复)
  petWin.onMoved(() => {
    if (!dragging) return;
    if (dragWaiter) clearTimeout(dragWaiter);
    dragWaiter = setTimeout(endDrag, 300);
  });
}
function endDrag() {
  dragging = false;
  if (dragWaiter) { clearTimeout(dragWaiter); dragWaiter = null; }
  behavior.dragDidEnd();
}

main();
