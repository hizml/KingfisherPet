// Phase 2 简化:不穿透(鸟 + 透明区都收点击),保证可点/可拖。
// macOS 的逐像素 hitTest 在 Tauri 上要靠 setIgnoreCursorEvents(true, forward) + alpha,
// mac WKWebView 的 forward 不可靠,先关掉穿透让鸟能交互;逐像素穿透后续单独调。

import { getCurrentWindow } from "@tauri-apps/api/window";
import type { SpriteLibrary } from "./sprite";

export function setupHitTest(_lib: SpriteLibrary, _getCurrentFrame: () => string, _size = 160) {
  getCurrentWindow().setIgnoreCursorEvents(false).catch(() => {});
}
