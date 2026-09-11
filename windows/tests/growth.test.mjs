// 成长系统单测(node --test,零依赖):与 Mac 侧 kf-tests「成长系统」节同一用例口径。
// 测的是 growth.mjs 真实现(growth.ts/behavior.ts 调的同一份源码),不是复制品。
import test from "node:test";
import assert from "node:assert/strict";
import { stageOf, affectionChance, growthMenuTitle, feedAllowed, FEED_COOLDOWN_MS } from "../src/growth.mjs";

test("档位换算(边界值逐档)", () => {
  assert.equal(stageOf(19), 0);
  assert.equal(stageOf(20), 1);
  assert.equal(stageOf(39), 1);
  assert.equal(stageOf(40), 2);
  assert.equal(stageOf(59), 2);
  assert.equal(stageOf(60), 3);
  assert.equal(stageOf(79), 3);
  assert.equal(stageOf(80), 4);
  assert.equal(stageOf(99), 4);
  assert.equal(stageOf(100), 5);
});

test("档位换算越界防御", () => {
  assert.equal(stageOf(-1), 0);
  assert.equal(stageOf(999), 5);
});

test("来访概率单调升且 stranger=0 且上限温和", () => {
  const ps = [0, 1, 2, 3, 4, 5].map(affectionChance);
  assert.equal(ps[0], 0);
  for (let i = 1; i < ps.length; i++) assert.ok(ps[i] >= ps[i - 1]);
  assert.ok(ps[5] <= 0.05);
});

test("菜单标题(中英 + 满级孵化后缀)", () => {
  assert.ok(growthMenuTitle(37, false, true).includes("相识"));
  assert.ok(growthMenuTitle(37, false, true).includes("37/100"));
  assert.ok(growthMenuTitle(37, false, false).includes("37/100"));
  assert.ok(growthMenuTitle(100, false, true).includes("100/100"));
  assert.ok(growthMenuTitle(100, true, true).includes("(已孵化)"));
  assert.ok(!growthMenuTitle(99, true, true).includes("已孵化"));   // 未满级不吃孵化后缀
});

test("喂鱼冷却(时刻注入)", () => {
  const t0 = 1_000_000;
  assert.equal(feedAllowed(t0, null), true);          // 首喂
  assert.equal(feedAllowed(t0 + 9 * 60_000, t0), false);   // 9 分钟:拒绝
  assert.equal(feedAllowed(t0 + FEED_COOLDOWN_MS + 1000, t0), true);   // 10min01s:放行
});
