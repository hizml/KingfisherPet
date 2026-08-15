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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .invoke_handler(tauri::generate_handler![front_perch_cmd, cursor_pos_cmd, window_rect_cmd])
        .setup(|app| {
            crate::system::setup_power(app.handle().clone());   // Windows 睡眠/唤醒监听 → emit sleep/wake
            // 前端 log 事件 → 终端(调试 webview 错)
            app.listen("log", |event| { println!("[webview] {}", event.payload()); });
            // 托盘菜单:召唤/唱/吃/显示/退出(对应 macOS AppDelegate 菜单栏)
            let call_over = MenuItem::with_id(app, "call", "召唤过来", true, None::<&str>)?;
            let sing = MenuItem::with_id(app, "sing", "唱一个", true, None::<&str>)?;
            let eat = MenuItem::with_id(app, "eat", "吃一口", true, None::<&str>)?;
            let show = MenuItem::with_id(app, "show", "显示", true, None::<&str>)?;
            let repair = MenuItem::with_id(app, "repair", "修复屏幕", true, None::<&str>)?;
            let t_flat = MenuItem::with_id(app, "theme_flat", "主题:扁平", true, None::<&str>)?;
            let t_clay = MenuItem::with_id(app, "theme_clay", "主题:粘土", true, None::<&str>)?;
            let t_pixel = MenuItem::with_id(app, "theme_pixel", "主题:像素", true, None::<&str>)?;
            let t_neon = MenuItem::with_id(app, "theme_neon", "主题:霓虹", true, None::<&str>)?;
            let t_ink = MenuItem::with_id(app, "theme_ink", "主题:水墨", true, None::<&str>)?;
            let t_water = MenuItem::with_id(app, "theme_watercolor", "主题:水彩", true, None::<&str>)?;
            let sound = MenuItem::with_id(app, "sound", "声音开关", true, None::<&str>)?;
            let act_low = MenuItem::with_id(app, "act_low", "活跃度:低", true, None::<&str>)?;
            let act_mid = MenuItem::with_id(app, "act_mid", "活跃度:中", true, None::<&str>)?;
            let act_high = MenuItem::with_id(app, "act_high", "活跃度:高", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[
                &call_over, &sing, &eat, &show, &repair,
                &sound,
                &act_low, &act_mid, &act_high,
                &t_flat, &t_clay, &t_pixel, &t_neon, &t_ink, &t_water,
                &quit,
            ])?;
            let _ = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => app.exit(0),
                    "show" => {
                        if let Some(w) = app.get_webview_window("main") {
                            let _ = w.show();
                            let _ = w.set_focus();
                        }
                    }
                    "sound" => { let _ = app.emit("setting", "sound"); }
                    "act_low" | "act_mid" | "act_high" => {
                        let v = match event.id.as_ref() { "act_low" => 0.2, "act_high" => 0.9, _ => 0.5 };
                        let _ = app.emit("setting", format!("activity:{}", v));
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
