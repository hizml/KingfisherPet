// Phase 1:透明置顶窗 + 托盘(显示/退出)+ 整体点击穿透
// 对应 macOS 版:PetWindowController(透明窗)+ AppDelegate(菜单栏)

mod windows;
mod system;
mod kflog;

/// 勿扰状态(全屏应用期间):Rust 侧逃生口(找回/显示)也要尊重——鸟绝不盖全屏
pub static DND: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

use tauri::{
    tray::TrayIconBuilder,
    Emitter, Listener, Manager,
};

#[tauri::command]
fn front_perch_cmd(bird_w: f64) -> Option<(f64, f64, isize)> {
    crate::windows::front_perch(bird_w)
}

#[tauri::command]
fn cursor_pos_cmd() -> Option<(f64, f64)> {
    crate::windows::cursor_pos()
}

#[tauri::command]
fn window_at_point_cmd(x: f64, y: f64) -> Option<isize> {
    crate::windows::window_at_point(x, y)
}

#[tauri::command]
fn window_rect_cmd(hwnd_val: isize) -> Option<(f64, f64, f64, f64)> {
    crate::windows::window_rect(hwnd_val)
}

#[tauri::command]
fn surfaces_below_cmd(x: f64) -> Vec<(f64, f64, f64, isize)> {
    crate::windows::surfaces_below(x)
}

#[tauri::command]
fn work_area_cmd(app: tauri::AppHandle) -> Option<(i32, i32, i32, i32)> {
    let w = app.get_webview_window("main")?;
    #[cfg(windows)]
    if let Ok(h) = w.hwnd() {
        return crate::windows::work_area(h.0 as isize);
    }
    #[cfg(not(windows))]
    let _ = w;   // 非 Windows 无工作区查询(前端有兜底)
    None
}

#[tauri::command]
fn stage_visibility(app: tauri::AppHandle, label: String, show: bool) {
    // 舞台窗(poop/crack)隐藏/显示:睡眠时隐藏 → WebView2 停合成/挂起(省电)。
    // 显示必须走 tauri 的 show()(wry 会恢复 WebView2 控制器可见性 = 恢复渲染);
    // 之前只做原生 SetWindowPos(SWP_SHOWWINDOW)——窗口亮了但 wry 还认为它隐藏,
    // 控制器不恢复 → 页面不渲染(能看到窗口投影、内容全无的根因)。
    // show() 会激活抢一次焦点,随后用 NOACTIVATE+TOPMOST 补位(不二次抢)。
    if let Some(w) = app.get_webview_window(&label) {
        if show {
            let _ = w.show();
            crate::windows::show_no_activate(&w);
            let _ = assert_z_cmd(app.clone());   // 置顶后立即收敛:poop(树枝)> main > crack
        } else {
            let _ = w.hide();
        }
    }
}

/// 三窗层级链:鸟(main)最上 → 树枝/阴影/屎舞台(poop)居中 → 裂纹(crack)最下。
/// Windows 置顶段内"谁刚置顶谁在上",任何一次 TOPMOST 断言都会打乱链,
/// 所以显示舞台/找回后统一重排(用户要求:裂纹不得盖住树枝和鸟)。
/// 显示主窗但不激活(不抢用户前台焦点)。Windows 走 SetWindowPos(NOACTIVATE),
/// 其他平台退化为普通 show。
#[tauri::command]
fn show_no_activate(app: tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        crate::windows::show_no_activate(&w);
    }
}

/// 找回小鸟(Rust 直操,不依赖前端):鸟窗移到光标所在屏工作区右下角并显示,
/// 舞台窗(阴影/树枝/屎)一并恢复——之前前端 recall 只救鸟窗不救舞台,
/// 找回后永远没树枝/阴影。最后延迟 emit 让前端复位状态(鸟窗刚恢复时事件会丢)。
fn recall_internal(app: &tauri::AppHandle) {
    use tauri::Emitter;
    if DND.load(std::sync::atomic::Ordering::Relaxed) { crate::kflog::kflog("recall: 勿扰中忽略"); return; }   // 鸟绝不盖全屏
    if let Some(w) = app.get_webview_window("main") {
        let _ = crate::windows::recall_show(&w);
    }
    for label in ["poop", "crack"] {
        if let Some(w) = app.get_webview_window(label) {
            crate::windows::show_no_activate(&w);
        }
    }
    let _ = assert_z_cmd(app.clone());   // 找回后恢复 poop(树枝)> main > crack
    let h = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(400));
        let _ = h.emit("menu", "recall");
    });
}

