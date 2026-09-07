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

/// UTC→本地偏移秒数(GetTimeZoneInformation;Bias 含 DST 语义:本地 = UTC - (Bias+季节Bias)*60)。
/// 非 Windows(本机 dev)无偏移,退 UTC。
#[cfg(windows)]
fn utc_offset_secs() -> i64 {
    use windows::Win32::System::Time::{GetTimeZoneInformation, TIME_ZONE_INFORMATION};
    // windows 0.61 里 TIME_ZONE_ID_* 常量在 SystemServices(不在 Time)——隔壁会话按记忆写错
    // 模块,mac 上 cfg 门挡住编译不到,windows target 一跑现形(纪律 5 兜底)
    use windows::Win32::System::SystemServices::TIME_ZONE_ID_DAYLIGHT;
    unsafe {
        let mut tz = TIME_ZONE_INFORMATION::default();
        let r = GetTimeZoneInformation(&mut tz);
        // Bias:UTC = 本地 + Bias;夏令时再叠加 DaylightBias,否则 StandardBias
        let seasonal = if r == TIME_ZONE_ID_DAYLIGHT { tz.DaylightBias } else { tz.StandardBias };
        (tz.Bias + seasonal) as i64 * 60
    }
}
#[cfg(not(windows))]
fn utc_offset_secs() -> i64 { 0 }

/// 追加一行(带本地时间戳);超 5MB 截断保留尾部(节流:每 64 行查一次大小)
pub fn kflog(line: &str) {
    use std::sync::atomic::{AtomicU64, Ordering};
    static WRITES: AtomicU64 = AtomicU64::new(0);
    static OFFSET: std::sync::OnceLock<i64> = std::sync::OnceLock::new();
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
    // 本地时间(此前直接用 epoch = UTC,与用户时钟差 8 小时,排障时间线对不上)
    let local = (ts as i64 - *OFFSET.get_or_init(utc_offset_secs)).max(0) as u64;
    let hh = (local % 86400) / 3600;
    let mm = (local % 3600) / 60;
    let ss = local % 60;
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
