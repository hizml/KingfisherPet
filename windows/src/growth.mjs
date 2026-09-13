// 成长系统纯函数(v1.5.x batch2;macOS Growth.swift 对称实现——同一公式同一用例口径,
// 任改一处必须同步另一端)。.mjs 让 tests/growth.test.mjs 直打真实现。
// 2026-09-13 经济重调(老板实测"几小时就满"):点击 +1/60s 冷却、喂鱼 +5/30min、
// 召唤 +1、自发捕鱼 +1,每日获取上限 30(≈3–4 天满);孵化可重复(回落「熟悉」40)。

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

/// 菜单状态行(zh=false 时英文);hatchCount>0 时尾缀已孵化次数(孵化后亲密度回落,档位行正常)
export function growthMenuTitle(intimacy, hatchCount, zh) {
  const st = stageOf(intimacy);
  const suffix = hatchCount > 0 ? (zh ? `(已孵化×${hatchCount})` : ` (hatched ×${hatchCount})`) : "";
  if (st === 5) return "❤️ " + (zh ? "缘定一生" : "Bonded") + (suffix || " · 100/100");
  return "❤️ " + (zh ? STAGE_ZH[st] : STAGE_EN[st]) + ` · ${intimacy}/100` + (suffix ? " " + suffix : "");
}

export const FEED_COOLDOWN_MS = 30 * 60 * 1000;   // 喂鱼冷却 30 分钟【可调】(原 10 分钟太快)
export const FEED_GAIN = 5;                        // 喂鱼 +5(原 +8)
export const PET_COOLDOWN_MS = 60 * 1000;          // 抚摸(点击)冷却 60 秒【可调】(防狂点秒满)
export const DAILY_CAP = 30;                       // 每日获取上限(所有来源合计)【可调】
export const HATCH_RESET_TO = 40;                  // 孵化后亲密度回落「熟悉」

/// 喂鱼冷却判定(纯函数:now/lastAt 毫秒注入可测)。true=可喂
export function feedAllowed(nowMs, lastFeedAtMs) {
  if (lastFeedAtMs == null) return true;
  if (nowMs < lastFeedAtMs) return true;   // 评审 A9:时钟回拨(负 interval)不进冷却,否则回拨多久锁多久
  return nowMs - lastFeedAtMs >= FEED_COOLDOWN_MS;
}

/// 抚摸冷却判定(同款注入可测)。true=本次点击计分
export function petAllowed(nowMs, lastPetAtMs) {
  if (lastPetAtMs == null) return true;
  if (nowMs < lastPetAtMs) return true;
  return nowMs - lastPetAtMs >= PET_COOLDOWN_MS;
}

/// 每日上限生效分(纯函数):当日已得 dayGain,本次申请 n → 实际生效(0=今日已满)
export function capEffective(n, dayGain) {
  if (n <= 0) return 0;
  return Math.min(n, Math.max(0, DAILY_CAP - dayGain));
}
