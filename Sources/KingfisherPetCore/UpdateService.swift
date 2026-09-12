import AppKit
import CommonCrypto
import Foundation

/// 检查更新(GitHub Releases 对比):手动(菜单)弹详情,自动(启动 30s + 每 24h)静默只标菜单。
/// 从 AppDelegate 拆分的独立类型(评审待办:AppDelegate 拆分)。
final public class UpdateService {

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
        fetchLatest { [weak self] latest, digest in
            let cur = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
            self?.menuItem?.title = Language.t("menu.checkUpdate")   // 看过详情,清标注
            self?.alert(latest: latest, current: cur, digest: digest)
        }
    }

    /// 自动检查(静默):有新版只在菜单项上标注(不弹窗,用户点开才出详情);
    /// 无新版/失败 → 清标注或不动,一声不吭
    private func autoCheck() {
        fetchLatest { [weak self] latest, _ in
            let cur = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
            let has = latest.map { Self.isNewer($0, than: cur) } ?? false
            self?.menuItem?.title = has
                ? Language.t("update.found")
                : Language.t("menu.checkUpdate")
            if has { kfLog("update: 自动检查发现新版 \(latest!),菜单已标注") }
        }
    }

    /// semver 比较:tag(vX.Y.Z)是否比 current 新(逐段数值比较)。
    /// 之前是严格不等(latest != "v"+cur)——本地比线上新(预发布/线上回滚)会误报"发现新版本"
    /// (N5105 实机验证时实锤:装 63 线上 59 仍提示更新)。解析失败按"不更新"保守处理。
    public static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.dropFirst(s.hasPrefix("v") ? 1 : 0)
                .split(separator: ".").prefix(4)
                .map { Int($0) ?? 0 }
        }
        let a = parts(tag), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 拉最新版:(tag, mac 资产 SHA256)。digest 是评审 A1 的完整性第二道防线
    /// (GitHub API 的 assets[].digest 形如 "sha256:…";无该字段的旧 API 返回 nil,验签退化为签名校验)。
    private func fetchLatest(_ done: @escaping (String?, String?) -> Void) {
        let url = URL(string: "https://api.github.com/repos/hizml/KingfisherPet/releases/latest")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var latest: String?
            var digest: String?
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                latest = obj["tag_name"] as? String
                if let assets = obj["assets"] as? [[String: Any]] {
                    for a in assets where (a["name"] as? String) == "KingfisherPet-mac-native.zip" {
                        if let d = a["digest"] as? String, d.hasPrefix("sha256:") {
                            digest = String(d.dropFirst("sha256:".count))
                        }
                        break
                    }
                }
            }
            DispatchQueue.main.async { done(latest, digest) }
        }.resume()
    }

    /// 更新结果弹窗(文案全走 Language 字典,评审 B2)。
    /// v1.6.0:发现新版且当前是 .app 运行 → 首按钮「下载并更新」走应用内更新
    /// (下载→验签→替换→重启);否则保留「前往下载」浏览器流。
    private func alert(latest: String?, current: String, digest: String? = nil) {
        if latest == nil {
            KFDialog.show(title: Language.t("update.failed"), message: Language.t("update.failedBody"),
                          buttons: [Language.t("update.openReleases"), Language.t("update.later")]) { idx in
                if idx == 0 { NSWorkspace.shared.open(URL(string: "https://github.com/hizml/KingfisherPet/releases")!) }
            }
            return
        }
        if !Self.isNewer(latest!, than: current) {
            KFDialog.show(title: Language.t("update.latest"), message: "v\(current)",
                          buttons: [Language.t("update.ok")]) { _ in }
        } else {
            let canInstall = Bundle.main.bundleURL.pathExtension == "app"
            let rel = URL(string: "https://github.com/hizml/KingfisherPet/releases/latest")!
            let body = String(format: Language.t("update.downloadBody"), current)
            if canInstall {
                KFDialog.show(title: Language.t("update.found") + " \(latest!)", message: body,
                              buttons: [Language.t("update.install"), Language.t("update.openReleases"), Language.t("update.later")]) { [weak self] idx in
                    switch idx {
                    case 0:
                        Self.installUpdate(tag: latest!, expectedSHA256: digest, progress: nil) { ok, why in
                            // 评审 A13:失败不再只写日志——用户面前给结果,并提供前往下载兜底
                            guard !ok else { return }
                            kfLog("update: 应用内更新失败(\(why))")
                            self?.reportInstallFailure(why)
                        }
                    case 1: NSWorkspace.shared.open(rel)
                    default: break
                    }
                }
            } else {
                KFDialog.show(title: Language.t("update.found") + " \(latest!)", message: body,
                              buttons: [Language.t("update.download"), Language.t("update.later")]) { idx in
                    if idx == 0 { NSWorkspace.shared.open(rel) }
                }
            }
        }
    }

    /// 安装失败反馈(A13:静默失败触「菜单状态必须可见」红线;A6:自绘)
    private func reportInstallFailure(_ why: String) {
        KFDialog.show(title: Language.t("update.failed"), message: why,
                      buttons: [Language.t("update.openReleases"), Language.t("update.later")]) { idx in
            if idx == 0 { NSWorkspace.shared.open(URL(string: "https://github.com/hizml/KingfisherPet/releases")!) }
        }
    }

    // MARK: - 应用内更新(v1.6.0:下载签名 zip → 验签 → 热替换 .app → 重启)

    /// 静态下载入口:progress 主线程回调 0–100;done(ok, 失败原因)。
    /// 成功路径最后一步是 relaunch——done(ok) 只在失败时被感知(进程已重启)。
    static func installUpdate(tag: String,
                              expectedSHA256: String? = nil,
                              progress: ((Int) -> Void)?,
                              done: @escaping (Bool, String) -> Void) {
        // 评审 A17:tag 来自 GitHub API 也要防畸形(强解包崩 = 红线同型)
        guard tag.allSatisfy({ $0.isLetter || $0.isNumber || ".-_".contains($0) }),
              let zipURL = URL(string: "https://github.com/hizml/KingfisherPet/releases/download/\(tag)/KingfisherPet-mac-native.zip") else {
            DispatchQueue.main.async { done(false, "下载地址构造失败(tag 畸形)") }; return
        }
        let curApp = Bundle.main.bundleURL
        DispatchQueue.global(qos: .userInitiated).async {
            // ① 下载(带进度)
            let (data, resp) = Download.one(zipURL) { received, total in
                guard total > 0 else { return }
                DispatchQueue.main.async { progress?(Int(Double(received) / Double(total) * 100)) }
            }
            guard let data, let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 1_000_000 else {
                DispatchQueue.main.async { done(false, "下载失败 HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)") }
                return
            }
            // ② 解压到临时目录
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("kf-update-\(Int(CACurrentMediaTime()))", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let zipPath = tmp.appendingPathComponent("update.zip")
            do { try data.write(to: zipPath) } catch {
                DispatchQueue.main.async { done(false, "写临时文件失败") }; return
            }
            let unzipped = tmp.appendingPathComponent("KingfisherPet.app")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", zipPath.path, tmp.path]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil, p.waitUntilExitWithTimeout() == 0,
                  FileManager.default.fileExists(atPath: unzipped.appendingPathComponent("Contents/MacOS/KingfisherPet").path) else {
                DispatchQueue.main.async { done(false, "解压失败") }; return
            }
            // ③ 验签(评审 A1 修复:旧实现只读 -dv 元数据,未签名包直接放行):
            // a) codesign --verify --strict 做完整性校验(被篡改的已签名包在这里现形);
            // b) TeamIdentifier 必须精确等于本团队——未签名包(-dv 无 Team 行)不再放行;
            // c) 发布资产的 SHA256(GitHub API digest 字段)与本地比对,双保险防替换。
            let v = Process()
            v.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            v.arguments = ["--verify", "--strict", unzipped.path]
            v.standardOutput = FileHandle.nullDevice; v.standardError = FileHandle.nullDevice
            _ = try? v.run()
            guard v.waitUntilExitWithTimeout() == 0 else {
                DispatchQueue.main.async { done(false, "签名完整性校验失败") }; return
            }
            let q = Process()
            q.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            q.arguments = ["-dv", unzipped.path]
            let pipe = Pipe(); q.standardOutput = pipe; q.standardError = pipe
            _ = try? q.run(); q.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard out.contains("TeamIdentifier=5CTLSL2C9X") else {
                DispatchQueue.main.async { done(false, "签名校验不符(非本团队/未签名)") }; return
            }
            if let expect = expectedSHA256, expect != Self.sha256(of: data) {
                DispatchQueue.main.async { done(false, "SHA256 不符(资产被替换?)") }; return
            }
            // ④ 热替换:旧包挪 ~/.Trash(可回滚),新包就位;失败把旧包挪回去
            let fm = FileManager.default
            let trashName = "KingfisherPet-\(Int(CACurrentMediaTime())).app"
            let trashURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash/\(trashName)", isDirectory: true)
            do {
                try fm.moveItem(at: curApp, to: trashURL)
                try fm.moveItem(at: unzipped, to: curApp)
            } catch {
                // 回滚:旧包尽量放回去
                if !fm.fileExists(atPath: curApp.path) {
                    try? fm.moveItem(at: trashURL, to: curApp)
                }
                DispatchQueue.main.async { done(false, "替换失败(\(error.localizedDescription))") }
                return
            }
            kfLog("update: 替换完成 \(curApp.path),即将重启")
            // ⑤ 重启(新包从原路径起)
            DispatchQueue.main.async {
                let rel = Process()
                rel.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                rel.arguments = ["-n", curApp.path]
                try? rel.run()
                NSApp.terminate(nil)
            }
        }
    }
}

