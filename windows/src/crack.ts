// 啄屏裂纹:Canvas 随机放射裂(简化 local;全屏裂纹需独立窗,后续)。对应 macOS CrackController。
export function setupCrack() { /* 无状态 */ }
export function crackAt(x: number, y: number) {
  const c = document.createElement("canvas");
  c.width = 160; c.height = 160;
  Object.assign(c.style, { position: "absolute", left: "0", top: "0", pointerEvents: "none" });
  const ctx = c.getContext("2d")!;
  ctx.strokeStyle = "rgba(20,20,20,0.55)";
  ctx.lineWidth = 2; ctx.lineCap = "round";
  for (let i = 0; i < 7; i++) {
    const a = i / 7 * Math.PI * 2 + Math.random() * 0.3;
    ctx.beginPath(); ctx.moveTo(x, y);
    ctx.lineTo(x + Math.cos(a) * (30 + Math.random() * 15), y + Math.sin(a) * (30 + Math.random() * 15));
    ctx.stroke();
  }
  document.body.appendChild(c);
}
export function clearCracks() { document.querySelectorAll("canvas").forEach(c => c.remove()); }
