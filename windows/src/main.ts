// 逐帧渲染 + 拖拽(startDragging 原生)+ 行为状态机。日志通过 emit 发 Rust 终端。

import { getCurrentWindow } from "@tauri-apps/api/window";
import { listen, emit } from "@tauri-apps/api/event";
import { SpriteLibrary } from "./sprite";
import { setupHitTest } from "./hittest";
import { setupEffects } from "./effects";
import { setupShadow, updateShadow } from "./shadow";
import { setupPoop } from "./poop";
import { setupCrack } from "./crack";
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
      onMoved: (x, y) => updateShadow(x, y),
    });
    setupHitTest(lib, () => currentFrame, 160);
    setupEffects(lib, effectLayer);
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
  animTime += (now - last) / 1000;
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
function setupDrag() {
  img.draggable = false;
  img.addEventListener("mousedown", (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    emit("log", "mousedown → startDragging");
    behavior.dragBegin();
    petWin.startDragging().catch((err: any) => emit("log", "startDragging err: " + err));
  });
  window.addEventListener("mouseup", () => behavior.dragDidEnd());
}

main();