#[tauri::command]
fn recall_cmd(app: tauri::AppHandle) {
    recall_internal(&app);
}

/// 诊断(主链路,Rust 一手包办,不依赖前端):Win32 实测写报告 + 记事本打开。
/// 前端随后可用 diag_append 追加 webview 侧数据(追加不重开)。
fn diag_run(app: &tauri::AppHandle) {
    let mut rpt = String::new();
    rpt.push_str("=== KingfisherPet 坐标诊断 ===\n");
    rpt.push_str(&format!("version: {}\n", app.package_info().version));   // 版本戳:报告先对版本(两侧分支同款改动,合并留一)
    rpt.push_str(&format!("dpi_awareness(0=unaware/1=system/2=per-monitor): {}\n",
        crate::windows::dpi_awareness()));
    rpt.push_str("monitors[rcMonitor l,t,r,b | rcWork l,t,r,b | dpi](物理):\n");
    for (i, m) in crate::windows::diag_monitors().iter().enumerate() {
        rpt.push_str(&format!("  #{} monitor({},{},{},{}) work({},{},{},{}) dpi={}\n",
            i, m.0, m.1, m.2, m.3, m.4, m.5, m.6, m.7, m.8));
    }
    if let Some(w) = app.get_webview_window("main") {
        if let Some(r) = crate::windows::diag_main_window(&w) {
            rpt.push_str(&format!("main GetWindowRect(l,t,r,b)={} {} {} {} dpi={}\n", r.0, r.1, r.2, r.3, r.4));
        }
        #[cfg(windows)]
        if let Ok(h) = w.hwnd() {
            rpt.push_str(&format!("work_area_cmd(main): {:?}\n", crate::windows::work_area(h.0 as isize)));
        }
        rpt.push_str(&format!("main is_visible: {:?}\n", w.is_visible()));
    }
    if let Some(c) = crate::windows::cursor_pos() {
        rpt.push_str(&format!("cursor(物理): {},{}\n", c.0, c.1));
    }
    let labels: Vec<String> = app.webview_windows().keys().cloned().collect();
    rpt.push_str(&format!("app windows(实际存在): {:?}\n", labels));
    rpt.push_str("\n=== kf.log 尾部(最近 60 行) ===\n");
    rpt.push_str(&kflog::tail(60));

    let dir = std::env::var("APPDATA")
        .map(|d| std::path::PathBuf::from(d))
        .unwrap_or_else(|_| std::env::temp_dir());
    let dir = dir.join("KingfisherPet");
    let _ = std::fs::create_dir_all(&dir);
    let path = dir.join("diagnostics.txt");
    if let Err(e) = std::fs::write(&path, rpt) {
        println!("[diag] 写失败 {}: {}", path.display(), e);
        return;
    }
    println!("[diag] {}", path.display());
    let _ = open::that(&path);
}

/// z 序断言:收敛到 poop(树枝/阴影/屎/特效) > main(鸟) > crack(裂纹)。
/// ⚠️ SetWindowPos(TOPMOST) 每次把窗口提到置顶带【最顶】——调用顺序必须反过来:
/// 先提 crack、再提 main、最后提 poop。之前 main→poop→crack,收敛后 crack 反而
/// 最顶(第二次啄的裂纹盖住鸟——用户报告)。看门狗周期调用。
#[tauri::command]
fn assert_z_cmd(app: tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("crack") {
        crate::windows::raise_no_show(&w);
    }
    if let Some(w) = app.get_webview_window("main") {
        crate::windows::raise_no_show(&w);
    }
    if let Some(w) = app.get_webview_window("poop") {
        crate::windows::raise_no_show(&w);
    }
}

/// 前端诊断数据追加(不重开记事本;主报告由 diag_run 保证落地)
#[tauri::command]
fn diag_append(payload: String) {
    let dir = std::env::var("APPDATA")
        .map(|d| std::path::PathBuf::from(d))
        .unwrap_or_else(|_| std::env::temp_dir());
    let path = dir.join("KingfisherPet").join("diagnostics.txt");
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new().append(true).create(true).open(path) {
        let _ = writeln!(f, "\n=== Webview(JS 收集) ===\n{}\n", payload);
    }
}

