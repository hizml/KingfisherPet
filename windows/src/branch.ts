// 树枝:branch.png,鸟悬空时脚下托。简化 local(窗底);栖窗/落点判断需 Win32 枚举,后续。
import type { SpriteLibrary } from "./sprite";
let lib: SpriteLibrary; let branch: HTMLImageElement;
export function setupBranch(s: SpriteLibrary) {
  lib = s;
  branch = document.createElement("img");
  Object.assign(branch.style, {
    position: "absolute", width: "160px", height: "60px",
    left: "0px", bottom: "-20px", pointerEvents: "none", display: "none",
  });
  document.body.appendChild(branch);
}
export function showBranch() {
  branch.src = `${import.meta.env.BASE_URL}Sprites/${lib.theme}/branch.png`;
  branch.style.display = "block";
}
export function hideBranch() { branch.style.display = "none"; }
