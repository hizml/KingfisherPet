// Phase 1:透明置顶窗 + 托盘(显示/退出)+ 整体点击穿透
// 对应 macOS 版:PetWindowController(透明窗)+ AppDelegate(菜单栏)

mod windows;
mod system;

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
fn window_rect_cmd(hwnd_val: isize) -> Option<(f64, f64, f64, f64)> {
    crate::windows::window_rect(hwnd_val)
}

#[tauri::command]
fn surfaces_below_cmd(x: f64) -> Vec<(f64, f64, f64, isize)> {
    crate::windows::surfaces_below(x)
}

#[tauri::command]
fn work_area_cmd(app: tauri::AppHandle) -> Option<(i32, i32, i32, i32)> {
    use tauri::Manager;
    if let Some(w) = app.get_webview_window("main") {
        #[cfg(windows)]
        if let Ok(h) = w.hwnd() {
            return crate::windows::work_area(h.0 as isize);
        }
    }
    None
}

#[tauri::command]
fn stage_visibility(app: tauri::AppHandle, label: String, show: bool) {
    // 舞台窗(poop/crack)隐藏/显示:睡眠时隐藏 → WebView2 停合成/挂起(省电);
    // 显示走 NOACTIVATE 防抢前台焦点
    if let Some(w) = app.get_webview_window(&label) {
        if show { crate::windows::show_no_activate(&w); } else { let _ = w.hide(); }
    }
}

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
    if let Some(w) = app.get_webview_window("main") {
        let _ = crate::windows::recall_show(&w);
    }
    for label in ["poop", "crack"] {
        if let Some(w) = app.get_webview_window(label) {
            crate::windows::show_no_activate(&w);
        }
    }
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
    let repair = MenuItem::with_id(app, "repair", t("修复屏幕", "Repair Screen"), true, None::<&str>)?;

    // ── 设置区(子菜单 + 勾选当前项)──
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

    let acts: [(&str, f64, &str, &str); 3] = [("act_low", 0.2, "低", "Low"), ("act_mid", 0.5, "中", "Med"), ("act_high", 0.9, "高", "High")];
    let mut act_items: Vec<Box<dyn IsMenuItem<tauri::Wry>>> = Vec::new();
    for (id, v, zh_n, en_n) in acts {
        act_items.push(Box::new(CheckMenuItem::with_id(app, id, t(zh_n, en_n), true, (ui.activity - v).abs() < 0.001, None::<&str>)?));
    }
    let act_refs: Vec<&dyn IsMenuItem<tauri::Wry>> = act_items.iter().map(|b| b.as_ref()).collect();
    let m_act = Submenu::with_id(app, "m_act", t("活跃度", "Activity"), true)?;
    m_act.append_items(&act_refs)?;

    let spds: [(&str, f64, &str, &str); 3] = [("spd_slow", 0.7, "慢", "Slow"), ("spd_norm", 1.0, "正常", "Normal"), ("spd_fast", 1.3, "快", "Fast")];
    let mut spd_items: Vec<Box<dyn IsMenuItem<tauri::Wry>>> = Vec::new();
    for (id, v, zh_n, en_n) in spds {
        spd_items.push(Box::new(CheckMenuItem::with_id(app, id, t(zh_n, en_n), true, (ui.speed - v).abs() < 0.001, None::<&str>)?));
    }
    let spd_refs: Vec<&dyn IsMenuItem<tauri::Wry>> = spd_items.iter().map(|b| b.as_ref()).collect();
    let m_spd = Submenu::with_id(app, "m_spd", t("速度", "Speed"), true)?;
    m_spd.append_items(&spd_refs)?;

    let langs: [(&str, &str, &str); 3] = [("lang_system", "system", "跟随系统"), ("lang_zh", "zh", "中文"), ("lang_en", "en", "English")];
    let mut lang_items: Vec<Box<dyn IsMenuItem<tauri::Wry>>> = Vec::new();
    for (id, key, name) in langs {
        lang_items.push(Box::new(CheckMenuItem::with_id(app, id, name.to_string(), true, ui.lang == key, None::<&str>)?));
    }
    let lang_refs: Vec<&dyn IsMenuItem<tauri::Wry>> = lang_items.iter().map(|b| b.as_ref()).collect();
    let m_lang = Submenu::with_id(app, "m_lang", t("语言", "Language"), true)?;
    m_lang.append_items(&lang_refs)?;

    let sound = CheckMenuItem::with_id(app, "sound", t("啾鸣声", "Chirp"), true, ui.sound, None::<&str>)?;
    let login = {
        use tauri_plugin_autostart::ManagerExt;
        let on = app.autolaunch().is_enabled().unwrap_or(false);
        CheckMenuItem::with_id(app, "login", t("开机自启", "Launch at Login"), true, on, None::<&str>)?
    };

    let about = MenuItem::with_id(app, "about", t("关于 翡", "About Fei"), true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", t("退出 翡", "Quit Fei"), true, None::<&str>)?;

    let menu = Menu::with_items(app, &[
        &call, &fish, &sing, &perch, &peck, &show, &recall, &repair,
    ])?;
    let _ = menu; // 分隔符+设置区需要 append;改用一次性 with_items 全量
    let items: Vec<&dyn IsMenuItem<tauri::Wry>> = vec![
        &call, &fish, &sing, &perch, &peck, &show, &recall, &repair,
        &m_theme, &m_act, &m_spd, &sound, &login, &m_lang,
        &about, &quit,
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
        .invoke_handler(tauri::generate_handler![front_perch_cmd, cursor_pos_cmd, window_rect_cmd, surfaces_below_cmd, show_no_activate, stage_visibility, work_area_cmd, recall_cmd])
        .setup(|app| {
            crate::system::setup_power(app.handle().clone());   // 睡眠/锁屏/唤醒 → emit sleep/wake
            // 前端 log 事件 → 终端(调试 webview 错)
            app.listen("log", |event| { println!("[webview] {}", event.payload()); });
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
                        "show" => {
                            // 鸟窗隐藏时前端收不到事件(或不可靠):先 Rust 侧救回,
                            // 走 recall 链路(移安全位+恢复舞台+延迟复位);可见时正常走前端 toggle
                            let hidden = app.get_webview_window("main")
                                .map(|w| !w.is_visible().unwrap_or(true))
                                .unwrap_or(false);
                            if hidden { recall_internal(&handle); }
                            else { let _ = app.emit("menu", "show"); }
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