/// 界面语言:系统首选语言 zh 开头 → 中文,否则英文。
/// 用 reg.exe 查注册表(纯 std + CommandExt,不依赖 windows crate feature——
/// Win32_Globalization 在 CI 上 feature 门控行为不稳,E0433)。
fn is_zh() -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        use std::process::Command;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        let out = Command::new("reg")
            .args(["query", r"HKCU\Control Panel\International", "/v", "LocaleName"])
            .creation_flags(CREATE_NO_WINDOW)
            .output();
        if let Ok(o) = out {
            return String::from_utf8_lossy(&o.stdout).to_lowercase().contains("zh-");
        }
        false
    }
    #[cfg(not(windows))]
    {
        // dev(mac/linux):看 LANG/LC_ALL
        std::env::var("LANG")
            .or_else(|_| std::env::var("LC_ALL"))
            .map(|v| v.to_lowercase().starts_with("zh"))
            .unwrap_or(false)
    }
}

// UI 状态:托盘勾选/语言的数据源(前端启动时 ui-state 同步,菜单切换时更新)
struct UiState {
    theme: &'static str,
    activity: f64,
    speed: f64,
    sound: bool,
    lang: &'static str,   // system / zh / en
}
static UI: std::sync::Mutex<UiState> = std::sync::Mutex::new(UiState {
    theme: "flat", activity: 0.5, speed: 1.0, sound: true, lang: "system",
});

/// 持久化小设置(Rust 侧目前只存语言;前端数值走 localStorage)
fn prefs_file() -> std::path::PathBuf {
    let dir = std::env::var("APPDATA")
        .map(|d| std::path::PathBuf::from(d))
        .unwrap_or_else(|_| std::env::temp_dir())
        .join("KingfisherPet");
    let _ = std::fs::create_dir_all(&dir);
    dir.join("settings.json")
}
fn prefs_get(key: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(prefs_file()).unwrap_or_default()).ok()?;
    v.get(key)?.as_str().map(|s| s.to_string())
}
fn prefs_set(key: &str, val: &str) {
    let mut v: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(prefs_file()).unwrap_or_default())
        .unwrap_or_else(|_| serde_json::json!({}));
    v[key] = serde_json::json!(val);
    let _ = std::fs::write(prefs_file(), serde_json::to_string(&v).unwrap_or_default());
}

fn ui_lang_zh() -> bool {
    match UI.lock().unwrap().lang {
        "zh" => true,
        "en" => false,
        _ => is_zh(),
    }
}

type MenuResult = tauri::Result<tauri::menu::Menu<tauri::Wry>>;

