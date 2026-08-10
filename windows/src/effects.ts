// 特效:水花/音符/zzz/太阳。DOM + CSS 动画 + 主题贴图。
// 移植自 macOS Effects.swift(短命透明窗口 → 前端 DOM 元素,播完 remove)。

import type { SpriteLibrary } from "./sprite";

let lib: SpriteLibrary;
let layer: HTMLElement;

export function setupEffects(spriteLib: SpriteLibrary, effectLayer: HTMLElement) {
  lib = spriteLib;
  layer = effectLayer;
}

function imgEl(name: string, w: number, h: number): HTMLImageElement {
  const img = document.createElement("img");
  img.src = `${import.meta.env.BASE_URL}Sprites/${lib.theme}/${name}.png`;
  img.style.position = "absolute";
  img.style.width = w + "px";
  img.style.height = h + "px";
  img.style.pointerEvents = "none";
  return img;
}

/// 水花(俯冲捕鱼入水):ring 放大淡出
export function splash(x: number, y: number) {
  const ring = imgEl("splash_ring", 30, 30);
  ring.style.left = (x - 15) + "px";
  ring.style.top = (y - 15) + "px";
  ring.style.transform = "scale(0.3)";
  ring.style.opacity = "0.9";
  ring.style.transition = "transform 0.55s ease-out, opacity 0.55s ease-out";
  layer.appendChild(ring);
  requestAnimationFrame(() => { ring.style.transform = "scale(3.2)"; ring.style.opacity = "0"; });
  setTimeout(() => ring.remove(), 700);
}

/// 音符(鸣唱):♪ 上浮淡出
export function notes(x: number, y: number) {
  for (let i = 0; i < 3; i++) {
    const n = imgEl("note", 32, 32);
    n.style.left = (x + (i - 1) * 14) + "px";
    n.style.top = y + "px";
    n.style.opacity = "0";
    n.style.transition = `transform 1.2s ease-out ${i * 0.25}s, opacity 1.2s ${i * 0.25}s`;
    layer.appendChild(n);
    requestAnimationFrame(() => { n.style.transform = "translateY(-40px)"; n.style.opacity = "1"; });
    setTimeout(() => { n.style.opacity = "0"; }, 800 + i * 250);
    setTimeout(() => n.remove(), 1700);
  }
}

/// zzz(打盹):z 上浮漂移淡出
export function zzz(x: number, y: number) {
  const z = imgEl("zzz", 28, 28);
  z.style.left = x + "px";
  z.style.top = y + "px";
  z.style.opacity = "0";
  z.style.transition = "transform 1.8s ease-out, opacity 1.8s ease-out";
  layer.appendChild(z);
  requestAnimationFrame(() => { z.style.transform = "translateY(-80px)"; z.style.opacity = "1"; });
  setTimeout(() => { z.style.opacity = "0"; }, 1200);
  setTimeout(() => z.remove(), 1900);
}

/// 太阳(日光浴):rays 旋转 + disk 脉冲,持续 duration 秒
export function sun(x: number, y: number, duration: number) {
  const c = document.createElement("div");
  c.style.position = "absolute";
  c.style.left = (x - 60) + "px";
  c.style.top = (y - 60) + "px";
  c.style.width = "120px";
  c.style.height = "120px";
  c.style.pointerEvents = "none";
  const rays = imgEl("sun_rays", 120, 120);
  rays.style.animation = "kf-sun-rot 14s linear infinite";
  const disk = imgEl("sun_disk", 58, 58);
  disk.style.left = "31px";
  disk.style.top = "31px";
  disk.style.animation = "kf-sun-pulse 1.4s ease-in-out infinite alternate";
  c.appendChild(rays);
  c.appendChild(disk);
  layer.appendChild(c);
  setTimeout(() => c.remove(), duration * 1000);
}