extension UpdateService {
    /// 评审 A1:资产 SHA256(GitHub API 的 digest 字段形如 "sha256:abcd…")
    static func sha256(of data: Data) -> String {
        var h = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &h) }
        return h.map { String(format: "%02x", $0) }.joined()
    }
}

/// 一次性下载器(带进度回调;dataTask 简版,20MB 级包足够)
private enum Download {
    static func one(_ url: URL, progress: @escaping (Int64, Int64) -> Void) -> (Data?, URLResponse?) {
        let sem = DispatchSemaphore(value: 0)
        var data: Data?, resp: URLResponse?
        let task = URLSession.shared.dataTask(with: url) { d, r, _ in
            data = d; resp = r
            sem.signal()
        }
        // 进度:KVO expectedProgress(系统已按 Content-Length 折算)
        let obs = task.progress.observe(\.fractionCompleted) { p, _ in
            progress(Int64(p.fractionCompleted * 100), 100)
        }
        task.resume()
        sem.wait()
        obs.invalidate()
        return (data, resp)
    }
}

extension Process {
    /// waitUntilExit 带超时(解压/查签卡死时 60s 放弃)
    func waitUntilExitWithTimeout(_ sec: Double = 60) -> Int32 {
        let deadline = Date().addingTimeInterval(sec)
        while isRunning && Date() < deadline { usleep(100_000) }
        if isRunning { terminate(); return -1 }
        return terminationStatus
    }
}
