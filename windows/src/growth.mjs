// 成长系统纯函数(v1.5.x batch2;macOS Growth.swift 对称实现——同一公式同一用例口径,
// 任改一处必须同步另一端)。.mjs 让 tests/growth.test.mjs 直打真实现。

/// 档位换算:0–19 陌生/20–39 相识/40–59 熟悉/60–79 亲近/80–99 亲密/100 缘定一生
export function stageOf(intimacy) {
  if (intimacy < 20) return 0;
  if (intimacy < 40) return 1;
  if (intimacy < 60) return 2;
  if (intimacy < 80) return 3;
  if (intimacy < 100) return 4;
  return 5;
}

/// 主动来访概率(think 每拍;亲密度影响互动频率的落点——档位越高越会自己来看你)
export function affectionChance(stage) {
  return [0, 0.004, 0.008, 0.012, 0.018, 0.025][stage] ?? 0;
}

export const STAGE_ZH = ["陌生", "相识", "熟悉", "亲近", "亲密", "缘定一生"];
export const STAGE_EN = ["Stranger", "Acquainted", "Familiar", "Close", "Intimate", "Bonded"];

/// 菜单状态行(zh=false 时英文)
export function growthMenuTitle(intimacy, hatched, zh) {
  const st = stageOf(intimacy);
  if (st === 5) {
    return "❤️ " + (zh ? "缘定一生" + (hatched ? "(已孵化)" : " · 100/100")
                       : "Bonded" + (hatched ? " (hatched)" : " · 100/100"));
  }
  return "❤️ " + (zh ? STAGE_ZH[st] : STAGE_EN[st]) + ` · ${intimacy}/100`;
}

export const FEED_COOLDOWN_MS = 10 * 60 * 1000;

/// 喂鱼冷却判定(纯函数:now/lastAt 毫秒注入可测)。true=可喂
export function feedAllowed(nowMs, lastFeedAtMs) {
  if (lastFeedAtMs == null) return true;
  if (nowMs < lastFeedAtMs) return true;   // 评审 A9:时钟回拨(负 interval)不进冷却,否则回拨多久锁多久
  return nowMs - lastFeedAtMs >= FEED_COOLDOWN_MS;
}
