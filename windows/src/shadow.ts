// 地面阴影:shadow.png,窗内 local(鸟脚下),跟鸟窗走。简化版(固定 opacity;随高度变淡 Phase 4)。

import type { SpriteLibrary } from "./sprite";

export function setupShadow(lib: SpriteLibrary) {
  const shadow = document.createElement("img");
  shadow.src = `${import.meta.env.BASE_URL}Sprites/${lib.theme}/shadow.png`;
  shadow.style.position = "absolute";
  shadow.style.bottom = "-6px";   // 窗底下方一点(鸟脚下)
  shadow.style.left = "5px";
  shadow.style.width = "150px";
  shadow.style.height = "40px";
  shadow.style.opacity = "0.45";
  shadow.style.pointerEvents = "none";
  document.body.appendChild(shadow);
}
