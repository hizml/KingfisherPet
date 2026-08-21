// 滚动日志:对齐 macOS kfLog(/tmp/kf_debug.log, 5MB 封顶)的可观测性哲学。
// 前端全部 emit("log") 自动落盘(lib.rs 的监听里调用 kflog),排障不再依赖终端。
use std::io::Write;

const CAP: u64 = 5 * 1024 * 1024;          // 5MB 封顶(Mac 同款)
const KEEP: u64 = 2 * 1024 * 1024;          // 超限时保留的尾部大小

fn log_path() -> std::path::PathBuf {
    let dir = std::env::var("APPDATA")
        .map(|d| std::path::PathBuf::from(d))
        .unwrap_or_else(|_| std::env::temp_dir())
        .join("KingfisherPet");
    let _ = std::fs::create_dir_all(&dir);
    dir.join("kf.log")
}

/// 追加一行(带时间戳);超 5MB 截断保留尾部(节流:每 64 行查一次大小)
pub fn kflog(line: &str) {
    use std::sync::atomic::{AtomicU64, Ordering};
    static WRITES: AtomicU64 = AtomicU64::new(0);
    let path = log_path();
    let n = WRITES.fetch_add(1, Ordering::Relaxed);
    if n % 64 == 0 {
        if let Ok(m) = std::fs::metadata(&path) {
            if m.len() > CAP {
                if let Ok(data) = std::fs::read(&path) {
                    let start = data.len().saturating_sub(KEEP as usize);
                    let _ = std::fs::write(&path, &data[start..]);
                }
            }
        }
    }
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let hh = (ts % 86400) / 3600;
    let mm = (ts % 3600) / 60;
    let ss = ts % 60;
    if let Ok(mut f) = std::fs::OpenOptions::new().append(true).create(true).open(&path) {
        let _ = writeln!(f, "[{hh:02}:{mm:02}:{ss:02}] {line}");
    }
}

/// 日志尾部(诊断报告附带,看最近发生了什么)
pub fn tail(n: usize) -> String {
    match std::fs::read_to_string(log_path()) {
        Ok(s) => {
            let lines: Vec<&str> = s.lines().collect();
            let start = lines.len().saturating_sub(n);
            lines[start..].join("\n")
        }
        Err(_) => String::from("(无日志)"),
    }
}
