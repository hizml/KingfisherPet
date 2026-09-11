// 天气归一化单测(node --test,零依赖):与 Mac 侧 kf-tests「天气归一化/天气权重」
// 两节同一用例口径。测的是 weather.mjs / shared.mjs 真实现(behavior/weather.ts 调的
// 同一份源码),不是复制品(版本比较 bug 的教训)。
import test from "node:test";
import assert from "node:assert/strict";
import { mainFromOpenMeteo, mainFromQWeather, tempFlags, weatherFactors, severity, mergeMain } from "../src/weather.mjs";
import { thinkBands } from "../src/shared.mjs";

test("OM WMO 码表逐档", () => {
  for (const c of [0, 1, 2]) assert.equal(mainFromOpenMeteo(c, 0), "sunny");
  assert.equal(mainFromOpenMeteo(3, 0), "overcast");
  for (const c of [45, 48]) assert.equal(mainFromOpenMeteo(c, 0), "fog");
  for (const c of [51, 53, 56, 57, 61, 80]) assert.equal(mainFromOpenMeteo(c, 0), "rainLight");
  for (const c of [55, 63, 65, 66, 67, 81, 82]) assert.equal(mainFromOpenMeteo(c, 0), "rainHeavy");
  for (const c of [95, 96, 99]) assert.equal(mainFromOpenMeteo(c, 0), "thunder");
  for (const c of [71, 77, 85]) assert.equal(mainFromOpenMeteo(c, 0), "snowLight");
  for (const c of [73, 75, 86]) assert.equal(mainFromOpenMeteo(c, 0), "snowHeavy");
  assert.equal(mainFromOpenMeteo(42, 0), null);   // 未知码静默不干预
});

test("OM 风速并档(>10.8 m/s → wind,按恶劣度取更凶)", () => {
  assert.equal(mainFromOpenMeteo(0, 10.9), "wind");
  assert.equal(mainFromOpenMeteo(0, 10.8), "sunny");   // 边界不触发
  assert.equal(mainFromOpenMeteo(95, 30), "thunder");
  assert.equal(mainFromOpenMeteo(63, 20), "rainHeavy");
  assert.equal(mainFromOpenMeteo(3, 15), "wind");
});

test("QW 和风码表逐档(302–304 才是雷阵雨、313 冻雨)", () => {
  for (const c of [...Array(4).keys()].map(i => 100 + i).concat([150, 151, 152, 153])) {
    assert.equal(mainFromQWeather(c, 0), "sunny");
  }
  assert.equal(mainFromQWeather(104, 0), "overcast");
  for (const c of [502, 507, 515]) assert.equal(mainFromQWeather(c, 0), "fog");
  for (const c of [300, 301, 305, 306, 309, 350, 351]) assert.equal(mainFromQWeather(c, 0), "rainLight");
  for (const c of [307, 308, 310, 311, 312, 313, 314, 316, 318]) assert.equal(mainFromQWeather(c, 0), "rainHeavy");
  for (const c of [302, 303, 304]) assert.equal(mainFromQWeather(c, 0), "thunder");
  for (const c of [400, 401, 404, 405, 406, 407, 408, 457]) assert.equal(mainFromQWeather(c, 0), "snowLight");
  for (const c of [402, 403, 409, 410, 456]) assert.equal(mainFromQWeather(c, 0), "snowHeavy");
  assert.equal(mainFromQWeather(399, 0), "rainLight");   // 未知雨保守轻档
  assert.equal(mainFromQWeather(499, 0), "snowLight");   // 未知雪保守轻档
  assert.equal(mainFromQWeather(900, 0), "sunny");
  assert.equal(mainFromQWeather(901, 0), "overcast");
});

test("QW windScale 并档", () => {
  assert.equal(mainFromQWeather(100, 6), "wind");
  assert.equal(mainFromQWeather(100, 5), "sunny");
  assert.equal(mainFromQWeather(304, 9), "thunder");
});

test("温度副档边界", () => {
  assert.deepEqual(tempFlags(33), { hot: true, cold: false });
  assert.equal(tempFlags(32).hot, false);
  assert.deepEqual(tempFlags(4), { hot: false, cold: true });
  assert.equal(tempFlags(5).cold, false);
  assert.deepEqual(tempFlags(null), { hot: false, cold: false });
});

