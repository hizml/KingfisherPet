import Foundation
import Network
import QuartzCore

/// 局域网小鸟(v1.7.0 串门批):Bonjour(_kingfisherpet._tcp)发现同网段的翡,
/// TCP 换行 JSON 通信(HELLO/PEEP/VISIT/FISH/BUSY/BYE),纯本地零账号零服务器。
/// 演出复用 VisitorService;陌生邻居首发消息必须本机确认(隐私红线)。
/// Windows 侧对称实现(Rust mdns-sd + std TCP,协议同此)。
public final class LanBirds {

    static let shared = LanBirds()

    // MARK: - 协议(纯函数,单测直打)

    public enum Lan {
        public static let protoVersion = 1
        static let serviceType = "_kingfisherpet._tcp"
        public static let maxLine = 1024          // 白名单小消息;超限静默丢弃(防灌包)
        static let heartbeat: TimeInterval = 5
        static let peerTimeout: TimeInterval = 10
        /// 串门冷却:每对邻居 30 分钟,双侧各记对方名,天然对称。【可调】
        static let visitCooldown: TimeInterval = 30 * 60
        /// 随机代号:翠鸟-3F2A(4 位大写十六进制)。不暴露主机名/IP(隐私红线)
        public static func randomCodename() -> String {
            let hex = String(format: "%04X", Int.random(in: 0...0xFFFF))
            return "翠鸟-\(hex)"
        }
        public static let types = ["HELLO", "PING", "PONG", "PEEP", "VISIT", "FISH", "BUSY", "BYE"]

        public static func encode(_ obj: [String: Any]) -> Data? {
            guard JSONSerialization.isValidJSONObject(obj),
                  let d = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
            return d.count + 1 <= maxLine ? d + Data([0x0A]) : nil
        }

        /// 解析一行:超长/坏 JSON/版本不认识/类型不在白名单 → nil(调用方静默丢弃)
        public static func decode(_ line: String) -> (type: String, v: Int, name: String, mid: String)? {
            guard line.count <= maxLine,
                  let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let type = obj["t"] as? String,
                  types.contains(type),
                  let v = obj["v"] as? Int, v == protoVersion else { return nil }
            return (type, v, obj["name"] as? String ?? "", obj["mid"] as? String ?? "")
        }

        /// 机器指纹:IOPlatformUUID 哈希取 16 位十六进制(稳定/不可逆,不广播原始 UUID)。
        /// 同机多实例握手即断(老板红线:本机的鸟不跟本机的鸟通信,开多少只都不行)
        public static func machineID() -> String {
            let uuid: String = {
                let port = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/")
                defer { IOObjectRelease(port) }
                guard let cf = IORegistryEntryCreateCFProperty(
                    port, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeUnretainedValue(),
                    let s = cf as? String else { return "mac-unknown" }
                return s
            }()
            var h: UInt64 = 0xcbf29ce484222325
            for b in uuid.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
            return String(format: "%016llx", h)
        }
    }

    // MARK: - 状态

    struct Peer {
        let conn: NWConnection
        var lastRecv: TimeInterval
    }

    private(set) var peers: [String: Peer] = [:]     // 邻居名 → 连接
    private var connNames: [ObjectIdentifier: String] = [:]   // 连接 → 邻居名(入向连接收 HELLO 才知道)
    private var lineBuf: [ObjectIdentifier: String] = [:]
    var onlineNames: [String] { peers.keys.sorted() }

    /// 事件回调(主线程;KingfisherPetApp 注入:配对弹窗/演出/托盘刷新)
    var onEvent: ((Event) -> Void)?
    enum Event {
        case peersChanged                       // 托盘刷新
        case peepReceived(String)               // 对唱:对方叫了一声(我们应答)
        case visitRequest(String)               // 串门请求(已配对才走到这)
        case fishReceived(String)               // 收到送鱼
    }

    // MARK: - 配对(隐私红线)

