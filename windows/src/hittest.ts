// 逐像素点击穿透。对应 macOS PetView.hitTest。
// Windows 上 setIgnoreCursorEvents(true) 后 webview 收不到任何 mousemove(Tauri #6164),
// 所以不能靠 mousemove 判断——改为轮询全局光标(Rust GetCursorPos),换算到窗口本地坐标,
// 查当前帧 alpha:透明 → 穿透,实体 → 接收(可点/可拖)。
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
  const POLL_MS = 33;   // ~30fps,足够跟手
  let polling = false;
  setInterval(async () => {
    if (polling) return;
    polling = true;
    try {
      if (isDragging()) { setIgnore(false); return; }   // 拖拽中必须接收鼠标:一旦穿透,Win32 模态移动循环立即终止
      const cur = await invoke<[number, number]>("cursor_pos_cmd");
      if (!cur) { setIgnore(true); return; }
      const pos = await petWin.outerPosition();      // 物理像素
      const scale = await petWin.scaleFactor();
      // 光标物理 → 窗口本地逻辑
      const lx = (cur[0] - pos.x) / scale;
      const ly = (cur[1] - pos.y) / scale;
      if (lx < 0 || ly < 0 || lx >= size || ly >= size) {
        setIgnore(true);   // 光标不在窗口范围 → 穿透
        return;
      }
      const alpha = lib.alphaAt(getCurrentFrame(), lx / size, ly / size);
      setIgnore(alpha < 16);
    } catch { /* dev 非 Windows:cursor_pos_cmd 返回 null → 穿透 */ }
    finally { polling = false; }
  }, POLL_MS);
}
