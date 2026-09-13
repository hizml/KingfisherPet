// 局域网小鸟服务层(v1.7.0;macOS LanBirds.swift 对称):开关/昵称/配对(localStorage)/
// 托盘行/事件接行为机。网络层在 Rust lan.rs(mdns-sd+TCP),协议纯函数在 shared.mjs。
import { invoke } from "@tauri-apps/api/core";
import { listen, emit } from "@tauri-apps/api/event";
import { lanCodename, lanVisitAllowed } from "./shared.mjs";

export const lan = {
  get enabled(): boolean { return localStorage.getItem("kf_lan_on") === "1"; },
  set enabled(v: boolean) {
    localStorage.setItem("kf_lan_on", v ? "1" : "0");
    if (v) lan.start(); else { invoke("lan_stop").catch(() => {}); lan.syncTray(); }
  },
  get name(): string {
    let n = localStorage.getItem("kf_lan_name");
    if (!n) { n = lanCodename(); localStorage.setItem("kf_lan_name", n); }
    return n;
  },
  get allowed(): string[] { return JSON.parse(localStorage.getItem("kf_lan_allowed") ?? "[]"); },
  get denied(): string[] { return JSON.parse(localStorage.getItem("kf_lan_denied") ?? "[]"); },
  allowPeer(n: string) {
    if (!lan.allowed.includes(n)) localStorage.setItem("kf_lan_allowed", JSON.stringify([...lan.allowed, n]));
    lan.syncTray();
  },
  denyPeer(n: string) {
    if (!lan.denied.includes(n)) localStorage.setItem("kf_lan_denied", JSON.stringify([...lan.denied, n]));
    lan.syncTray();
  },
  lastVisitKey(n: string) { return `kf_lan_visit_${n}`; },
  visitAllowed(n: string) {
    const last = Number(localStorage.getItem(lan.lastVisitKey(n)));
    return lanVisitAllowed(Date.now(), Number.isFinite(last) ? last : null);
  },
  markVisit(n: string) { localStorage.setItem(lan.lastVisitKey(n), String(Date.now())); },

  async start() {
    try {
      await invoke("lan_start", { name: lan.name, theme: localStorage.getItem("kf_theme") || "flat" });
    } catch (e) { console.error("lan_start", e); }
    lan.syncTray();
  },
  /// 托盘状态行(状态可见纪律;Rust 菜单重建消费)
  async syncTray() {
    const zh = (localStorage.getItem("kf_lang") || "system") === "zh"
      || ((localStorage.getItem("kf_lang") || "system") === "system"
          && (navigator.language || "en").toLowerCase().startsWith("zh"));
    if (!lan.enabled) { await invoke("set_lan_status", { title: null }).catch(() => {}); return; }
    let peers: string[] = [];
    try { peers = await invoke<string[]>("lan_peers"); } catch { /* */ }
    const ok = peers.filter((n) => lan.allowed.includes(n));
    const pending = peers.filter((n) => !lan.allowed.includes(n) && !lan.denied.includes(n));
    let title: string;
    if (ok.length) title = zh ? `🐦 邻居:${ok.join("、")}(在线)` : `🐦 Neighbors: ${ok.join(", ")} (online)`;
    else if (pending.length) title = zh ? `🐦 发现邻居:${pending.join("、")}(设置里配对)` : `🐦 Neighbor found: ${pending.join(", ")}`;
    else title = zh ? "🐦 邻居:暂无(局域网)" : "🐦 Neighbors: none (LAN)";
    await invoke("set_lan_status", { title }).catch(() => {});
  },
  /// 行为机入口(main.ts 事件路由调用)
  async send(kind: "peep" | "visit" | "fish"): Promise<boolean> {
    try { return await invoke<boolean>("lan_send", { kind }); } catch { return false; }
  },
};

/// 事件 → 行为机(behavior 经由全局事件转发,避免循环 import)
export function setupLan() {
  if (lan.enabled) lan.start();
  listen<{ type: string; name: string }>("lan-event", (e) => {
    const { type, name } = e.payload;
    if (type === "peersChanged") { lan.syncTray(); emit("lan-peers-changed", {}).catch(() => {}); return; }
    if (!lan.enabled) return;
    if (type === "peep") {
      if (lan.denied.includes(name)) return;
      emit("lan-behavior", { act: "peep", name }).catch(() => {});
    } else if (type === "visit") {
      if (!lan.allowed.includes(name) || !lan.visitAllowed(name)) return;
      lan.markVisit(name);
      emit("lan-behavior", { act: "visit", name }).catch(() => {});
    } else if (type === "fish") {
      if (!lan.allowed.includes(name)) return;
      emit("lan-behavior", { act: "fish", name }).catch(() => {});
    }
  }).catch(() => {});
}
