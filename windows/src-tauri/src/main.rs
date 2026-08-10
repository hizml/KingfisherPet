// 防止 release 弹控制台窗口(Windows 子系统)
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    kingfisherpet_lib::run()
}
