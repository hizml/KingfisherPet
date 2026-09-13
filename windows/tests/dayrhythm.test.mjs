// 昼夜节律权重带单测(node --test,零依赖):与 Mac 侧 kf-tests「昼夜节律」节同一用例口径。
// 测的是 shared.mjs 真实现(behavior.ts think() 调的同一份),不是复制品。
import test from "node:test";
import assert from "node:assert/strict";
import { dayFactors, thinkBands, napSeconds } from "../src/shared.mjs";

test("白天基准(原归一公式不变)", () => {
  const day = thinkBands(0.5, 12);
  assert.equal(day.idleBand, 11);
  assert.equal(day.walkEnd, 21);
  assert.ok(Math.abs(day.k - 73 / 62) < 1e-9);
  // 带宽和 61(非 62),/62 余量进 sleep 兜底 ≈7.2——原公式原语义
  assert.ok(Math.abs(day.sleepShare - (100 - 21 - 61 * 73 / 62)) < 1e-9);
});

test("深夜:sing/fish/dart 归零 + 整体×0.35 + sleep 放大", () => {
  const day = thinkBands(0.5, 12);
  const deep = thinkBands(0.5, 3);
  assert.deepEqual(deep.widths.slice(1, 4), [0, 0, 0]);
  assert.ok(Math.abs(deep.k - day.k * 0.35) < 1e-9);
  assert.ok(deep.sleepShare > 50);
});

test("清晨晨鸣 sing×1.5", () => {
  const dawn = thinkBands(0.5, 7);
  assert.ok(Math.abs(dawn.widths[2] - 7 * 1.5) < 1e-9);
});

test("黄昏 ×0.85 + 晒夕阳 sun×1.3", () => {
  const day = thinkBands(0.5, 12);
  const dusk = thinkBands(0.5, 19);
  assert.ok(Math.abs(dusk.k - day.k * 0.85) < 1e-9);
  assert.ok(Math.abs(dusk.widths[5] - 7 * 1.3) < 1e-9);
});

test("夜 22–24 ×0.5", () => {
  const day = thinkBands(0.5, 12);
  const n23 = thinkBands(0.5, 23);
  assert.ok(Math.abs(n23.k - day.k * 0.5) < 1e-9);
});

test("边界小时落段", () => {
  assert.equal(dayFactors(5).overall, 0.35);          // 深夜含 5
  assert.equal(dayFactors(6).sing, 1.5);              // 清晨含 6
  assert.equal(dayFactors(8).sing, 1.5);              // 清晨含 8
  assert.deepEqual(dayFactors(9), { overall: 1, sing: 1, fish: 1, dart: 1, sun: 1 });    // 白天含 9
  assert.deepEqual(dayFactors(16), { overall: 1, sing: 1, fish: 1, dart: 1, sun: 1 });   // 白天含 16
  assert.equal(dayFactors(17).overall, 0.85);         // 黄昏含 17
  assert.equal(dayFactors(21).overall, 0.85);         // 黄昏含 21
  assert.equal(dayFactors(22).overall, 0.5);          // 夜含 22
  assert.equal(dayFactors(23).overall, 0.5);          // 夜含 23
});

test("sleep 份额:深夜>夜>黄昏>白天(越夜越困);清晨最精神", () => {
  const seg = (h) => thinkBands(0.5, h).sleepShare;
  assert.ok(seg(3) > seg(23) && seg(23) > seg(19) && seg(19) > seg(12));
  assert.ok(seg(7) < seg(12));
});

test("24h×3 活跃度布局守恒(和=100)", () => {
  for (let h = 0; h <= 23; h++) {
    for (const a of [0.2, 0.5, 0.8]) {
      const p = thinkBands(a, h);
      const total = p.walkEnd + p.widths.reduce((s, w) => s + w, 0) * p.k + p.sleepShare;
      assert.ok(Math.abs(total - 100) <= 0.01, `h=${h} a=${a} total=${total}`);
    }
  }
});

// 打盹时长随昼夜(此前全天 5–9,深夜秒醒后 idle 睁眼发呆像"睁眼睡觉");
// 与 Mac kf-tests「打盹时长随昼夜」同一用例口径
test("打盹时长:白天小盹,越夜越长", () => {
  assert.deepEqual(napSeconds(12), [5, 9]);    // 白天:原行为
  assert.deepEqual(napSeconds(3), [40, 80]);   // 深夜:长睡
  assert.deepEqual(napSeconds(7), [8, 14]);    // 清晨:刚醒小盹
  assert.deepEqual(napSeconds(19), [7, 12]);   // 黄昏
  assert.deepEqual(napSeconds(23), [25, 50]);  // 夜:渐长
  // 时段边界与 dayFactors 对齐
  assert.deepEqual(napSeconds(5), [40, 80]);
  assert.deepEqual(napSeconds(6), [8, 14]);
  assert.deepEqual(napSeconds(17), [7, 12]);
  assert.deepEqual(napSeconds(22), [25, 50]);
});
