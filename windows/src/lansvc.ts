// 局域网小鸟服务层(v1.7.0;macOS LanBirds.swift 对称):开关/昵称/配对(localStorage)/
// 托盘行/事件接行为机。网络层在 Rust lan.rs(mdns-sd+TCP),协议纯函数在 shared.mjs。
import { invoke } from "@tauri-apps/api/core";
import { listen, emit } from "@tauri-apps/api/event";
import { lanCodename, lanVisitAllowed } from "./shared.mjs";

type LanCfgT = { on: boolean; name: string; allowed: string[]; denied: string[]; inbound: string[] };

export const lan = {
  /// v1.7.5:状态唯一权威=Rust prefs lan_cfg(老板实锤 localStorage 随设置窗关闭丢勾);
  /// enabled/allowed 等以 lan_config 命令读写,localStorage 仅作主窗缓存
  cfg: null as LanCfgT | null,
  get enabled(): boolean { return lan.cfg?.on ?? localStorage.getItem("kf_lan_on") === "1"; },
  set enabled(v: boolean) {
    void invoke("lan_config", { on: v, allow: null, deny: null, unallow: null, undeny: null }).then((c) => { lan.cfg = c as never; }).catch(() => {});
    localStorage.setItem("kf_lan_on", v ? "1" : "0");   // 兼容缓存
    if (!v) { invoke("lan_stop").catch(() => {}); }
    lan.syncTray();
  },
  get name(): string {
    const n = lan.cfg?.name || localStorage.getItem("kf_lan_name") || "";
    if (n) return n;
    // 主窗兜底生成的代号必须落盘(此前每次启动当场随机=重启换名,对端看到「新邻居」)
    const c = lanCodename();
    localStorage.setItem("kf_lan_name", c);
    return c;
  },
  get allowed(): string[] { return lan.cfg?.allowed ?? JSON.parse(localStorage.getItem("kf_lan_allowed") ?? "[]"); },
  get denied(): string[] { return lan.cfg?.denied ?? JSON.parse(localStorage.getItem("kf_lan_denied") ?? "[]"); },
  /// 对方端已允许了我(PAIR 消息同步,Rust 持久化)
  get inbound(): string[] { return lan.cfg?.inbound ?? []; },
  allowPeer(n: string) {
    void invoke("lan_config", { on: null, allow: n, deny: null, unallow: null, undeny: null }).then((c) => { lan.cfg = c as never; }).catch(() => {});
    if (!lan.allowed.includes(n)) localStorage.setItem("kf_lan_allowed", JSON.stringify([...lan.allowed, n]));
    lan.syncTray();
  },
  denyPeer(n: string) {
    void invoke("lan_config", { on: null, allow: null, deny: n, unallow: null, undeny: null }).then((c) => { lan.cfg = c as never; }).catch(() => {});
    if (!lan.denied.includes(n)) localStorage.setItem("kf_lan_denied", JSON.stringify([...lan.denied, n]));
    lan.syncTray();
  },
  /// 名单管理:移除「我已允许」(不再通知拒绝,只是取消授权;对端会收到 UNPAIR)
  removePeer(n: string) {
    void invoke("lan_config", { on: null, allow: null, deny: null, unallow: n, undeny: null }).then((c) => { lan.cfg = c as never; }).catch(() => {});
    lan.syncTray();
  },
  /// 双向已配对(我允许了对方 && 对方允许了我)——串门/送鱼的放行条件
  pairReady(peers?: string[]): boolean {
    const online = peers ?? [];
    return online.some((n) => lan.allowed.includes(n) && lan.inbound.includes(n));
  },
  /// 打开设置窗时拉权威配置(勾选/代号/配对名单的唯一真相)
  async loadCfg() {
    try { lan.cfg = await invoke("lan_config", { on: null, allow: null, deny: null, unallow: null, undeny: null }) as never; } catch { /* */ }
    return lan.cfg;
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
      // (菜单态由 syncTray 统一推 on+ready,此处不重复)
    } catch (e) { console.error("lan_start", e); }
    lan.syncTray();
  },
  /// 托盘状态行(状态可见纪律;Rust 菜单重建消费)
  async syncTray() {
    const zh = (localStorage.getItem("kf_lang") || "system") === "zh"
      || ((localStorage.getItem("kf_lang") || "system") === "system"
          && (navigator.language || "en").toLowerCase().startsWith("zh"));
    if (!lan.enabled) {
      await invoke("set_lan_status", { title: null }).catch(() => {});
      await invoke("set_lan_menu", { on: false, ready: false }).catch(() => {});
      return;
    }
    let peers: string[] = [];
    try { peers = await invoke<string[]>("lan_peers"); } catch { /* */ }
    // v1.7.20 修复:此前没有任何前端调用 set_lan_menu → LAN_READY 恒 false → 串门/送鱼永远灰。
    // v1.7.24:cds=每只双向邻居的串门冷却剩余分钟(冷却标到鸟上,老板令)
    const dualAll = peers.filter((n) => lan.allowed.includes(n) && lan.inbound.includes(n));
    const cds: Record<string, number> = {};
    for (const n of dualAll) { const m = lan.visitRemainingMin(n); if (m > 0) cds[n] = m; }
    await invoke("set_lan_menu", { on: true, ready: dualAll.length > 0, cds: JSON.stringify(cds) }).catch(() => {});
    const dual = peers.filter((n) => lan.allowed.includes(n) && lan.inbound.includes(n));
    const half = peers.filter((n) => lan.allowed.includes(n) && !lan.inbound.includes(n));
    const pending = peers.filter((n) => !lan.allowed.includes(n) && !lan.denied.includes(n));
    let title: string;
    if (dual.length) title = zh ? `🐦 邻居:${dual.join("、")}(🤝双向已配对)` : `🐦 Neighbors: ${dual.join(", ")} (paired)`;
    else if (half.length) title = zh ? `🐦 邻居:${half.join("、")}(已允许,等对方确认)` : `🐦 Neighbors: ${half.join(", ")} (awaiting their confirm)`;
    else if (pending.length) title = zh ? `🐦 发现邻居:${pending.join("、")}(设置里配对)` : `🐦 Neighbor found: ${pending.join(", ")}`;
    else title = zh ? "🐦 邻居:暂无(局域网)" : "🐦 Neighbors: none (LAN)";
    await invoke("set_lan_status", { title }).catch(() => {});
  },
  /// 动作反馈(状态可见纪律):托盘状态行临时换成结果文案,5s 后恢复真值
  async flashStatus(text: string) {
    await invoke("set_lan_status", { title: text }).catch(() => {});
    setTimeout(() => { void lan.syncTray(); }, 5000);
  },
  /// 带反馈的动作:先判双向与冷却,再发送;每一步都给托盘文案(老板实锤"点了没反应")
  async act(kind: "visit" | "fish", wantTarget?: string): Promise<void> {
    const zh = (localStorage.getItem("kf_lang") || "system") === "zh"
      || ((localStorage.getItem("kf_lang") || "system") === "system"
          && (navigator.language || "en").toLowerCase().startsWith("zh"));
    let peers: string[] = [];
    try { peers = await invoke<string[]>("lan_peers"); } catch { /* */ }
    let dual = peers.filter((n) => lan.allowed.includes(n) && lan.inbound.includes(n));
    if (wantTarget) { dual = dual.filter((n) => n === wantTarget); }   // 子菜单指定目标(v1.7.22)
    if (!dual.length) {
      const half = peers.filter((n) => lan.allowed.includes(n));
      await lan.flashStatus(zh ? (half.length ? "🐦 串门/送鱼需对方也确认配对(现在是单向)" : "🐦 没有已配对的在线邻居(设置里配对)") : "🐦 Need mutual pairing first");
      return;
    }
    const target = dual[0];
    if (kind === "visit" && !lan.visitAllowed(target)) {
      const min = lan.visitRemainingMin(target);
      await lan.flashStatus(zh ? `🐦 串门冷却中,还剩 ${min} 分钟(每对邻居 30 分钟一次)` : `🐦 Visit cooldown, ${min} min left`);
      return;
    }
    if (kind === "visit") lan.markVisit(target);
    const sentTo = await lan.send(kind, kind === "visit" || kind === "fish" ? target : undefined);
    if (sentTo && kind === "visit") { void import("./behavior").then((b) => { void b.lanVisitDepart(); }); }   // 本鸟飞走
    await lan.flashStatus(sentTo
      ? (zh ? (kind === "visit" ? `🐦 已去 ${sentTo} 家串门(对方屏幕见)` : `🐦 已给 ${sentTo} 送鱼(对方+亲密度)`) : "🐦 Sent")
      : (zh ? "🐦 发送失败(连接断开?)" : "🐦 Send failed"));
  },
  /// 行为机入口(main.ts 事件路由调用)
  /// 点对点纪律(v1.7.21):visit/fish 指定收件人;peep 广播(环境音)。
  /// 返回收件人名(送达)/null(没送出)
  async send(kind: "peep" | "visit" | "fish", target?: string): Promise<string | null> {
    try { return await invoke<string | null>("lan_send", { kind, target: target ?? null }); } catch { return null; }
  },
  /// 串门冷却剩余分钟(0=可串)
  visitRemainingMin(n: string): number {
    const last = Number(localStorage.getItem(lan.lastVisitKey(n)));
    if (!Number.isFinite(last) || last <= 0) return 0;
    return Math.max(1, Math.ceil((last + 30 * 60_000 - Date.now()) / 60_000));
  },
};

