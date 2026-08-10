// Phase 1:透明置顶窗 + 托盘(显示/退出)+ 整体点击穿透
// 对应 macOS 版:PetWindowController(透明窗)+ AppDelegate(菜单栏)

use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    Emitter, Listener, Manager,
};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            // 前端 log 事件 → 终端(调试 webview 错)
            app.listen("log", |event| { println!("[webview] {}", event.payload()); });
            // 托盘菜单:召唤/唱/吃/显示/退出(对应 macOS AppDelegate 菜单栏)
            let call_over = MenuItem::with_id(app, "call", "召唤过来", true, None::<&str>)?;
            let sing = MenuItem::with_id(app, "sing", "唱一个", true, None::<&str>)?;
            let eat = MenuItem::with_id(app, "eat", "吃一口", true, None::<&str>)?;
            let show = MenuItem::with_id(app, "show", "显示", true, None::<&str>)?;
            let t_flat = MenuItem::with_id(app, "theme_flat", "主题:扁平", true, None::<&str>)?;
            let t_clay = MenuItem::with_id(app, "theme_clay", "主题:粘土", true, None::<&str>)?;
            let t_pixel = MenuItem::with_id(app, "theme_pixel", "主题:像素", true, None::<&str>)?;
            let t_neon = MenuItem::with_id(app, "theme_neon", "主题:霓虹", true, None::<&str>)?;
            let t_ink = MenuItem::with_id(app, "theme_ink", "主题:水墨", true, None::<&str>)?;
            let t_water = MenuItem::with_id(app, "theme_watercolor", "主题:水彩", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[
                &call_over, &sing, &eat, &show,
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
