// 局域网协议单测(与 Mac kf-tests「局域网协议」同一用例口径)
import test from "node:test";
import assert from "node:assert/strict";
import { lanEncode, lanDecode, LAN_TYPES, lanVisitAllowed, lanCodename as codename } from "../src/shared.mjs";

test("编解码往返 + 换行结尾", () => {
  const s = lanEncode({ t: "PEEP", v: 1, name: "翠鸟-3F2A" });
  assert.ok(s.endsWith("\n"));
  const m = lanDecode(s.trimEnd());
  assert.equal(m.type, "PEEP");
  assert.equal(m.name, "翠鸟-3F2A");
});

test("白名单外/版本不符/坏 JSON/超长 拒绝", () => {
  assert.equal(lanDecode('{"t":"PWN","v":1}'), null);
  assert.equal(lanDecode('{"t":"PEEP","v":2}'), null);
  assert.equal(lanDecode("{oops"), null);
  assert.equal(lanDecode('{"t":"PEEP","v":1,"x":"' + "a".repeat(2000) + '"}'), null);
  assert.equal(lanEncode({ t: "PEEP", v: 1, x: "a".repeat(2000) }), null);
});

test("随机代号格式 翠鸟-XXXX", () => {
  for (let i = 0; i < 30; i++) assert.match(codename(), /^翠鸟-[0-9A-F]{4}$/);
});

test("串门冷却 30 分钟(含时钟回拨不锁死)", () => {
  assert.equal(lanVisitAllowed(1_000_000, null), true);
  assert.equal(lanVisitAllowed(1_000_000 + 29 * 60_000, 1_000_000), false);
  assert.equal(lanVisitAllowed(1_000_000 + 30 * 60_000 + 1, 1_000_000), true);
  assert.equal(lanVisitAllowed(1_000_000 - 3600_000, 1_000_000), true);
});

test("消息类型白名单齐 8 种", () => assert.equal(LAN_TYPES.length, 8));

// ── v1.7.26 串门体验批语义(与 Mac kf-tests 新增用例同口径)──
import { lanVisitCdMin, lanAnswerCdOk, lanVisitorTheme, LAN_THEMES, LAN_ANSWER_COOLDOWN_MS } from "../src/shared.mjs";

test("串门冷却剩余分钟:未串/刚串/中段/过期边界", () => {
  const t0 = 1_000_000;
  assert.equal(lanVisitCdMin(t0, null), 0);                    // 从未串门
  assert.equal(lanVisitCdMin(t0, t0), 30);                     // 刚串:整 30 分
  assert.equal(lanVisitCdMin(t0 + 29 * 60_000 + 1, t0), 1);    // 剩不足 1 分按 1 计
  assert.equal(lanVisitCdMin(t0 + 29 * 60_000 + 1, t0), 1);    // 最后一分钟内按 1 计
  assert.equal(lanVisitCdMin(t0 + 30 * 60_000, t0), 0);        // 整点边界即归零(lanVisitAllowed 用 >=,同一刻放行)
  assert.equal(lanVisitCdMin(t0 + 31 * 60_000, t0), 0);        // 深度过期=0
  assert.equal(lanVisitCdMin(t0, NaN), 0);                     // 脏存储
});

test("对唱应答冷却 10s(安全批防刷线)", () => {
  assert.equal(LAN_ANSWER_COOLDOWN_MS, 10_000);
  const t0 = 5_000_000;
  assert.equal(lanAnswerCdOk(t0, null), true);                  // 首答
  assert.equal(lanAnswerCdOk(t0 + 9_999, t0), false);           // 冷却中
  assert.equal(lanAnswerCdOk(t0 + 10_000, t0), true);           // 整点放行
});

test("访客皮肤回退:六主题放行,未知/恶意回退本机", () => {
  for (const t of LAN_THEMES) assert.equal(lanVisitorTheme(t, "flat"), t);
  assert.equal(lanVisitorTheme("../../../etc", "flat"), "flat");
  assert.equal(lanVisitorTheme("", "ink"), "ink");
  assert.equal(lanVisitorTheme(undefined, "ink"), "ink");
  assert.equal(lanVisitorTheme("FLAT", "ink"), "ink");          // 大小写敏感:不认
});
