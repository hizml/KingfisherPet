// 统一错误留痕:每个 key 只报第一次(既不刷屏,也不再有"永远沉默"的失败)。
// 之前 catch 全静默,舞台窗创建失败这类致命错连一行日志都没有——蒙了四轮的教训。
import { emit } from "@tauri-apps/api/event";

const said = new Set<string>();
export function warnOnce(key: string, e: unknown) {
  if (said.has(key)) return;
  said.add(key);
  const msg = e instanceof Error ? (e.stack || e.message) : String(e);
  console.warn("[kf]", key, msg);
  emit("log", `${key}: ${msg}`).catch(() => {});
}