test("恶劣度排序 + 合并", () => {
  assert.ok(severity("thunder") > severity("rainHeavy"));
  assert.ok(severity("rainHeavy") > severity("wind"));
  assert.ok(severity("wind") > severity("snowHeavy"));
  assert.equal(mergeMain("sunny", "wind"), "wind");
  assert.equal(mergeMain(null, "fog"), "fog");
  assert.equal(mergeMain("thunder", "wind"), "thunder");
});

test("权重表(PLAN-B 拍板版)", () => {
  const f0 = weatherFactors("sunny", false, false);
  assert.equal(f0.sun, 1.6); assert.equal(f0.watch, 1.2); assert.equal(f0.overall, 1);
  assert.deepEqual(weatherFactors("overcast", false, false),
    { overall: 1, fly: 1, fish: 1, sing: 1, dart: 1, watch: 1, sun: 1, perch: 1, walk: 1 });
  const f1 = weatherFactors("rainLight", false, false);
  assert.equal(f1.fly, 0.7); assert.equal(f1.fish, 0.7); assert.equal(f1.dart, 0.7); assert.equal(f1.perch, 1.3);
  const f2 = weatherFactors("rainHeavy", false, false);
  assert.equal(f2.fly, 0.3); assert.equal(f2.perch, 1.6);
  const f3 = weatherFactors("thunder", false, false);
  assert.equal(f3.overall, 0.3); assert.equal(f3.fly, 0); assert.equal(f3.fish, 0); assert.equal(f3.dart, 0);
  assert.equal(f3.watch, 1);   // 雷惊探头保留
  const f4 = weatherFactors("snowLight", false, false);
  assert.equal(f4.walk, 0.8); assert.equal(f4.watch, 1.5);
  const f5 = weatherFactors("snowHeavy", false, false);
  assert.equal(f5.fly, 0.4); assert.equal(f5.perch, 1.5); assert.equal(f5.watch, 1.5);
  const f6 = weatherFactors("fog", false, false);
  assert.equal(f6.fly, 0.5); assert.equal(f6.watch, 1.5);
  const f7 = weatherFactors("wind", false, false);
  assert.equal(f7.fly, 0.3); assert.equal(f7.perch, 1.5);
  // 副档叠乘
  const h = weatherFactors("sunny", true, false);
  assert.ok(Math.abs(h.sun - 0.8) < 1e-9); assert.ok(Math.abs(h.fish - 1.2) < 1e-9);
  const c = weatherFactors("sunny", false, true);
  assert.ok(Math.abs(c.sun - 2.56) < 1e-9); assert.ok(Math.abs(c.fly - 0.8) < 1e-9);
});

test("昼夜×天气合成(thinkBands 第三参)", () => {
  const plain = thinkBands(0.5, 12);
  const thunder = thinkBands(0.5, 12, weatherFactors("thunder", false, false));
  assert.ok(Math.abs(thunder.k - plain.k * 0.3) < 1e-9);
  assert.equal(thunder.widths[0], 0);   // fly
  assert.equal(thunder.widths[1], 0);   // fish
  assert.equal(thunder.widths[3], 0);   // dart
  assert.ok(thunder.sleepShare > 50);
  const rain = thinkBands(0.5, 12, weatherFactors("rainLight", false, false));
  assert.ok(Math.abs(rain.widths[0] - 7 * 0.7) < 1e-9);   // fly 带
  assert.ok(Math.abs(rain.widths[7] - 6 * 1.3) < 1e-9);   // perch 带
  const snow = thinkBands(0.5, 12, weatherFactors("snowLight", false, false));
  assert.equal(snow.walkEnd, 19);   // walk×0.8:21→19
  // 守恒(或增益叠加钳 0)
  for (const h of [3, 8, 12, 19, 23]) {
    for (const m of ["sunny", "rainHeavy", "thunder", "snowLight", "wind", "fog"]) {
      const f = weatherFactors(m, m === "sunny", false);
      const p = thinkBands(0.5, h, f);
      const total = p.walkEnd + p.widths.reduce((s, w) => s + w, 0) * p.k + p.sleepShare;
      assert.ok(Math.abs(total - 100) <= 0.01 || (p.sleepShare === 0 && total >= 100),
        `h=${h} m=${m} total=${total}`);
    }
  }
});
