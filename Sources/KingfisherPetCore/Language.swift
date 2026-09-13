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
        "menu.feed": "喂条鱼",
        "growth.stage.stranger": "陌生",
        "growth.stage.acquainted": "相识",
        "growth.stage.familiar": "熟悉",
        "growth.stage.close": "亲近",
        "growth.stage.intimate": "亲密",
        "growth.stage.bonded": "缘定一生",
        "growth.hatchedSuffix": "(已孵化)",
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
        "update.install": "下载并更新",
        "update.later": "稍后",
        "update.ok": "好",
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
        // 天气联动(v1.5.0)
        "settings.weather": "天气联动",
        "settings.weather.enable": "启用天气联动",
        "settings.weather.note": "开启后将请求所选天气源查询天气(约 30 分钟一次);城市留空时用 IP 粗略定位。",
        "settings.weather.city": "城市",
        "settings.weather.cityPlaceholder": "留空 = IP 定位",
        "settings.weather.provider": "数据源",
        "settings.weather.key": "和风 API Key",
        "settings.weather.host": "和风 API Host",
        "settings.weather.status": "状态:%@",
        "settings.weather.status.off": "未开启",
        "settings.weather.status.ok": "正常",
        "settings.weather.status.unavailable": "天气源不可用(已静默降级,不干预行为)",
        "weather.kind.sunny": "晴",
        "weather.kind.overcast": "阴",
        "weather.kind.rainLight": "小雨",
        "weather.kind.rainHeavy": "大雨",
        "weather.kind.thunder": "雷暴",
        "weather.kind.snowLight": "小雪",
        "weather.kind.snowHeavy": "大雪",
        "weather.kind.fog": "雾",
        "weather.kind.wind": "大风",
        "weather.kind.hot": "热",
        "weather.kind.cold": "冷",
        "weather.unavailable": "🌧 天气源不可用",
        "weather.alert.line": "⚠️ %@%@ · 鸟躲起来了",
        // 关于
        "about.title": "翡",
        "about.body": "一只住在你 Mac 上的小生灵。\n它会自己活动,也会回应你——\n至于它都会些什么,养着养着就知道了。\n\n点它、拖它,或者就让它待着。",
        "about.github": "GitHub 主页",
        "about.version": "当前版本 v%@",
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
        "menu.feed": "Feed a Fish",
        "growth.stage.stranger": "Stranger",
        "growth.stage.acquainted": "Acquainted",
        "growth.stage.familiar": "Familiar",
        "growth.stage.close": "Close",
        "growth.stage.intimate": "Intimate",
        "growth.stage.bonded": "Bonded",
        "growth.hatchedSuffix": " (hatched)",
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
        "update.install": "Download & Update",
        "update.later": "Later",
        "update.ok": "OK",
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
        // Weather (v1.5.0)
        "settings.weather": "Weather",
        "settings.weather.enable": "Enable weather",
        "settings.weather.note": "When on, the selected weather provider is queried every ~30 minutes; empty city = rough IP location.",
        "settings.weather.city": "City",
        "settings.weather.cityPlaceholder": "Empty = IP location",
        "settings.weather.provider": "Provider",
        "settings.weather.key": "QWeather API Key",
        "settings.weather.host": "QWeather API Host",
        "settings.weather.status": "Status: %@",
        "settings.weather.status.off": "off",
        "settings.weather.status.ok": "ok",
        "settings.weather.status.unavailable": "unavailable (degraded silently)",
        "weather.kind.sunny": "Sunny",
        "weather.kind.overcast": "Overcast",
        "weather.kind.rainLight": "Light rain",
        "weather.kind.rainHeavy": "Heavy rain",
        "weather.kind.thunder": "Thunderstorm",
        "weather.kind.snowLight": "Light snow",
        "weather.kind.snowHeavy": "Heavy snow",
        "weather.kind.fog": "Fog",
        "weather.kind.wind": "Windy",
        "weather.kind.hot": "Hot",
        "weather.kind.cold": "Cold",
        "weather.unavailable": "🌧 Weather unavailable",
        "weather.alert.line": "⚠️ %@ %@ · hiding",
        // About
        "about.title": "Fei",
        "about.body": "A little creature living on your Mac.\nIt does its own thing, and answers to you—\nwhat it can do, you'll discover as you keep it around.\n\nClick it, drag it, or just let it be.",
        "about.github": "GitHub Page",
        "about.version": "Version v%@",
        "about.ok": "OK",
        // Accessibility
        "ax.petName": "Fei · Kingfisher",
        "ax.petHelp": "Click to make it shy; drag to move.",
        "ax.tooltip": "Fei · Kingfisher desktop pet",
        "statusitem.tooltip": "Fei · Kingfisher desktop pet",
    ]
}
