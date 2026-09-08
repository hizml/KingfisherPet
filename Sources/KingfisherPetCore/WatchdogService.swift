import AppKit
import Foundation
import QuartzCore

/// 自监控看门狗:每 15s 记 CPU/内存/窗口数(卡死时日志有铁证);
/// CPU 三连击或窗口数超阈 → 熔断重置;重置无效(窗口>50)→ 冷却式自我重启。
/// 从 AppDelegate 拆分的独立类型(评审待办:AppDelegate 拆分)。
/// emergencyReset 需要各子系统句柄,经 owner(AppDelegate)供给。
final class WatchdogService {

    weak var owner: AppDelegate?

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        var highCpuStreak = 0
        var watchdogBusy = false   // 防重入:上一个 ps 没完成不 fork 新的
        let timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in   // 15s:熔断需 3 连击=45s,更频的 fork ps 唤醒太费电
            guard let self = self else { return }
            guard !watchdogBusy else { return }   // 上一个 ps 还没完(系统高负载时 ps 会慢),跳过
            watchdogBusy = true
            // ps 在后台线程跑,不阻塞主线程(主线程阻塞 = 丢帧 = 卡顿加剧)
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/ps")
                task.arguments = ["-p", "\(pid)", "-o", "%cpu,rss"]
                let pipe = Pipe()
                task.standardOutput = pipe
                do { try task.run() } catch { watchdogBusy = false; return }
                // 超时保护:3 秒 ps 不返回就强杀(唤醒后系统高负载时 ps 可能卡)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0) {
                    if task.isRunning { task.terminate() }
                }
                task.waitUntilExit()
                guard task.terminationStatus == 0 else {
                    DispatchQueue.main.async { watchdogBusy = false }
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                var cpu: Double = 0
                var rss: Double = 0
                if let s = String(data: data, encoding: .utf8) {
                    let lines = s.split(separator: "\n")
                    if lines.count > 1 {
                        let parts = lines[1].split(whereSeparator: { $0.isWhitespace }).filter { !$0.isEmpty }
                        if parts.count >= 2 {
                            cpu = Double(parts[0]) ?? 0
                            rss = (Double(parts[1]) ?? 0) / 1024
                        }
                    }
                }
                // 回主线程记日志 + 检查熔断
                DispatchQueue.main.async {
                    watchdogBusy = false
                    let state = self.owner?.petController?.behavior.currentStateForLog() ?? "?"
                    let onWin = self.owner?.petController?.behavior.onWindow ?? false
                    // 自己进程的窗口数(泄漏监控:CGWindowList 过滤本 pid)
                    var winCount = -1
                    if let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
                        let myPID = ProcessInfo.processInfo.processIdentifier
                        winCount = infos.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == myPID }.count
                    }
                    kfLog("WATCHDOG cpu=\(String(format: "%.1f", cpu))% rss=\(String(format: "%.0f", rss))MB effects=\(Effect.active.count) windows=\(winCount) state=\(state) onWindow=\(onWin)")
                    // 窗口数熔断:正常常驻 ≤10(鸟/影/枝/裂纹/屎≤8/池);超 30 = 出现未知泄漏
                    // → 熔断重置;超 50(重置无效)→ 自我重启,宁可闪一下也不拖死机器
                    if winCount > 30 {
                        kfLog("⚠️ WINDOW LEAK: windows=\(winCount) > 30 → 熔断重置")
                        self.emergencyReset()
                    }
                    if winCount > 50 {
                        kfLog("🚨 WINDOW LEAK CRITICAL: windows=\(winCount) > 50 → 自我重启")
                        Self.relaunchLeakGuard()
                    }
                    if cpu > 40 {
                        highCpuStreak += 1
                        if highCpuStreak >= 3 {
                            kfLog("⚠️ CIRCUIT BREAKER: cpu=\(cpu)% 持续 \(highCpuStreak*15)s → 熔断重置")
                            self.emergencyReset()
                            highCpuStreak = 0
                        }
                    } else {
                        highCpuStreak = 0
                    }
                }
            }
        }
        self.timer = timer
    }

    /// 睡眠/锁屏时停 watchdog(夜里每 15s fork ps + 全窗口枚举,纯耗电)
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 泄漏终极兜底:重启进程(窗口对象全清,泄漏清零)。带冷却,防重启风暴。
    private static var lastRelaunchAt: CFTimeInterval = 0
    static func relaunchLeakGuard() {
        guard CACurrentMediaTime() - lastRelaunchAt > 300 else { return }   // 5 分钟冷却
        lastRelaunchAt = CACurrentMediaTime()
        let url = Bundle.main.bundleURL
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            kfLog("relaunching (leak guard)")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-n", url.path]
            try? proc.run()
            NSApp.terminate(nil)
        }
    }

    /// 熔断重置:停一切 + 清一切 + 干净恢复。不管根因是什么,保证不卡死系统。
    func emergencyReset() {
        // 停所有 Behavior 定时器 + 代际 bump
        owner?.petController?.behavior.suspend()
        // 停所有常驻 timer
        owner?.petController?.petView.suspendAnimation()
        owner?.poopCtl?.suspend()
        owner?.branchCtl?.suspend()
        // 撤所有特效窗口
        Effects.clearAll()
        // 清裂纹 layer(保留裂纹数据,只移除 layer 树防 GPU 合成开销)
        owner?.crackCtl?.purgeLayers()
        // 短暂等待后干净恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.owner?.petController?.petView.resumeAnimation()
            self.owner?.poopCtl?.resume()
            self.owner?.branchCtl?.resume()
            self.owner?.petController?.behavior.forceIdle()
            kfLog("CIRCUIT BREAKER: 重置完成,恢复运行")
        }
    }
}
