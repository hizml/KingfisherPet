import Foundation

/// 运行时语言:跟随系统(默认)/ 中文 / English。菜单可切,即时生效。
/// (NSLocalizedString 只跟系统语言,不能运行时切,所以自建表。)
public enum Language {

    enum Choice: String { case system, zh, en }

    static var choice: Choice {
        get { Choice(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    private static let key = "kingfisher.language"

    /// 实际生效语言:choice=system 时按设备首选语言(中文系→zh,否则 en)
    static var current: String {
        switch choice {
        case .zh: return "zh"
        case .en: return "en"
        case .system:
            let pref = Locale.preferredLanguages.first ?? "en"
            return pref.hasPrefix("zh") ? "zh" : "en"
        }
    }

    /// 取文案。查不到回退 key 本身(开发期易发现)。
    public static func t(_ key: String) -> String {
        let table = current == "zh" ? zh : en
        return table[key] ?? en[key] ?? key
    }

    private static let zh: [String: String] = [
        // 菜单
        "menu.callOver": "召唤过来",
        "menu.fish": "去抓条鱼",
        "menu.sing": "唱一个",
        "menu.perch": "停到窗口上",
        "menu.peck": "啄一下",
        "menu.toggleVisibility": "显示 / 隐藏",
        "menu.soundOn": "啾鸣声:开",
        "menu.soundOff": "啾鸣声:关",
        "menu.autoLogin": "开机自启",
        "menu.repairScreen": "修复屏幕",
        "menu.settings": "设置…",
        "menu.checkUpdate": "检查更新…",
        "update.failed": "检查更新失败",
        "update.failedBody": "无法访问 GitHub(网络原因)。可手动前往 Releases 页面查看。",
        "update.openReleases": "打开 Releases 页",
        "update.latest": "已是最新版本",
        "update.found": "发现新版本",
        "update.downloadBody": "当前 v%@。前往下载?",
        "update.download": "前往下载",
        "update.later": "稍后",
        "menu.about": "关于 翡",
        "menu.quit": "退出 翡",
        "menu.language": "语言",
        "menu.lang.system": "跟随系统",
        "menu.lang.zh": "中文",
        "menu.lang.en": "English",
        // 设置
        "settings.title": "翡 · 设置",
        "settings.theme": "主题",
        "settings.activity": "活跃度",
        "settings.speed": "动画速度",
        "settings.peck": "啄屏幕",
        "settings.sound": "啾鸣声",
        "settings.activity.low": "低",
        "settings.activity.mid": "中",
        "settings.activity.high": "高",
        // 关于
        "about.title": "翡",
        "about.body": "一只住在你 Mac 上的小生灵。\n它会自己活动,也会回应你——\n至于它都会些什么,养着养着就知道了。\n\n点它、拖它,或者就让它待着。",
        "about.github": "GitHub 主页",
        "about.ok": "好",
        // 无障碍/其他
        "ax.petName": "翡 · 翠鸟",
        "ax.petHelp": "点击它会害羞,拖动可移动。",
        "ax.tooltip": "翡 · 翠鸟桌面宠物",
        "statusitem.tooltip": "翡 · 翠鸟桌面宠物",
    ]

    private static let en: [String: String] = [
        // Menu
        "menu.callOver": "Call Over",
        "menu.fish": "Go Catch a Fish",
        "menu.sing": "Sing",
        "menu.perch": "Perch on a Window",
        "menu.peck": "Peck",
        "menu.toggleVisibility": "Show / Hide",
        "menu.soundOn": "Chirp: On",
        "menu.soundOff": "Chirp: Off",
        "menu.autoLogin": "Launch at Login",
        "menu.repairScreen": "Repair Screen",
        "menu.settings": "Settings…",
        "menu.checkUpdate": "Check for Updates…",
        "update.failed": "Update Check Failed",
        "update.failedBody": "Cannot reach GitHub. You can check the Releases page manually.",
        "update.openReleases": "Open Releases",
        "update.latest": "Up to Date",
        "update.found": "New Version",
        "update.downloadBody": "Current v%@. Download now?",
        "update.download": "Download",
        "update.later": "Later",
        "menu.about": "About Fei",
        "menu.quit": "Quit Fei",
        "menu.language": "Language",
        "menu.lang.system": "Follow System",
        "menu.lang.zh": "中文",
        "menu.lang.en": "English",
        // Settings
        "settings.title": "Fei · Settings",
        "settings.theme": "Theme",
        "settings.activity": "Activity",
        "settings.speed": "Animation Speed",
        "settings.peck": "Peck the screen",
        "settings.sound": "Chirp",
        "settings.activity.low": "Low",
        "settings.activity.mid": "Med",
        "settings.activity.high": "High",
        // About
        "about.title": "Fei",
        "about.body": "A little creature living on your Mac.\nIt does its own thing, and answers to you—\nwhat it can do, you'll discover as you keep it around.\n\nClick it, drag it, or just let it be.",
        "about.github": "GitHub Page",
        "about.ok": "OK",
        // Accessibility
        "ax.petName": "Fei · Kingfisher",
        "ax.petHelp": "Click to make it shy; drag to move.",
        "ax.tooltip": "Fei · Kingfisher desktop pet",
        "statusitem.tooltip": "Fei · Kingfisher desktop pet",
    ]
}