const peepAnswerAt: Record<string, number> = {};   // 对唱应答冷却(每邻居 10s:恶意刷叫防线的轻量修法)
const zh2 = () => (localStorage.getItem("kf_lang") || "system") === "zh"
  || ((localStorage.getItem("kf_lang") || "system") === "system"
      && (navigator.language || "en").toLowerCase().startsWith("zh"));

/// 事件 → 行为机(behavior 经由全局事件转发,避免循环 import)。
/// v1.7.18:先拉 Rust 权威 cfg 再判启停——此前凭隔离 localStorage 缓存直接 start,
/// 设置窗关掉 LAN 后主窗重启会用陈旧缓存复活服务
export function setupLan() {
  void lan.loadCfg().then(() => {
    if (lan.enabled) void lan.start();
    else lan.syncTray();   // 关着也推一次状态(清托盘行)
  });
  listen<{ type: string; name: string }>("lan-event", (e) => {
    const { type, name } = e.payload;
    if (type === "peersChanged") { void lan.loadCfg().then(() => lan.syncTray()); emit("lan-peers-changed", {}).catch(() => {}); return; }
    if (type === "pair") { void lan.loadCfg().then(() => lan.syncTray()); emit("lan-peers-changed", {}).catch(() => {}); return; }
    if (!lan.enabled) return;
    if (type === "peep") {
      if (lan.denied.includes(name)) return;
      const now = Date.now();
      if (peepAnswerAt[name] && now - peepAnswerAt[name] < 10_000) return;   // 冷却中的对唱不答(防刷)
      peepAnswerAt[name] = now;
      emit("log", `lan: 邻居对唱 ${name}`);
      emit("lan-behavior", { act: "peep", name }).catch(() => {});
    } else if (type === "visit") {
      // 冷却只由发送端守(每对一个钟,发送方记);接收端曾双重拦截=老板实锤"没鸟飞过去"
      if (!lan.allowed.includes(name)) return;
      emit("lan-behavior", { act: "visit", name }).catch(() => {});
      void lan.flashStatus(zh2() ? `🐦 ${name} 来串门了(它在你屏幕上)` : `🐦 ${name} is visiting your screen`);
    } else if (type === "fish") {
      if (!lan.allowed.includes(name)) return;
      emit("lan-behavior", { act: "fish", name }).catch(() => {});
      void lan.flashStatus(zh2() ? `🐦 收到 ${name} 送的鱼(亲密度+2)` : `🐦 Fish from ${name} (+2 bonding)`);
    }
  }).catch(() => {});
}
