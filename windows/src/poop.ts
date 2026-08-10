// 屎:poop.png 从鸟屁股下落 + 落地 + 淡出。简化 local(窗内;全屏屎物理需独立窗,后续)。
import type { SpriteLibrary } from "./sprite";
let lib: SpriteLibrary; let layer: HTMLElement;
export function setupPoop(s: SpriteLibrary, l: HTMLElement) { lib = s; layer = l; }
export function dropPoop() {
  const p = document.createElement("img");
  p.src = `${import.meta.env.BASE_URL}Sprites/${lib.theme}/poop.png`;
  Object.assign(p.style, {
    position: "absolute", width: "30px", height: "20px", left: "65px", top: "60px",
    pointerEvents: "none", transition: "top 1s ease-in, opacity 0.5s",
  });
  layer.appendChild(p);
  requestAnimationFrame(() => { p.style.top = "135px"; });      // 下落到窗底
  setTimeout(() => { p.style.opacity = "0"; }, 1100);            // 淡出
  setTimeout(() => p.remove(), 1800);
}
