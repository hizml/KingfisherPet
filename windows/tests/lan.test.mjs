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
