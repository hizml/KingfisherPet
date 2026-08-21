// 主题切换:原地换装(macOS SpriteLibrary.reload 同款哲学)。
// 不整页 reload——鸟不重新破壳、行为状态保留;帧 URL 随主题路径变化,
// 渲染 tick 下一帧自然换图;阴影/树枝载荷的主题字段同步;
// 舞台窗(poop/crack)监听 "theme" 事件即时换素材。
import type { SpriteLibrary } from "./sprite";
import { setShadowTheme } from "./shadow";
import { setBranchTheme } from "./branch";

let lib: SpriteLibrary;
export function setupTheme(s: SpriteLibrary) { lib = s; }
export async function setTheme(theme: string) {
  localStorage.setItem("kf_theme", theme);
  await lib.load(theme);
  setShadowTheme(theme);
  setBranchTheme(theme);
}
export const THEMES: Array<[string, string]> = [
  ["flat", "扁平"], ["clay", "粘土"], ["pixel", "像素"],
  ["neon", "霓虹"], ["ink", "水墨"], ["watercolor", "水彩"],
];
