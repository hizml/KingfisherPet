// 主题切换:重载 sprite + 刷新页面(简化;精细 reload 各模块 Phase 4 完善)。
import type { SpriteLibrary } from "./sprite";
let lib: SpriteLibrary;
export function setupTheme(s: SpriteLibrary) { lib = s; }
export async function setTheme(theme: string) {
  await lib.load(theme);
  location.reload();   // 重 load 帧缓存 + 重建 effects/shadow/crack(最简单可靠)
}
export const THEMES: Array<[string, string]> = [
  ["flat", "扁平"], ["clay", "粘土"], ["pixel", "像素"],
  ["neon", "霓虹"], ["ink", "水墨"], ["watercolor", "水彩"],
];