/// 构建托盘菜单(Mac 同构:动作平铺 + 设置子菜单带勾选)。
fn build_menu(app: &tauri::AppHandle<tauri::Wry>) -> MenuResult {
    use tauri::menu::{Menu, MenuItem, CheckMenuItem, Submenu, IsMenuItem};
    let zh = ui_lang_zh();
    let ui = UI.lock().unwrap();

    let t = |zh_txt: &str, en_txt: &str| -> String { (if zh { zh_txt } else { en_txt }).into() };

    // ── 动作区(平铺,对应 Mac 菜单上半)──
    let call = MenuItem::with_id(app, "call", t("召唤过来", "Call Over"), true, None::<&str>)?;
    let fish = MenuItem::with_id(app, "fish", t("去抓条鱼", "Catch a Fish"), true, None::<&str>)?;
    let sing = MenuItem::with_id(app, "sing", t("唱一个", "Sing"), true, None::<&str>)?;
    let perch = MenuItem::with_id(app, "perch", t("停到窗口上", "Perch on a Window"), true, None::<&str>)?;
    let peck = MenuItem::with_id(app, "peck", t("啄一下", "Peck"), true, None::<&str>)?;
    let show = MenuItem::with_id(app, "show", t("显示 / 隐藏", "Show / Hide"), true, None::<&str>)?;
    let recall = MenuItem::with_id(app, "recall", t("找回小鸟", "Find the Bird"), true, None::<&str>)?;
    let diag = MenuItem::with_id(app, "diag", t("诊断信息", "Diagnostics"), true, None::<&str>)?;
    let repair = MenuItem::with_id(app, "repair", t("修复屏幕", "Repair Screen"), true, None::<&str>)?;

    // ── 高频项放外边(用户指令:使用频率高的放外边,低的收设置窗):
    // 主题(常换着玩)+ 声音开关留在托盘直达;活跃度/速度滑杆、语言、自启在设置窗
    let themes: [(&str, &str, &str); 6] = [
        ("theme_flat", "扁平", "Flat"), ("theme_clay", "粘土", "Clay"),
        ("theme_pixel", "像素", "Pixel"), ("theme_neon", "霓虹", "Neon"),
        ("theme_ink", "水墨", "Ink"), ("theme_watercolor", "水彩", "Watercolor"),
    ];
    let mut theme_items: Vec<Box<dyn IsMenuItem<tauri::Wry>>> = Vec::new();
    for (id, zh_n, en_n) in themes {
        let key = id.trim_start_matches("theme_");
        theme_items.push(Box::new(CheckMenuItem::with_id(app, id, t(zh_n, en_n), true, ui.theme == key, None::<&str>)?));
    }
    let theme_refs: Vec<&dyn IsMenuItem<tauri::Wry>> = theme_items.iter().map(|b| b.as_ref()).collect();
    let m_theme = Submenu::with_id(app, "m_theme", t("主题", "Theme"), true)?;
    m_theme.append_items(&theme_refs)?;
    let sound = CheckMenuItem::with_id(app, "sound", t("啾鸣声", "Chirp"), true, ui.sound, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", t("设置…", "Settings…"), true, None::<&str>)?;
    let about = MenuItem::with_id(app, "about", t("关于 翡", "About Fei"), true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", t("退出 翡", "Quit Fei"), true, None::<&str>)?;

    let menu = Menu::with_items(app, &[
        &call, &fish, &sing, &perch, &peck, &show, &recall, &repair,
    ])?;
    let _ = menu; // 分隔符+设置区需要 append;改用一次性 with_items 全量
    let items: Vec<&dyn IsMenuItem<tauri::Wry>> = vec![
        &call, &fish, &sing, &perch, &peck, &show, &recall, &repair, &diag,
        &m_theme, &sound, &settings, &about, &quit,
    ];
    Menu::with_items(app, &items)
}

/// 重建托盘菜单(切换勾选/语言后)
fn refresh_menu(app: &tauri::AppHandle<tauri::Wry>) {
    if let Some(tray) = app.tray_by_id("main") {
        if let Ok(m) = build_menu(app) {
            let _ = tray.set_menu(Some(m));
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .invoke_handler(tauri::generate_handler![front_perch_cmd, cursor_pos_cmd, window_at_point_cmd, window_rect_cmd, surfaces_below_cmd, show_no_activate, stage_visibility, work_area_cmd, recall_cmd, diag_append, assert_z_cmd])
        .setup(|app| {
            crate::system::setup_power(app.handle().clone());   // 睡眠/锁屏/唤醒 → emit sleep/wake
            // 设置窗主动拉状态(打开时):回语言/自启
            {
                let app2 = app.handle().clone();
                app.listen("settings-need-state", move |_| {
                    let (lang, auto) = {
                        let l = UI.lock().unwrap().lang;
                        use tauri_plugin_autostart::ManagerExt;
                        (l, app2.autolaunch().is_enabled().unwrap_or(false))
                    };
                    use tauri::Emitter;
                    let _ = app2.emit("settings-open", serde_json::json!({ "lang": lang, "autostart": auto }));
                });
            }
            // 设置窗事件:语言切换(持久化+整菜单换语言)/ 开机自启
            {
                let app2 = app.handle().clone();
                app.listen("lang", move |event| {
                    let l = event.payload().trim_matches('"').to_string();
                    if matches!(l.as_str(), "zh" | "en" | "system") {
                        UI.lock().unwrap().lang = Box::leak(l.clone().into_boxed_str());
                        prefs_set("lang", &l);
                        crate::kflog::kflog(&format!("lang → {l}"));
                        refresh_menu(&app2);
                    }
                });
            }
            {
                let app2 = app.handle().clone();
                app.listen("autostart", move |event| {
                    let on = event.payload() == "true";
                    use tauri_plugin_autostart::ManagerExt;
                    let m = app2.autolaunch();
                    let _ = if on { m.enable() } else { m.disable() };
                    crate::kflog::kflog(&format!("autostart → {on}"));
                });
            }
            // Rust 侧看门狗(主窗 WebView 崩死时 JS 看门狗同归于尽,必须在这层兜底):
            // 1) 心跳:主窗每 30s emit("hb");丢失 >120s(且已运行 >3min)→ 重载主窗页面自愈(10min 冷却)
            // 2) 出屏:主窗位置跑出所有显示器 → 找回安全位(跟随未钳制等历史路径的兜底)
            {
                use std::sync::atomic::{AtomicU64, Ordering};
                static LAST_HB: AtomicU64 = AtomicU64::new(0);
                static LAST_HEAL: AtomicU64 = AtomicU64::new(0);
                let app2 = app.handle().clone();
                app.listen("hb", |_| {
                    LAST_HB.store(
                        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs(),
                        Ordering::Relaxed);
                });
                std::thread::spawn(move || {
                    let boot = std::time::Instant::now();
                    loop {
                        std::thread::sleep(std::time::Duration::from_secs(30));
                        let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
                            .map(|d| d.as_secs()).unwrap_or(0);
                        let hb = LAST_HB.load(Ordering::Relaxed);
                        let healed = LAST_HEAL.load(Ordering::Relaxed);
                        // 心跳丢失 → 主窗页面重载(蛋壳重启,好过整只鸟消失)
                        if boot.elapsed().as_secs() > 180 && hb > 0 && now.saturating_sub(hb) > 120
                            && now.saturating_sub(healed) > 600 {
                            crate::kflog::kflog("rust-watchdog: 主窗心跳丢失 >120s,重载主窗页面自愈");
                            LAST_HEAL.store(now, Ordering::Relaxed);
                            if let Some(w) = app2.get_webview_window("main") {
                                let _ = w.eval("location.reload()");
                            }
                            continue;
                        }
                        // 出屏自愈:窗口原点在所有显示器之外 → 拉回光标所在屏安全位
                        if let Some(w) = app2.get_webview_window("main") {
                            if let (Ok(p), Ok(mons)) = (w.outer_position(), app2.available_monitors()) {
                                let inside = mons.iter().any(|m|
                                    p.x >= m.position().x - 40 && p.x <= m.position().x + m.size().width as i32 + 40 &&
                                    p.y >= m.position().y - 40 && p.y <= m.position().y + m.size().height as i32 + 40);
                                if !inside && now.saturating_sub(healed) > 60 {
                                    crate::kflog::kflog(&format!("rust-watchdog: 主窗出屏({},{}) → 找回", p.x, p.y));
                                    LAST_HEAL.store(now, Ordering::Relaxed);
                                    let _ = crate::windows::recall_show(&w);
                                    let _ = app2.emit("menu", "recall");
                                }
                            }
                        }
                    }
                });
            }
            // 前端 log 事件 → 终端 + 滚动日志文件(可观测性:排障不再依赖终端)
            app.listen("log", |event| {
                let line = event.payload().trim_matches('"').to_string();
                println!("[webview] {}", line);
                kflog::kflog(&line);
            });
            // 前端启动同步状态(主题/活跃度/速度/声音)→ 菜单勾选反映真实值
            let state_handle = app.handle().clone();
            app.listen("ui-state", move |event| {
                let app = &state_handle;
                let p: serde_json::Value = serde_json::from_str(event.payload()).unwrap_or_default();
                let mut ui = UI.lock().unwrap();
                if let Some(t) = p.get("theme").and_then(|v| v.as_str()) {
                    ui.theme = match t { "clay" => "clay", "pixel" => "pixel", "neon" => "neon", "ink" => "ink", "watercolor" => "watercolor", _ => "flat" };
                }
                if let Some(v) = p.get("activity").and_then(|v| v.as_f64()) { ui.activity = v; }
                if let Some(v) = p.get("speed").and_then(|v| v.as_f64()) { ui.speed = v; }
                if let Some(v) = p.get("sound").and_then(|v| v.as_bool()) { ui.sound = v; }
                drop(ui);
                refresh_menu(app);
            });

            // 出生定位:窗口创建即放右下角+脚踩任务栏(Rust 直操,不依赖 JS——
            // 窗口默认创建在系统居中位置,JS 定位前会闪在中心,失败则永久留中心)
            if let Some(w) = app.get_webview_window("main") {
                if crate::windows::recall_show(&w).is_some() {
                    crate::kflog::kflog("start: 窗口出生定位右下角(Rust)");
                }
            }
            // 启动恢复持久化的语言(之前重启丢回跟随系统)
            if let Some(l) = prefs_get("lang") {
                if matches!(l.as_str(), "zh" | "en" | "system") {
                    UI.lock().unwrap().lang = Box::leak(l.into_boxed_str());
                }
            }
            // 托盘:子菜单化菜单(勾选当前项),左键直接打开
            let menu = build_menu(app.handle())?;
            let _ = TrayIconBuilder::with_id("main")
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&menu)
                .show_menu_on_left_click(true)   // 左键直接开菜单(Mac 端同款)
                .on_menu_event(|app, event| {
                    let id = event.id.as_ref().to_string();
                    let handle = app.clone();
                    match id.as_str() {
                        "settings" => {
                            // 设置窗(macOS 设置窗口同款:普通小窗带标题栏,常驻复用)
                            match app.get_webview_window("settings") {
                                Some(w) => { let _ = w.show(); let _ = w.set_focus(); }
                                None => {
                                    let zh = ui_lang_zh();
                                    let _ = tauri::WebviewWindowBuilder::new(
                                        app, "settings",
                                        tauri::WebviewUrl::App("settings.html".into()))
                                        .title(if zh { "翡 · 设置" } else { "Fei · Settings" })
                                        .inner_size(300.0, 330.0)
                                        .resizable(false)
                                        .build();
                                }
                            }
                            // 设置窗回推当前值(主窗推行为值;这里补语言/自启)
                            let (lang, auto) = {
                                let l = UI.lock().unwrap().lang;
                                use tauri_plugin_autostart::ManagerExt;
                                (l, app.autolaunch().is_enabled().unwrap_or(false))
                            };
                            let _ = app.emit("settings-open", serde_json::json!({ "lang": lang, "autostart": auto }));
                        }
                        "about" => { let _ = open::that("https://github.com/hizml/KingfisherPet"); }
                        "quit" => app.exit(0),
                        "login" => {
                            use tauri_plugin_autostart::ManagerExt;
                            let m = app.autolaunch();
                            let on = m.is_enabled().unwrap_or(false);
                            let _ = if on { m.disable() } else { m.enable() };
                            refresh_menu(&handle);
                        }
                        "sound" => {
                            let mut ui = UI.lock().unwrap();
                            ui.sound = !ui.sound;
                            let _ = app.emit("setting", format!("sound:{}", ui.sound));
                            drop(ui);
                            refresh_menu(&handle);
                        }
                        "recall" => { recall_internal(&handle); }   // Rust 直操(前端状态废掉也能救回)
                        "diag" => {
                            // 诊断:Rust 一手包办(写报告+开记事本),再通知前端追加 webview 数据
                            diag_run(&handle);
                            let _ = app.emit("menu", "diag");
                        }
                        "show" => {
                            // 鸟窗隐藏时前端收不到事件(或不可靠):先 Rust 侧救回,
                            // 走 recall 链路(移安全位+恢复舞台+延迟复位);可见时正常走前端 toggle
                            if DND.load(std::sync::atomic::Ordering::Relaxed) {
                                crate::kflog::kflog("show: 勿扰中忽略");
                            } else {
                                let hidden = app.get_webview_window("main")
                                    .map(|w| !w.is_visible().unwrap_or(true))
                                    .unwrap_or(false);
                                if hidden { recall_internal(&handle); }
                                else { let _ = app.emit("menu", "show"); }
                            }
                        }
                        _ if id.starts_with("theme_") => {
                            let t = id.trim_start_matches("theme_").to_string();
                            UI.lock().unwrap().theme = Box::leak(t.into_boxed_str());
                            let _ = app.emit("theme", id.trim_start_matches("theme_"));
                            refresh_menu(&handle);
                        }
                        _ if id.starts_with("act_") => {
                            let v = match id.as_str() { "act_low" => 0.2, "act_high" => 0.9, _ => 0.5 };
                            UI.lock().unwrap().activity = v;
                            let _ = app.emit("setting", format!("activity:{}", v));
                            refresh_menu(&handle);
                        }
                        _ if id.starts_with("spd_") => {
                            let v = match id.as_str() { "spd_slow" => 0.7, "spd_fast" => 1.3, _ => 1.0 };
                            UI.lock().unwrap().speed = v;
                            let _ = app.emit("setting", format!("speed:{}", v));
                            refresh_menu(&handle);
                        }
                        _ if id.starts_with("lang_") => {
                            let l = match id.as_str() { "lang_zh" => "zh", "lang_en" => "en", _ => "system" };
                            UI.lock().unwrap().lang = l;
                            prefs_set("lang", l);   // 持久化(macOS UserDefaults 同款:重启不丢)
                            refresh_menu(&handle);   // 整菜单换语言
                        }
                        _ => { let _ = app.emit("menu", id); }
                    }
                })
                .build(app);
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
