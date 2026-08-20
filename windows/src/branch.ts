// 树枝:branch.png,鸟悬空时脚下托。渲染在 poop 全屏舞台窗(屏幕坐标)——
// 在鸟窗里画不了"预显"(窗口还在旧位置)且会被 160px 裁剪。
// 对应 macOS BranchController.showAt:飞往悬空落点时树枝先到。
import { emit } from "@tauri-apps/api/event";
import { ensurePoopStage } from "./poop";
import { warnOnce } from "./log";

let theme = localStorage.getItem("kf_theme") || "flat";   // 主题切换走 reload,启动时读持久化值

async function branchEvt(show: boolean, x = 0, y = 0) {
  try {
    await ensurePoopStage();
    await emit("branch", { show, x, y, theme });
  } catch (e) { warnOnce("branch", e); }
}

export function setupBranch(_lib: unknown) {
  // 树枝不再画在鸟窗内;主题由 setBranchTheme 跟踪
}

export function setBranchTheme(t: string) { theme = t; }

/// 在(屏幕物理坐标)脚点显示树枝——起飞前调 = 树枝先到
export function showBranchAt(screenX: number, feetY: number) { branchEvt(true, screenX, feetY); }
export function hideBranch() { branchEvt(false); }
