import AppKit
import KingfisherPetCore

// 薄壳入口:全部实现都在 core 库(见 KingfisherPetCore/KingfisherPetApp.swift 头注释)
let app = NSApplication.shared
app.delegate = AppDelegate.appDelegate
app.setActivationPolicy(.accessory)   // 不进 Dock,只留菜单栏图标
app.run()
