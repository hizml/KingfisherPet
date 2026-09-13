// 成长系统服务层(v1.5.x;macOS Growth.swift 对称):亲密度持久化(localStorage)、
// 加分/每日上限/抚摸与喂鱼冷却/孵化计数。纯公式在 growth.mjs(tests 直打同一份源码)。
// 亲密度不改 thinkBands 权重带,只经档位概率影响互动频率(macOS 同款纪律)。
// 2026-09-13 经济重调:孵化可重复(计数+回落「熟悉」),详见 growth.mjs 头注。

import { emit } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import {
  stageOf, affectionChance, growthMenuTitle, feedAllowed, petAllowed, capEffective,
  FEED_GAIN, HATCH_RESET_TO,
} from "./growth.mjs";

function dayStamp(d: Date = new Date()): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export const growth = {
  get intimacy(): number {
    const n = Number(localStorage.getItem("kf_intimacy"));
    return Number.isFinite(n) ? Math.min(100, Math.max(0, Math.trunc(n))) : 0;
  },
  set intimacy(v: number) {
    const c = Math.min(100, Math.max(0, Math.trunc(v)));
    if (c === growth.intimacy) return;
    localStorage.setItem("kf_intimacy", String(c));
    growth.syncTray();
  },
  get stage(): number { return stageOf(growth.intimacy); },
  get affectionChance(): number { return affectionChance(growth.stage); },
  /// 孵化次数(可重复彩蛋;旧一次性标志迁移)
  get hatchCount(): number {
    const n = Number(localStorage.getItem("kf_hatchcount"));
    if (Number.isFinite(n) && n >= 0) return Math.trunc(n);
    return localStorage.getItem("kf_hatched") === "1" ? 1 : 0;
  },
  /// 满级孵化待演(Behavior 在 think 里查;孵化后回落,自然转 false)
  get shouldHatch(): boolean { return growth.intimacy >= 100; },
  /// 加分(统一入口;每日获取上限,超出不生效。bypassDailyCap=开发测试用)
  add(n: number, bypassDailyCap = false) {
    let effective = n;
    if (!bypassDailyCap) {
      growth.rollDay();
      effective = capEffective(n, growth.dayGain);
      localStorage.setItem("kf_daygain", String(growth.dayGain + effective));
    }
    if (effective <= 0) return;
    growth.intimacy = growth.intimacy + effective;
  },
  /// 孵化结算:计数 +1、亲密度回落「熟悉」(macOS 同款,彩蛋可重复)
  markHatched() {
    localStorage.setItem("kf_hatchcount", String(growth.hatchCount + 1));
    growth.intimacy = HATCH_RESET_TO;
    growth.syncTray();
  },
  /// 每日获取(自然日滚动)
  get dayGain(): number {
    const n = Number(localStorage.getItem("kf_daygain"));
    return Number.isFinite(n) && n > 0 ? Math.trunc(n) : 0;
  },
  rollDay(d: Date = new Date()) {
    const today = dayStamp(d);
    if (localStorage.getItem("kf_daystamp") !== today) {
      localStorage.setItem("kf_daystamp", today);
      localStorage.setItem("kf_daygain", "0");
    }
  },
  /// 喂鱼(30 分钟冷却;true=本次计分并占下冷却)
  feed(nowMs: number = Date.now()): boolean {
    const last = Number(localStorage.getItem("kf_lastfeed"));
    if (!feedAllowed(nowMs, Number.isFinite(last) ? last : null)) return false;
    localStorage.setItem("kf_lastfeed", String(nowMs));
    return true;
  },
  /// 抚摸(点击,60 秒冷却;true=本次计分并占下冷却)
  pet(nowMs: number = Date.now()): boolean {
    const last = Number(localStorage.getItem("kf_lastpet"));
    if (!petAllowed(nowMs, Number.isFinite(last) ? last : null)) return false;
    localStorage.setItem("kf_lastpet", String(nowMs));
    return true;
  },
  get feedGain(): number { return FEED_GAIN; },
  /// 托盘状态行(状态可见纪律;Rust 菜单重建消费)
  syncTray() {
    const zh = (localStorage.getItem("kf_lang") || "system") === "zh"
      || ((localStorage.getItem("kf_lang") || "system") === "system"
          && (navigator.language || "en").toLowerCase().startsWith("zh"));
    invoke("set_growth_status", { title: growthMenuTitle(growth.intimacy, growth.hatchCount, zh) })
      .catch(() => {});
    emit("growth-changed", { intimacy: growth.intimacy }).catch(() => {});
  },
};
