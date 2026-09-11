// 成长系统服务层(v1.5.x;macOS Growth.swift 对称):亲密度持久化(localStorage)、
// 加分/喂鱼冷却/孵化标记;纯公式在 growth.mjs(tests 直打同一份源码)。
// 亲密度不改 thinkBands 权重带,只经档位概率影响互动频率(macOS 同款纪律)。

import { emit } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { stageOf, affectionChance, growthMenuTitle, feedAllowed } from "./growth.mjs";

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
  get hatched(): boolean { return localStorage.getItem("kf_hatched") === "1"; },
  /// 满级孵化彩蛋未播(Behavior 在 think 里查;触发时机=下一个思考拍)
  get shouldHatch(): boolean { return growth.intimacy >= 100 && !growth.hatched; },
  /// 加分(统一入口)
  add(n: number) { growth.intimacy = growth.intimacy + n; },
  markHatched() { localStorage.setItem("kf_hatched", "1"); growth.syncTray(); },
  /// 喂鱼(10 分钟冷却;true=本次计分并占下冷却)
  feed(nowMs: number = Date.now()): boolean {
    const last = Number(localStorage.getItem("kf_lastfeed"));
    if (!feedAllowed(nowMs, Number.isFinite(last) ? last : null)) return false;
    localStorage.setItem("kf_lastfeed", String(nowMs));
    return true;
  },
  /// 托盘状态行(状态可见纪律;Rust 菜单重建消费)
  syncTray() {
    const zh = (localStorage.getItem("kf_lang") || "system") === "zh"
      || ((localStorage.getItem("kf_lang") || "system") === "system"
          && (navigator.language || "en").toLowerCase().startsWith("zh"));
    invoke("set_growth_status", { title: growthMenuTitle(growth.intimacy, growth.hatched, zh) })
      .catch(() => {});
    emit("growth-changed", { intimacy: growth.intimacy }).catch(() => {});
  },
};
