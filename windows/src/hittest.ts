// 逐像素点击穿透。对应 macOS PetView.hitTest。
// Windows 上 setIgnoreCursorEvents(true) 后 webview 收不到任何 mousemove(Tauri #6164),
// 所以不能靠 mousemove 判断——改为轮询全局光标(Rust GetCursorPos),换算到窗口本地坐标,
// 查当前帧 alpha:透明 → 穿透,实体 → 接收(可点/可拖)。
//
// IPC 减肥:窗口原点/缩放走【同步缓存】,由 behavior.onMoved(每次 setOrigin)和
// 拖拽 onMoved 喂进来 + 2s 慢速兜底刷新。之前每跳 3 次 IPC(cursor+outerPosition+
// scaleFactor ≈ 90 IPC/s 常驻,睡眠也不停)——现在常态 1 次/33ms,睡眠/隐藏归零。
import { getCurrentWindow } from "@tauri-apps/api/window";
import { invoke } from "@tauri-apps/api/core";
import type { SpriteLibrary } from "./sprite";
import { isSleeping } from "./behavior";

const petWin = getCurrentWindow();
let ignoring = false;

async function setIgnore(b: boolean) {
  if (b === ignoring) return;
  ignoring = b;
  try { await petWin.setIgnoreCursorEvents(b); } catch { /* */ }
}

// 缓存:窗口物理原点 + 缩放(behavior/拖拽喂,2s 兜底刷)
let ox = 0, oy = 0, sc = 1;
let sizeLogical = 160;
export function updateHitOrigin(x: number, y: number) { ox = x; oy = y; }

async function refreshGeom() {
  try {
    const p = await petWin.outerPosition();
    const s = await petWin.scaleFactor();
    ox = p.x; oy = p.y; sc = s;
  } catch { /* */ }
}

export function setupHitTest(lib: SpriteLibrary, getCurrentFrame: () => string, size = 160,
                              isDragging: () => boolean = () => false) {
  sizeLogical = size;
  setIgnore(true);   // 初始穿透,轮询命中实体再切回
  refreshGeom();
  petWin.onScaleChanged(() => { refreshGeom(); });   // 拖到不同 DPI 的屏 → 重取
  setInterval(refreshGeom, 2000);   // 兜底:漏喂路径(系统移动窗口等)不致永久错位
  const POLL_MS = 33;   // ~30fps,足够跟手
  let polling = false;
  setInterval(async () => {
    if (polling) return;
    if (isSleeping() || document.hidden) { setIgnore(true); return; }   // 睡眠/隐藏:零 IPC,纯穿透
    polling = true;
    try {
      if (isDragging()) { setIgnore(false); return; }   // 拖拽中必须接收鼠标:一旦穿透,Win32 模态移动循环立即终止
      const cur = await invoke<[number, number] | null>("cursor_pos_cmd");
      if (!cur) { setIgnore(true); return; }
      // 光标物理 → 窗口本地逻辑(全本地算,无 IPC)
      const lx = (cur[0] - ox) / sc;
      const ly = (cur[1] - oy) / sc;
      if (lx < 0 || ly < 0 || lx >= sizeLogical || ly >= sizeLogical) {
        setIgnore(true);   // 光标不在窗口范围 → 穿透
        return;
      }
      const alpha = lib.alphaAt(getCurrentFrame(), lx / sizeLogical, ly / sizeLogical);
      setIgnore(alpha < 16);
    } catch { /* dev 非 Windows:cursor_pos_cmd 返回 null → 穿透 */ }
    finally { polling = false; }
  }, POLL_MS);
}
