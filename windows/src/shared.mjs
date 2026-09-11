// 跨端纯函数(isNewer 的 Windows 侧实现)。.mjs 让 node --test 可直接 import 同一份源码
// ——测试必须打真实现,不是复制品(版本比较 bug 的教训:副本绿了,真码还错着)。

/// semver 比较:tag(vX.Y.Z)是否比 cur 新(逐段数值,前 4 段;解析失败保守判 false)。
/// 历史教训:此前是严格不等(latest !== "v"+cur)——本地比线上新(装 draft/线上回滚)
/// 会误报「发现新版本」(N5105 实机实锤:装 1.4.63、线上 v1.4.59 仍提示)。
export function isNewer(tag, cur) {
  const p = (s) => String(s).replace(/^v/, "").split(".").slice(0, 4).map((n) => parseInt(n, 10) || 0);
  const a = p(tag), b = p(cur);
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const x = a[i] ?? 0, y = b[i] ?? 0;
    if (x !== y) return x > y;
  }
  return false;
}

/// 昼夜节律分段系数(v1.5.0 A;macOS DayRhythm.swift 对称实现,同一公式同一用例口径,
/// 任改一处必须同步另一端):深夜 0–6 ×0.35 且 sing/fish/dart=0 / 清晨 6–9 晨鸣×1.5 /
/// 白天 9–17 基准 / 黄昏 17–22 ×0.85 且 sun×1.3 / 夜 22–24 ×0.5。
export function dayFactors(hour) {
  const f = { overall: 1, sing: 1, fish: 1, dart: 1, sun: 1 };
  if (hour >= 0 && hour < 6) { f.overall = 0.35; f.sing = 0; f.fish = 0; f.dart = 0; }
  else if (hour >= 6 && hour < 9) { f.sing = 1.5; }
  else if (hour >= 17 && hour < 22) { f.overall = 0.85; f.sun = 1.3; }
  else if (hour >= 22 && hour < 24) { f.overall = 0.5; }
  return f;
}

/// think() 权重带布局(活跃度 × 昼夜节律;原公式从 behavior.ts 收拢于此,
/// tests 直打真实现——测试必须打真实现,不是复制品)。
/// widths 顺序(未乘 k):fly/fish/sing/dart/watch/sun/peck/perch/poop;
/// sleepShare = 兜底份额(overall<1 时动作带变窄、余量自然落进 sleep,越夜越大,
/// "超界进 sleep"语义不变)。
/// wx:天气权重(weather.mjs weatherFactors 产物,普通对象;缺省 = 不干预)。
/// 昼夜 × 天气双层在唯一合成点相乘(macOS DayRhythm.thinkBands(activity:hour:weather:) 同构)。
export function thinkBands(activity, hour, wx) {
  const f = dayFactors(hour);
  const w = Object.assign({ overall: 1, fly: 1, fish: 1, sing: 1, dart: 1, watch: 1, sun: 1, perch: 1, walk: 1 }, wx);
  const a = Math.min(1, Math.max(0, activity));
  const idleBand = Math.round((1 - a) * 22);
  const walkEnd = idleBand + Math.max(1, Math.round(Math.round((1 - a) * 20) * w.walk));
  const k = Math.max(0.5, (100 - walkEnd - 6) / 62) * f.overall * w.overall;
  const mul = [w.fly, f.fish * w.fish, f.sing * w.sing, f.dart * w.dart, w.watch, f.sun * w.sun, 1, w.perch, 1];
  const widths = [7, 8, 7, 7, 7, 7, 6, 6, 6].map((w2, i) => w2 * mul[i]);
  const sleepShare = Math.max(0, 100 - walkEnd - widths.reduce((s, w2) => s + w2, 0) * k);
  return { idleBand, walkEnd, k, widths, sleepShare };
}
