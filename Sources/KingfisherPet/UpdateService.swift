import AppKit
import Foundation

/// 检查更新(GitHub Releases 对比):手动(菜单)弹详情,自动(启动 30s + 每 24h)静默只标菜单。
/// 从 AppDelegate 拆分的独立类型(评审待办:AppDelegate 拆分)。
final class UpdateService {

    /// 「检查更新…」菜单项(静默发现新版时标注;由 AppDelegate 建菜单后注入)
    weak var menuItem: NSMenuItem?

    private var timer: Timer?

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.autoCheck() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.autoCheck()
        }
    }

    /// 手动检查(菜单):总是给反馈(成功/最新/失败都弹窗)
    func checkNow() {
        fetchLatest { [weak self] latest in
            let cur = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
            self?.menuItem?.title = Language.t("menu.checkUpdate")   // 看过详情,清标注
            self?.alert(latest: latest, current: cur)
        }
    }

    /// 自动检查(静默):有新版只在菜单项上标注(不弹窗,用户点开才出详情);
    /// 无新版/失败 → 清标注或不动,一声不吭
    private func autoCheck() {
        fetchLatest { [weak self] latest in
            let cur = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
            let has = (latest != nil) && latest != "v" + cur
            self?.menuItem?.title = has
                ? Language.t("update.found")
                : Language.t("menu.checkUpdate")
            if has { kfLog("update: 自动检查发现新版 \(latest!),菜单已标注") }
        }
    }

    private func fetchLatest(_ done: @escaping (String?) -> Void) {
        let url = URL(string: "https://api.github.com/repos/hizml/KingfisherPet/releases/latest")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var latest: String?
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                latest = obj["tag_name"] as? String
            }
            DispatchQueue.main.async { done(latest) }
        }.resume()
    }

    /// 更新结果弹窗(文案全走 Language 字典,评审 B2)
    private func alert(latest: String?, current: String) {
        let a = NSAlert()
        if latest == nil {
            a.messageText = Language.t("update.failed")
            a.informativeText = Language.t("update.failedBody")
            a.addButton(withTitle: Language.t("update.openReleases"))
            if a.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "https://github.com/hizml/KingfisherPet/releases")!)
            }
            return
        }
        if latest == "v" + current {
            a.messageText = Language.t("update.latest")
            a.informativeText = "v\(current)"
            _ = a.runModal()
        } else {
            a.messageText = Language.t("update.found") + " \(latest!)"
            a.informativeText = String(format: Language.t("update.downloadBody"), current)
            a.addButton(withTitle: Language.t("update.download"))
            a.addButton(withTitle: Language.t("update.later"))
            if a.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "https://github.com/hizml/KingfisherPet/releases/latest")!)
            }
        }
    }
}
