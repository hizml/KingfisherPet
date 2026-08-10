// 主题切换:重载 sprite + 刷新页面(简化;精细 reload 各模块 Phase 4 完善)。
import type { SpriteLibrary } from "./sprite";
let lib: SpriteLibrary;
export function setupTheme(s: SpriteLibrary) { lib = s; }
export async function setTheme(theme: string) {
  localStorage.setItem("kf_theme", theme);
  await lib.load(theme);
  location.reload();
}
export const THEMES: Array<[string, string]> = [
  ["flat", "扁平"], ["clay", "粘土"], ["pixel", "像素"],
  ["neon", "霓虹"], ["ink", "水墨"], ["watercolor", "水彩"],
];