    private static let kAllowed = "kingfisher.lan.allowed"       // [String]
    private static let kDenied = "kingfisher.lan.denied"         // [String]
    var allowed: [String] { UserDefaults.standard.stringArray(forKey: Self.kAllowed) ?? [] }
    var denied: [String] { UserDefaults.standard.stringArray(forKey: Self.kDenied) ?? [] }
    func allowPeer(_ name: String) {
        guard !allowed.contains(name) else { return }
        UserDefaults.standard.set(allowed + [name], forKey: Self.kAllowed)
    }
    func denyPeer(_ name: String) {
        guard !denied.contains(name) else { return }
        UserDefaults.standard.set(denied + [name], forKey: Self.kDenied)
    }
    /// 串门冷却(每邻居名持久化;双向各自记对方名=每对邻居一个冷却)
    private static func visitKey(_ name: String) -> String { "kingfisher.lan.visit.\(name)" }
    func visitCooldownPassed(_ name: String) -> Bool {
        Date().timeIntervalSince(UserDefaults.standard.object(forKey: Self.visitKey(name)) as? Date ?? .distantPast)
            >= Lan.visitCooldown
    }
    func markVisit(_ name: String) {
        UserDefaults.standard.set(Date(), forKey: Self.visitKey(name))
    }

    // MARK: - 生命周期

    private var browser: NWBrowser?
    private var listener: NWListener?
    private var heartbeatTimer: Timer?
    private(set) var myName: String = ""
    private let myMid: String = Lan.machineID()

    var isEnabled: Bool { listener != nil }

    /// 开启:昵称(首次生成随机代号并记住)+ 注册服务 + 浏览;关闭:全撤
    func setEnabled(_ on: Bool) {
        if on { start() } else { stop() }
    }

    private func start() {
        guard listener == nil else { return }
        myName = UserDefaults.standard.string(forKey: "kingfisher.lan.name") ?? Lan.randomCodename()
        UserDefaults.standard.set(myName, forKey: "kingfisher.lan.name")
        do {
            let l = try NWListener(using: .tcp, on: .any)
            l.service = NWListener.Service(name: myName, type: Lan.serviceType)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.serviceRegistrationUpdateHandler = { [weak self] _ in self?.browse() }
            l.start(queue: .global(qos: .utility))
            listener = l
            kfLog("lan: 服务已注册 \(myName)")
            heartbeatTimer?.invalidate()
            let t = Timer(timeInterval: Lan.heartbeat, repeats: true) { [weak self] _ in
                self?.heartbeat()
            }
            RunLoop.main.add(t, forMode: .common)
            heartbeatTimer = t
        } catch {
            kfLog("lan: 监听失败 \(error)")
        }
    }

    private func stop() {
        browser?.cancel(); browser = nil
        listener?.cancel(); listener = nil
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        for (_, p) in peers { p.conn.cancel() }
        let had = !peers.isEmpty
        peers.removeAll(); connNames.removeAll(); lineBuf.removeAll()
        if had { DispatchQueue.main.async { self.onEvent?(.peersChanged) } }
        kfLog("lan: 已关闭")
    }

    /// 浏览:服务名 > 自己名字的邻居由我方发起连接(< 的由对方连我,避免双连接)
    private func browse() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let b = NWBrowser(for: .bonjour(type: Lan.serviceType, domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            for r in results {
                guard case let .service(name, _, _, _) = r.endpoint,
                      name > self.myName, self.peers[name] == nil else { continue }
                kfLog("lan: 发现邻居 \(name),发起连接")
                let c = NWConnection(to: r.endpoint, using: .tcp)
                self.connect(c, peerName: name)
            }
        }
        b.start(queue: .global(qos: .utility))
        browser = b
    }

    private func connect(_ c: NWConnection, peerName: String) {
        peers[peerName] = Peer(conn: c, lastRecv: CACurrentMediaTime())
        connNames[ObjectIdentifier(c)] = peerName
        c.stateUpdateHandler = { [weak self] st in
            guard let self = self else { return }
            switch st {
            case .ready: self.send(c, obj: ["t": "HELLO", "v": Lan.protoVersion, "name": self.myName,
                                            "mid": self.myMid,
                                            "theme": SpriteLibrary.shared.currentTheme])
            case .failed, .cancelled: self.drop(peerName)
            default: break
            }
        }
        c.start(queue: .global(qos: .utility))
        receiveLoop(c)
    }

    private func accept(_ c: NWConnection) {
        c.stateUpdateHandler = { [weak self] st in
            guard let self = self else { return }
            if case .failed = st, let n = self.connNames[ObjectIdentifier(c)] { self.drop(n) }
        }
        c.start(queue: .global(qos: .utility))
        receiveLoop(c)
    }

    // MARK: - 收发

    private func send(_ c: NWConnection, obj: [String: Any]) {
        guard let d = Lan.encode(obj) else { return }
        c.send(content: d, completion: .contentProcessed { _ in })
    }

