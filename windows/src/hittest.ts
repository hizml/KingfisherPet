// 逐像素点击穿透。对应 macOS PetView.hitTest。
// Windows 上 setIgnoreCursorEvents(true) 后 webview 收不到任何 mousemove(Tauri #6164),
// 所以不能靠 mousemove 判断——改为轮询全局光标(Rust GetCursorPos),换算到窗口本地坐标,
// 查当前帧 alpha:透明 → 穿透,实体 → 接收(可点/可拖)。
// 性能:每 tick 仅 1 次 IPC(cursor_pos_cmd);窗口位置/缩放缓存,onMoved/onScaleChanged 刷新
// + 1s 安全兜底重取。之前每 33ms 3 次 IPC(~90/s)永远跑,光标远离鸟时纯浪费。
import { getCurrentWindow } from "@tauri-apps/api/window";
import { invoke } from "@tauri-apps/api/core";
import type { SpriteLibrary } from "./sprite";

const petWin = getCurrentWindow();
let ignoring = false;

async function setIgnore(b: boolean) {
  if (b === ignoring) return;
  ignoring = b;
  try { await petWin.setIgnoreCursorEvents(b); } catch { /* */ }
}

export function setupHitTest(lib: SpriteLibrary, getCurrentFrame: () => string, size = 160,
                              isDragging: () => boolean = () => false) {
  setIgnore(true);   // 初始穿透,轮询命中实体再切回
  // 缓存:窗口物理原点 + 缩放(由事件维护,1s 兜底刷新)
  let px = 0, py = 0, sc = 1, cacheAt = 0;
  const refreshCache = async () => {
    try {
      const p = await petWin.outerPosition();
      sc = await petWin.scaleFactor();
      px = p.x; py = p.y; cacheAt = performance.now();
    } catch { /* */ }
  };
  refreshCache();
  petWin.onMoved(() => { refreshCache(); });
  (petWin as any).onScaleChanged?.(() => { refreshCache(); });

  const POLL_MS = 33;   // ~30fps
  let polling = false;
  setInterval(async () => {
    if (polling) return;
    polling = true;
    try {
      if (isDragging()) { setIgnore(false); return; }   // 拖拽中必须接收鼠标:一旦穿透,Win32 模态移动循环立即终止
      if (performance.now() - cacheAt > 1000) await refreshCache();   // 兜底
      const cur = await invoke<[number, number] | null>("cursor_pos_cmd");
      if (!cur) { setIgnore(true); return; }
      const lx = (cur[0] - px) / sc, ly = (cur[1] - py) / sc;
      if (lx < 0 || ly < 0 || lx >= size || ly >= size) { setIgnore(true); return; }   // 光标不在窗口范围
      const alpha = lib.alphaAt(getCurrentFrame(), lx / size, ly / size);
      setIgnore(alpha < 16);
    } catch { /* dev 非 Windows:cursor_pos_cmd 返回 null → 穿透 */ }
    finally { polling = false; }
  }, POLL_MS);
}
