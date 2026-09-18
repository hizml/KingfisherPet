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
        public static let types = ["HELLO", "PING", "PONG", "PEEP", "VISIT", "FISH", "BUSY", "BYE", "PAIR", "UNPAIR"]

        public static func encode(_ obj: [String: Any]) -> Data? {
            guard JSONSerialization.isValidJSONObject(obj),
                  let d = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
            return d.count + 1 <= maxLine ? d + Data([0x0A]) : nil
        }

        /// 解析一行:超长/坏 JSON/版本不认识/类型不在白名单 → nil(调用方静默丢弃)
        public static func decode(_ line: String) -> (type: String, v: Int, name: String, mid: String, token: String)? {
            guard line.count <= maxLine,
                  let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let type = obj["t"] as? String,
                  types.contains(type),
                  let v = obj["v"] as? Int, v == protoVersion else { return nil }
            return (type, v, obj["name"] as? String ?? "", obj["mid"] as? String ?? "",
                obj["token"] as? String ?? "")   // 身份令牌(冒名防线)
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
    private var peepAnswerAt: [String: Double] = [:]   // 对唱应答冷却(每邻居 10s)
    enum Event {
        case peersChanged                       // 托盘刷新
        case peepReceived(String)               // 对唱:对方叫了一声(我们应答)
        case visitRequest(String)               // 串门请求(已配对才走到这)
        case fishReceived(String)               // 收到送鱼
    }

    // MARK: - 配对(隐私红线)。v1.7.20 全双向:PAIR/UNPAIR 同步"对方允许了我",
    // 双向配对 = allowed(我允许了对方)&& inbound(对方允许了我)——串门/送鱼按双向放行

    private static let kAllowed = "kingfisher.lan.allowed"       // [String]
    private static let kDenied = "kingfisher.lan.denied"         // [String]
    private static let kInbound = "kingfisher.lan.inbound"       // [String] 对方端已允许了我(PAIR 同步)
    private static let kMyToken = "kingfisher.lan.token"          // 本机身份令牌(随机 16 hex,一次生成)
    private static let kTokens = "kingfisher.lan.tokens"          // [String:String] 邻居名→对方令牌(PAIR 首次落账)
    var allowed: [String] { UserDefaults.standard.stringArray(forKey: Self.kAllowed) ?? [] }
    var denied: [String] { UserDefaults.standard.stringArray(forKey: Self.kDenied) ?? [] }
    var inbound: [String] { UserDefaults.standard.stringArray(forKey: Self.kInbound) ?? [] }
    /// 本机身份令牌(所有出站消息携带;代号可被冒名,令牌不能)
    var myToken: String {
        if let t = UserDefaults.standard.string(forKey: Self.kMyToken), !t.isEmpty { return t }
        let t = String(format: "%016llx", UInt64.random(in: UInt64.min...UInt64.max))
        UserDefaults.standard.set(t, forKey: Self.kMyToken)
        return t
    }
    private var tokens: [String: String] {
        UserDefaults.standard.dictionary(forKey: Self.kTokens) as? [String: String] ?? [:]
    }
    /// 令牌落账(first-wins:已存不同=疑似假冒抢注 → false)
    @discardableResult
    private func rememberToken(_ name: String, _ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        var all = tokens
        if let t = all[name] { return t == token }
        all[name] = token
        UserDefaults.standard.set(all, forKey: Self.kTokens)
        return true
    }
    private func tokenMatches(_ name: String, _ token: String) -> Bool {
        guard let t = tokens[name] else { return true }   // 未落账(还没交换过)不拦:动作另有 allowed 墙
        return t == token
    }
    func allowPeer(_ name: String) {
        if !allowed.contains(name) {
            UserDefaults.standard.set(allowed + [name], forKey: Self.kAllowed)
        }
        UserDefaults.standard.set(denied.filter { $0 != name }, forKey: Self.kDenied)   // 允许即解除拒绝
        notifyPair(name, paired: true)
    }
    func denyPeer(_ name: String) {
        if !denied.contains(name) {
            UserDefaults.standard.set(denied + [name], forKey: Self.kDenied)
        }
        UserDefaults.standard.set(allowed.filter { $0 != name }, forKey: Self.kAllowed)
        notifyPair(name, paired: false)
    }
    /// 名单管理:移除「我已允许」(取消授权;不改变拒绝态)
    func removePeer(_ name: String) {
        UserDefaults.standard.set(allowed.filter { $0 != name }, forKey: Self.kAllowed)
        UserDefaults.standard.set(denied.filter { $0 != name }, forKey: Self.kDenied)
        UserDefaults.standard.set(inbound.filter { $0 != name }, forKey: Self.kInbound)
        notifyPair(name, paired: false)
    }
    /// 双向已配对(串门/送鱼的放行条件)
    func isDualPaired(_ name: String) -> Bool { allowed.contains(name) && inbound.contains(name) }
    /// 我方配对决定 → 在线即通知对端(离线则等重连握手时补发)
    private func notifyPair(_ name: String, paired: Bool) {
        guard let p = peers[name] else { return }
        send(p.conn, obj: ["t": paired ? "PAIR" : "UNPAIR", "v": Lan.protoVersion, "name": myName])
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
    /// 串门冷却剩余分钟(0=可串;反馈文案用——老板两连撞冷却,只说"冷却中"等于没说)
    func visitCooldownRemainingMinutes(_ name: String) -> Int {
        let last = UserDefaults.standard.object(forKey: Self.visitKey(name)) as? Date ?? .distantPast
        return max(1, Int(ceil((Lan.visitCooldown - Date().timeIntervalSince(last)) / 60)))
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
        let had = !peers.isEmpty
        // 先广播 BYE 再断(对端立即感知,不再干等 10s 无包超时;与 Win v1.7.18 同款)
        for (_, p) in peers {
            send(p.conn, obj: ["t": "BYE", "v": Lan.protoVersion, "name": myName])
            p.conn.cancel()
        }
        peers.removeAll(); connNames.removeAll(); lineBuf.removeAll()
        if had { onEvent?(.peersChanged) }
        kfLog("lan: 已关闭")
    }

    /// 浏览:服务名 > 自己名字的邻居由我方发起连接(< 的由对方连我,避免双连接)。
    /// 线程纪律(R8 修复):所有 NW 回调第一步切主线程再碰状态——browser/connection
    /// 都是 .global 并发队列,回调线程与主线程对 peers/connNames/lineBuf 的并发读写
    /// 是未定义行为(随机崩溃源)
    private func browse() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let b = NWBrowser(for: .bonjour(type: Lan.serviceType, domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                for r in results {
                    guard case let .service(name, _, _, _) = r.endpoint,
                          name > self.myName, self.peers[name] == nil else { continue }
                    kfLog("lan: 发现邻居 \(name),发起连接")
                    let c = NWConnection(to: r.endpoint, using: .tcp)
                    self.connect(c, peerName: name)
                }
            }
        }
        b.start(queue: .global(qos: .utility))
        browser = b
    }

    private func connect(_ c: NWConnection, peerName: String) {
        peers[peerName] = Peer(conn: c, lastRecv: CACurrentMediaTime())
        connNames[ObjectIdentifier(c)] = peerName
        c.stateUpdateHandler = { [weak self] st in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch st {
                case .ready: self.send(c, obj: ["t": "HELLO", "v": Lan.protoVersion, "name": self.myName,
                                                "mid": self.myMid,
                                                "theme": SpriteLibrary.shared.currentTheme])
                case .failed, .cancelled: self.drop(peerName)
                default: break
                }
            }
        }
        c.start(queue: .global(qos: .utility))
        receiveLoop(c)
    }

    private func accept(_ c: NWConnection) {
        c.stateUpdateHandler = { [weak self] st in
            guard let self = self else { return }
            if case .failed = st {
                DispatchQueue.main.async {
                    let key = ObjectIdentifier(c)
                    if let n = self.connNames[key] { self.drop(n) }
                    self.lineBuf[key] = nil   // 匿名连接(没等到 HELLO)也清残留缓冲
                }
            }
        }
        c.start(queue: .global(qos: .utility))
        receiveLoop(c)
    }

    // MARK: - 收发

    private func send(_ c: NWConnection, obj: [String: Any]) {
        var o = obj
        o["token"] = myToken   // 身份令牌:接收端比对(冒名代号即丢)
        guard let d = Lan.encode(o) else { return }
        c.send(content: d, completion: .contentProcessed { _ in })
    }

    private func receiveLoop(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: Lan.maxLine) { [weak self] data, _, isComplete, err in
            guard let self = self else { return }
            if let d = data, !d.isEmpty {
                DispatchQueue.main.async { self.feed(d, conn: c) }   // feed 写 lineBuf:主线程
            }
            if err == nil && !isComplete {
                self.receiveLoop(c)   // 重挂留在连接队列(与连接同队列,Network 框架要求)
            } else {
                DispatchQueue.main.async {
                    let key = ObjectIdentifier(c)
                    if let n = self.connNames[key] { self.drop(n) }
                    self.lineBuf[key] = nil
                }
            }
        }
    }

    /// 按行切包喂协议(主线程)
    private func feed(_ data: Data, conn c: NWConnection) {
        let key = ObjectIdentifier(c)
        let chunk = (lineBuf[key] ?? "") + String(decoding: data, as: UTF8.self)
        // 防灌包:半行累积超上限即断(此前无上限——对端持续发不带换行的数据可无限撑大内存)
        guard chunk.count <= Lan.maxLine else {
            kfLog("lan: 超长行,断开该连接(防灌包)")
            lineBuf[key] = nil
            c.cancel()
            return
        }
        var lines = chunk.components(separatedBy: "\n")
        lineBuf[key] = lines.removeLast()
        for line in lines where !line.isEmpty {
            guard let m = Lan.decode(line) else { continue }
            handle(m, conn: c)   // feed 已在主线程,直接处理
        }
    }

    private func handle(_ m: (type: String, v: Int, name: String, mid: String, token: String), conn c: NWConnection) {
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
                // 双向配对状态随握手同步:离线期间点的允许,重连即补报
                if allowed.contains(n) {
                    send(c, obj: ["t": "PAIR", "v": Lan.protoVersion, "name": myName])
                }
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
        case "PAIR", "UNPAIR":
            // 令牌 first-wins 落账;已存不同令牌=疑似假冒抢注,整条丢弃
            if !rememberToken(n, m.token) {
                kfLog("lan: \(m.type) 令牌不符(\(n)),疑似假冒,已丢弃")
                return
            }
            let on = m.type == "PAIR"
            let cur = inbound
            let next = on ? (cur.contains(n) ? cur : cur + [n]) : cur.filter { $0 != n }
            UserDefaults.standard.set(next, forKey: Self.kInbound)
            onEvent?(.peersChanged)   // 菜单/设置窗刷新(对方刚允许了我=单向变双向)
        
        case "PEEP":
            guard !denied.contains(n) else { send(c, obj: ["t": "BUSY", "v": Lan.protoVersion, "name": myName]); return }
            guard tokenMatches(n, m.token) else {
                kfLog("lan: PEEP 令牌不符(\(n)),疑似假冒,已丢弃"); return
            }
            // 对唱应答冷却(每邻居 10s:恶意刷叫防线的轻量修法)
            let now = CACurrentMediaTime()
            if let last = peepAnswerAt[n], now - last < 10 { return }
            peepAnswerAt[n] = now
            onEvent?(.peepReceived(n))
        case "VISIT":
            guard tokenMatches(n, m.token) else {
                kfLog("lan: VISIT 令牌不符(\(n)),疑似假冒,已丢弃"); return
            }
            // 冷却只由发送端守(每对一个钟,发送方记);接收端曾双重拦截=串门"没鸟飞过来"的一半真相
            guard allowed.contains(n) else {
                send(c, obj: ["t": "BUSY", "v": Lan.protoVersion, "name": myName]); return
            }
            onEvent?(.visitRequest(n))
        case "FISH":
            guard tokenMatches(n, m.token) else {
                kfLog("lan: FISH 令牌不符(\(n)),疑似假冒,已丢弃"); return
            }
            guard allowed.contains(n) else { send(c, obj: ["t": "BUSY", "v": Lan.protoVersion, "name": myName]); return }
            onEvent?(.fishReceived(n))
        case "BYE":
            guard tokenMatches(n, m.token) else {
                kfLog("lan: BYE 令牌不符(\(n)),疑似假冒,已丢弃"); return
            }
            drop(n)
        default: break
        }
    }

    private func heartbeat() {
        let now = CACurrentMediaTime()
        // 先收集后删除(R9 修复:遍历字典期间 drop 原地 removeValue 是未定义行为)
        let timedOut = peers.filter { now - $0.value.lastRecv > Lan.peerTimeout }.map(\.key)
        for n in timedOut { drop(n) }
        for (_, p) in peers {
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
        onEvent?(.peersChanged)   // 调用方已在主线程(R8 收敛后)
    }

    // MARK: - 主动动作(App/Behavior 调)

    func sendPeep() {
        for (n, p) in peers where allowed.contains(n) {
            send(p.conn, obj: ["t": "PEEP", "v": Lan.protoVersion, "name": myName])
        }
    }
    /// 请求去对方屏幕串门(双向配对才放行;to=指定目标(子菜单),nil=第一个双向在线;
    /// 返回 nil=已发出,否则=失败原因码)
    func requestVisit(to want: String? = nil) -> String? {
        let dualOnline = onlineNames.filter { isDualPaired($0) }
        let target = want.flatMap { w in dualOnline.first { $0 == w } } ?? dualOnline.first
        guard let target else {
            return onlineNames.contains(where: allowed.contains) ? "visitNeedDual" : "visitNoPeer"
        }
        guard visitCooldownPassed(target) else { return "visitCooldown" }
        guard let p = peers[target] else { return "visitNoPeer" }
        markVisit(target)
        send(p.conn, obj: ["t": "VISIT", "v": Lan.protoVersion, "name": myName])
        return nil
    }
    /// 给邻居送鱼(双向配对才放行;to=指定目标)
    func sendFish(to want: String? = nil) -> String? {
        let dualOnline = onlineNames.filter { isDualPaired($0) }
        let target = want.flatMap { w in dualOnline.first { $0 == w } } ?? dualOnline.first
        guard let target, let p = peers[target] else { return "fishNoPeer" }
        send(p.conn, obj: ["t": "FISH", "v": Lan.protoVersion, "name": myName])
        return nil
    }
}