    private func receiveLoop(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: Lan.maxLine) { [weak self] data, _, isComplete, err in
            guard let self = self else { return }
            if let d = data, !d.isEmpty { self.feed(d, conn: c) }
            if err == nil && !isComplete {
                self.receiveLoop(c)
            } else if let n = self.connNames[ObjectIdentifier(c)] {
                self.drop(n)
            }
        }
    }

    /// 按行切包喂协议
    private func feed(_ data: Data, conn c: NWConnection) {
        let key = ObjectIdentifier(c)
        let chunk = (lineBuf[key] ?? "") + String(decoding: data, as: UTF8.self)
        var lines = chunk.components(separatedBy: "\n")
        lineBuf[key] = lines.removeLast()
        for line in lines where !line.isEmpty {
            guard let m = Lan.decode(line) else { continue }
            DispatchQueue.main.async { self.handle(m, conn: c) }
        }
    }

    private func handle(_ m: (type: String, v: Int, name: String, mid: String), conn c: NWConnection) {
        let key = ObjectIdentifier(c)
        if m.type == "HELLO" {
            // 同机实例互斥:机器指纹相同 → 回 BYE 断开,不入邻居册
            if !m.mid.isEmpty, m.mid == myMid {
                kfLog("lan: 同机实例(\(m.name)),按协议断开")
                send(c, obj: ["t": "BYE", "v": Lan.protoVersion, "name": myName])
                c.cancel()
                return
            }
            let n = m.name
            if peers[n] == nil {
                peers[n] = Peer(conn: c, lastRecv: CACurrentMediaTime())
                connNames[key] = n
                // 入向连接回敬 HELLO(让对方也知道我是谁)
                send(c, obj: ["t": "HELLO", "v": Lan.protoVersion, "name": myName,
                              "mid": myMid,
                              "theme": SpriteLibrary.shared.currentTheme])
                onEvent?(.peersChanged)
                kfLog("lan: 邻居上线 \(n)")
            }
            return
        }
        guard let n = connNames[key], peers[n] != nil else { return }
        peers[n]?.lastRecv = CACurrentMediaTime()
        switch m.type {
        case "PING": send(c, obj: ["t": "PONG", "v": Lan.protoVersion, "name": myName])
        case "PONG": break
        case "PEEP":
            guard !denied.contains(n) else { send(c, obj: ["t": "BUSY", "v": Lan.protoVersion, "name": myName]); return }
            onEvent?(.peepReceived(n))
        case "VISIT":
            guard allowed.contains(n), visitCooldownPassed(n) else {
                send(c, obj: ["t": "BUSY", "v": Lan.protoVersion, "name": myName]); return
            }
            markVisit(n)
            onEvent?(.visitRequest(n))
        case "FISH":
            guard allowed.contains(n) else { send(c, obj: ["t": "BUSY", "v": Lan.protoVersion, "name": myName]); return }
            onEvent?(.fishReceived(n))
        case "BYE": drop(n)
        default: break
        }
    }

    private func heartbeat() {
        let now = CACurrentMediaTime()
        for (n, p) in peers {
            if now - p.lastRecv > Lan.peerTimeout { drop(n); continue }
            send(p.conn, obj: ["t": "PING", "v": Lan.protoVersion, "name": myName])
        }
    }

    private func drop(_ name: String) {
        guard let p = peers.removeValue(forKey: name) else { return }
        let key = ObjectIdentifier(p.conn)
        connNames[key] = nil
        lineBuf[key] = nil
        p.conn.cancel()
        kfLog("lan: 邻居离线 \(name)")
        DispatchQueue.main.async { self.onEvent?(.peersChanged) }
    }

    // MARK: - 主动动作(App/Behavior 调)

    func sendPeep() {
        for (n, p) in peers where allowed.contains(n) {
            send(p.conn, obj: ["t": "PEEP", "v": Lan.protoVersion, "name": myName])
        }
    }
    /// 请求去对方屏幕串门(对方已配对+冷却过才演)
    func requestVisit() -> Bool {
        guard let target = onlineNames.first(where: allowed.contains),
              visitCooldownPassed(target),
              let p = peers[target] else { return false }
        markVisit(target)
        send(p.conn, obj: ["t": "VISIT", "v": Lan.protoVersion, "name": myName])
        return true
    }
    /// 给邻居送鱼(菜单)
    func sendFish() -> Bool {
        guard let target = onlineNames.first(where: allowed.contains), let p = peers[target] else { return false }
        send(p.conn, obj: ["t": "FISH", "v": Lan.protoVersion, "name": myName])
        return true
    }
}
