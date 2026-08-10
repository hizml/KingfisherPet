// Phase 1 最小骨架:加载 flat 主题,idle 逐帧循环(对应 macOS 版 PetView 的 tick/applyFrame)
// 后续 Phase 在此扩展行为状态机、移动、栖窗、特效。

import { SpriteLibrary } from "./sprite";

const lib = new SpriteLibrary();
const img = document.getElementById("sprite") as HTMLImageElement;

let state = "idle";
let animTime = 0;
let last = 0;

async function main() {
  await lib.load("flat");
  const first = lib.frame("idle_0");
  if (first) img.src = first.src;
  requestAnimationFrame(tick);
}

function tick(now: number) {
  if (last === 0) last = now;
  animTime += (now - last) / 1000;
  last = now;
  const seq = lib.sequence(state);
  const f = Math.max(1, lib.fps(state));
  const idx = Math.floor(animTime * f) % seq.length;
  const fr = lib.frame(seq[idx]);
  if (fr && img.src !== fr.src) img.src = fr.src;
  requestAnimationFrame(tick);
}

main();
