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
