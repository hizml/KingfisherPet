// Phase 1:透明置顶窗 + 托盘(显示/退出)+ 整体点击穿透
// 对应 macOS 版:PetWindowController(透明窗)+ AppDelegate(菜单栏)

mod windows;
mod system;

use tauri::{
    menu::{Menu, MenuItem},
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

/// 显示主窗但不激活(不抢用户前台焦点)。Windows 走 SetWindowPos(NOACTIVATE),
/// 其他平台退化为普通 show。
#[tauri::command]
fn show_no_activate(app: tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        crate::windows::show_no_activate(&w);
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .invoke_handler(tauri::generate_handler![front_perch_cmd, cursor_pos_cmd, window_rect_cmd, surfaces_below_cmd, show_no_activate])
        .setup(|app| {
            crate::system::setup_power(app.handle().clone());   // Windows 睡眠/唤醒监听 → emit sleep/wake
            // 前端 log 事件 → 终端(调试 webview 错)
            app.listen("log", |event| { println!("[webview] {}", event.payload()); });
            // 托盘菜单:按系统语言选文案(中文系统→中文,否则英文)
            let zh = is_zh();
            let call_over = MenuItem::with_id(app, "call", if zh { "召唤过来" } else { "Call Over" }, true, None::<&str>)?;
            let sing = MenuItem::with_id(app, "sing", if zh { "唱一个" } else { "Sing" }, true, None::<&str>)?;
            let fish = MenuItem::with_id(app, "fish", if zh { "去抓条鱼" } else { "Catch a Fish" }, true, None::<&str>)?;
            let show = MenuItem::with_id(app, "show", if zh { "显示 / 隐藏" } else { "Show / Hide" }, true, None::<&str>)?;
            let repair = MenuItem::with_id(app, "repair", if zh { "修复屏幕" } else { "Repair Screen" }, true, None::<&str>)?;
            let perch = MenuItem::with_id(app, "perch", if zh { "停到窗口上" } else { "Perch on a Window" }, true, None::<&str>)?;
            let peck = MenuItem::with_id(app, "peck", if zh { "啄一下" } else { "Peck" }, true, None::<&str>)?;
            let about = MenuItem::with_id(app, "about", if zh { "关于 翡" } else { "About Fei" }, true, None::<&str>)?;
            let auto_on = {
                use tauri_plugin_autostart::ManagerExt;
                app.autolaunch().is_enabled().unwrap_or(false)
            };
            let login = tauri::menu::CheckMenuItem::with_id(app, "login",
                if zh { "开机自启" } else { "Launch at Login" }, true, auto_on, None::<&str>)?;
            let t_flat = MenuItem::with_id(app, "theme_flat", if zh { "主题:扁平" } else { "Theme: Flat" }, true, None::<&str>)?;
            let t_clay = MenuItem::with_id(app, "theme_clay", if zh { "主题:粘土" } else { "Theme: Clay" }, true, None::<&str>)?;
            let t_pixel = MenuItem::with_id(app, "theme_pixel", if zh { "主题:像素" } else { "Theme: Pixel" }, true, None::<&str>)?;
            let t_neon = MenuItem::with_id(app, "theme_neon", if zh { "主题:霓虹" } else { "Theme: Neon" }, true, None::<&str>)?;
            let t_ink = MenuItem::with_id(app, "theme_ink", if zh { "主题:水墨" } else { "Theme: Ink" }, true, None::<&str>)?;
            let t_water = MenuItem::with_id(app, "theme_watercolor", if zh { "主题:水彩" } else { "Theme: Watercolor" }, true, None::<&str>)?;
            let sound = MenuItem::with_id(app, "sound", if zh { "声音开关" } else { "Sound" }, true, None::<&str>)?;
            let act_low = MenuItem::with_id(app, "act_low", if zh { "活跃度:低" } else { "Activity: Low" }, true, None::<&str>)?;
            let act_mid = MenuItem::with_id(app, "act_mid", if zh { "活跃度:中" } else { "Activity: Med" }, true, None::<&str>)?;
            let act_high = MenuItem::with_id(app, "act_high", if zh { "活跃度:高" } else { "Activity: High" }, true, None::<&str>)?;
            let spd_slow = MenuItem::with_id(app, "spd_slow", if zh { "速度:慢" } else { "Speed: Slow" }, true, None::<&str>)?;
            let spd_norm = MenuItem::with_id(app, "spd_norm", if zh { "速度:正常" } else { "Speed: Normal" }, true, None::<&str>)?;
            let spd_fast = MenuItem::with_id(app, "spd_fast", if zh { "速度:快" } else { "Speed: Fast" }, true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", if zh { "退出" } else { "Quit" }, true, None::<&str>)?;
            let menu = Menu::with_items(app, &[
                &call_over, &sing, &fish, &perch, &peck, &show, &repair, &about,
                &login,
                &sound,
                &act_low, &act_mid, &act_high,
                &spd_slow, &spd_norm, &spd_fast,
                &t_flat, &t_clay, &t_pixel, &t_neon, &t_ink, &t_water,
                &quit,
            ])?;
            let _ = TrayIconBuilder::with_id("main")
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&menu)
                .show_menu_on_left_click(true)   // 左键直接开菜单(Mac 端同款,别右键)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "about" => {
                        let _ = open::that("https://github.com/hizml/KingfisherPet");
                    }
                    "login" => {
                        use tauri_plugin_autostart::ManagerExt;
                        let m = app.autolaunch();
                        let on = m.is_enabled().unwrap_or(false);
                        let r = if on { m.disable() } else { m.enable() };
                        let _ = app.emit("log", format!("autostart toggle {} -> {:?}", on, r));
                    }
                    "quit" => app.exit(0),
                    "show" => { let _ = app.emit("menu", "show"); }   // 前端 toggle(fallAway/hatchIn);别在这抢焦点
                    "sound" => { let _ = app.emit("setting", "sound"); }
                    "act_low" | "act_mid" | "act_high" => {
                        let v = match event.id.as_ref() { "act_low" => 0.2, "act_high" => 0.9, _ => 0.5 };
                        let _ = app.emit("setting", format!("activity:{}", v));
                    }
                    "spd_slow" | "spd_norm" | "spd_fast" => {
                        let v = match event.id.as_ref() { "spd_slow" => 0.7, "spd_fast" => 1.3, _ => 1.0 };
                        let _ = app.emit("setting", format!("speed:{}", v));
                    }
                    id if id.starts_with("theme_") => {
                        let t = id.strip_prefix("theme_").unwrap_or("flat");
                        let _ = app.emit("theme", t);
                    }
                    id => { let _ = app.emit("menu", id); }
                })
                .build(app);
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
