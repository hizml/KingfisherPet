// 纯逻辑单测(node --test,零依赖):与 Mac 侧 kf-tests 同一套用例口径
import test from "node:test";
import assert from "node:assert/strict";
import { isNewer } from "../src/shared.mjs";

test("基础比较", () => {
  assert.equal(isNewer("v1.4.64", "1.4.63"), true);
  assert.equal(isNewer("v1.5.0", "1.4.99"), true);
  assert.equal(isNewer("v1.4.63", "1.4.63"), false);
});

test("本地比线上新不误报(N5105 实锤场景)", () => {
  assert.equal(isNewer("v1.4.59", "1.4.63"), false);
  assert.equal(isNewer("v1.4.0", "1.4.63"), false);
});

test("逐段数值非字典序 + 段数不齐", () => {
  assert.equal(isNewer("v1.4.10", "1.4.9"), true);
  assert.equal(isNewer("v2.0", "1.9.9"), true);
});

test("畸形输入保守不更新", () => {
  assert.equal(isNewer("garbage", "1.4.63"), false);
  assert.equal(isNewer("", "1.4.63"), false);
  assert.equal(isNewer(undefined, "1.4.63"), false);
});
