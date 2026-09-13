// 成长系统单测(node --test,零依赖):与 Mac 侧 kf-tests「成长系统」节同一用例口径。
// 测的是 growth.mjs 真实现(growthsvc.ts/behavior.ts 调的同一份源码),不是复制品。
import test from "node:test";
import assert from "node:assert/strict";
import {
  stageOf, affectionChance, growthMenuTitle, feedAllowed, petAllowed, capEffective,
  FEED_COOLDOWN_MS, PET_COOLDOWN_MS, DAILY_CAP, HATCH_RESET_TO,
} from "../src/growth.mjs";

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

test("菜单标题(中英 + 孵化计数后缀;经济重调后孵化不再限满级展示)", () => {
  assert.ok(growthMenuTitle(37, 0, true).includes("相识"));
  assert.ok(growthMenuTitle(37, 0, true).includes("37/100"));
  assert.ok(growthMenuTitle(37, 0, false).includes("37/100"));
  assert.ok(growthMenuTitle(100, 0, true).includes("100/100"));
  assert.ok(growthMenuTitle(100, 2, true).includes("已孵化×2"));
  // 孵化后亲密度回落:任何档位都带计数后缀(状态可见)
  assert.ok(growthMenuTitle(40, 1, true).includes("已孵化×1"));
  assert.ok(growthMenuTitle(40, 1, true).includes("熟悉"));
  assert.ok(!growthMenuTitle(99, 0, true).includes("已孵化"));   // 没孵化过不吃后缀
});

test("喂鱼时钟回拨不锁死(评审 A9 对称)", () => {
  const t0 = 2_000_000;
  assert.equal(feedAllowed(t0, null), true);
  assert.equal(feedAllowed(t0 + 9 * 60_000, t0), false);        // 正向:冷却中
  assert.equal(feedAllowed(t0 - 3600_000, t0), true);           // 回拨(负 interval):不锁,放行
});

test("喂鱼冷却 30 分钟(经济重调,原 10 分钟)", () => {
  assert.equal(FEED_COOLDOWN_MS, 30 * 60_000);
  const t0 = 1_000_000;
  assert.equal(feedAllowed(t0, null), true);          // 首喂
  assert.equal(feedAllowed(t0 + 29 * 60_000, t0), false);   // 29 分钟:拒绝
  assert.equal(feedAllowed(t0 + FEED_COOLDOWN_MS + 1000, t0), true);   // 30min01s:放行
});

test("抚摸(点击)冷却 60 秒(防狂点秒满)", () => {
  assert.equal(PET_COOLDOWN_MS, 60_000);
  const t0 = 1_000_000;
  assert.equal(petAllowed(t0, null), true);
  assert.equal(petAllowed(t0 + 59_000, t0), false);
  assert.equal(petAllowed(t0 + 61_000, t0), true);
  assert.equal(petAllowed(t0 - 3600_000, t0), true);   // 回拨不锁死
});

test("每日获取上限(跨来源合计)", () => {
  assert.equal(capEffective(5, 0), 5);
  assert.equal(capEffective(25, DAILY_CAP - 25), 25);      // 恰好补满
  assert.equal(capEffective(5, DAILY_CAP - 3), 3);         // 只剩 3 可得
  assert.equal(capEffective(5, DAILY_CAP), 0);             // 已满
  assert.equal(capEffective(0, 0), 0);
});

test("孵化回落值=「熟悉」40(彩蛋可重复)", () => {
  assert.equal(HATCH_RESET_TO, 40);
  assert.equal(stageOf(HATCH_RESET_TO), 2);
});
