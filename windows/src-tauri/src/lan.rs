// 局域网小鸟(v1.7.0 串门批):mdns-sd 发现 + TCP 换行 JSON 协议
// (HELLO/PING/PONG/PEEP/VISIT/FISH/BUSY/BYE)。对称 macOS LanBirds.swift。
// 隐私红线:广播仅昵称+主题(不含主机名/IP);配对/冷却判定在前端(localStorage)。
//
// v1.7.18 重构(CODE_REVIEW-2026-09-17 R2-R6/M16-M18):
// - STATE 锁内绝不做网络 IO(此前回敬 HELLO 同线程重锁=死锁;持锁写 TCP=坏邻居全局冻结)
// - lan_start 先 bind/注册全部成功再置位(此前失败残留 running=true=永久假启动)
// - lan_stop 完整回收:广播 BYE→逐 peer shutdown→关 listener/daemon;心跳线程按代际退出
// - 主动连接立即发 HELLO(此前从不发,对端无法登记=Win↔Win/Win↔Mac 永远配不上对)
// - 行长上限在读层强制(整行读入后再查=马后炮,无换行垃圾流可撑爆内存)
// - 外连 connect 2s 超时;全部连接写超时 3s(发送阻塞不再无限期)
// - 多网卡主机排除虚拟网卡跑 mDNS(WSL/Hyper-V 内部交换机抢组播源地址时,
//   RFC 6762 接收端按异网段源丢包 → 双端互不可见;N5105 六网卡实锤)
use mdns_sd::{IfKind, ServiceDaemon, ServiceEvent, ServiceInfo};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{Ipv4Addr, Shutdown, TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tauri::{AppHandle, Emitter};
use std::net::IpAddr;

const SERVICE_TYPE: &str = "_kingfisherpet._tcp.local.";
const PROTO_V: i64 = 1;
const MAX_LINE: usize = 1024;
const HEARTBEAT_MS: u64 = 5_000;
const PEER_TIMEOUT_SECS: u64 = 10;
const WRITE_TIMEOUT: Duration = Duration::from_secs(3);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(2);

/// 本机身份(线程启动时定格;运行期不变)
#[derive(Clone)]
struct Ident {
    name: String,
    mid: String,
    theme: String,
}

struct LanState {
    my_name: String,
    my_mid: String,
    theme: String,
    /// 邻居名 → (写端, 最后收包时刻)。连接所有权:每条连接一个读线程。
    peers: HashMap<String, (Arc<Mutex<TcpStream>>, std::time::Instant)>,
    daemon: Option<ServiceDaemon>,
    /// stop 用句柄(与 accept 线程共享同一底层 socket;accept 为非阻塞轮询,靠 running 退出)
    listener: Option<TcpListener>,
    /// 启动代际(单调递增):心跳线程不匹配即退出,防 stop 后快速重启出现双心跳
    generation: u64,
    running: bool,
}

static STATE: Mutex<Option<LanState>> = Mutex::new(None);
static GENERATION: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// 服务是否仍在指定代际运行(工作线程的退出判据)
fn lan_running(gen: u64) -> bool {
    match STATE.lock() {
        Ok(g) => match g.as_ref() {
            Some(st) => st.running && st.generation == gen,
            None => false,
        },
        Err(_) => false,
    }
}

/// 身份快照(锁内取,锁外用;调用方必须不持有 STATE)
fn ident() -> Ident {
    let g = STATE.lock().unwrap_or_else(|e| e.into_inner());
    match g.as_ref() {
        Some(st) => Ident { name: st.my_name.clone(), mid: st.my_mid.clone(), theme: st.theme.clone() },
        None => Ident { name: String::new(), mid: String::new(), theme: String::new() },
    }
}

fn emit_event(app: &AppHandle, kind: &str, name: &str) {
    let _ = app.emit("lan-event", serde_json::json!({ "type": kind, "name": name }));
}

/// 组一行并写 socket。纪律:只准在**不持有 STATE 锁**的上下文调用(身份由调用方传入)
fn send_line(stream: &Arc<Mutex<TcpStream>>, t: &str, id: &Ident) {
    let mut obj = serde_json::json!({ "t": t, "v": PROTO_V, "name": id.name });
    if t == "HELLO" {
        obj["theme"] = serde_json::json!(id.theme);
        obj["mid"] = serde_json::json!(id.mid);
    }
    let s = obj.to_string();
    if s.len() + 1 > MAX_LINE { return; }
    if let Ok(mut g) = stream.lock() {
        // 写失败(超时/断开)不传播:对端死亡由 10s 无包超时收尸
        let _ = writeln!(g, "{}", s);
    }
}

/// 处理一行:登记/心跳/转发给前端(配对与演出由前端裁决)。
/// 锁内只算不发:所有 send_line 都在 STATE 锁释放之后(评审 R2/R5 的核心修复)
fn handle_line(app: &AppHandle, line: &str, stream: &Arc<Mutex<TcpStream>>, peer_of_conn: &mut Option<String>) {
    let line = line.trim_end();
    if line.len() > MAX_LINE { return; }
    let obj: serde_json::Value = match serde_json::from_str(line) { Ok(o) => o, Err(_) => return };
    if obj["v"].as_i64() != Some(PROTO_V) { return; }
    let t = match obj["t"].as_str() { Some(s) => s.to_string(), None => return };
    let name = obj["name"].as_str().unwrap_or("").to_string();

    if t == "HELLO" {
        let mid = obj["mid"].as_str().unwrap_or("");
        let mut same_machine = false;
        let mut is_new = false;
        {
            let mut g = match STATE.lock() { Ok(g) => g, Err(_) => return };
            let Some(st) = g.as_mut() else { return };
            if !mid.is_empty() && mid == st.my_mid {
                same_machine = true;   // 同机实例:回 BYE 断开(老板红线)
            } else if name.is_empty() || name == st.my_name {
                return;
            } else {
                is_new = !st.peers.contains_key(&name);
                st.peers.entry(name.clone()).or_insert_with(|| (stream.clone(), std::time::Instant::now()));
            }
        }
        let id = ident();
        if same_machine {
            crate::kflog::kflog(&format!("lan: 同机实例({}),按协议断开", name));
            send_line(stream, "BYE", &id);
            let _ = stream.lock().map(|c| c.shutdown(Shutdown::Both));
            return;
        }
        *peer_of_conn = Some(name.clone());
        send_line(stream, "HELLO", &id);   // 回敬 HELLO(入向连接对方不知道我是谁)——锁外发送
        if crate::lan_allowed(&name) {
            send_line(stream, "PAIR", &id);   // 双向配对状态同步:重连即补报「我允许了你」
        }
        if is_new {
            crate::kflog::kflog(&format!("lan: 邻居上线 {}", name));
            emit_event(app, "peersChanged", &name);
        }
        return;
    }
    // 非 HELLO:须已登记
    let Some(pname) = peer_of_conn.clone() else { return };
    {
        let mut g = match STATE.lock() { Ok(g) => g, Err(_) => return };
        let Some(st) = g.as_mut() else { return };
        if let Some(p) = st.peers.get_mut(&pname) { p.1 = std::time::Instant::now(); }
    }
    let id = ident();
    match t.as_str() {
        "PING" => send_line(stream, "PONG", &id),
        "PONG" => {}
        // 双向配对状态同步:「对方端已允许了我」。持久化进 lan_cfg.inbound 并广播给前端
        "PAIR" => {
            crate::lan_pair_update(&pname, true);
            emit_event(app, "pair", &pname);
        }
        "UNPAIR" => {
            crate::lan_pair_update(&pname, false);
            emit_event(app, "pair", &pname);
        }
        "PEEP" | "VISIT" | "FISH" | "BYE" => emit_event(app, &t.to_lowercase(), &pname),
        _ => {}
    }
}

/// 连接读循环:按行喂 handle_line;连接断 → 邻居下线
fn reader_loop(app: AppHandle, stream: TcpStream, mark_name: Option<String>, id: Ident) {
    let _ = stream.set_write_timeout(Some(WRITE_TIMEOUT));
    let stream = Arc::new(Mutex::new(stream));
    let mut peer: Option<String> = mark_name;
    // 主动连接方先自我介绍(R6:此前从不发 HELLO,被动方在登记前丢弃一切消息,
    // 主动方又因收不到 PONG 被 10s 超时踢除 → 永远配不上对)
    if peer.is_some() {
        send_line(&stream, "HELLO", &id);
        if let Some(n) = &peer {
            if crate::lan_allowed(n) { send_line(&stream, "PAIR", &id); }   // 双向状态随握手同步
        }
    }
    // 名字大者主动连的场景,连接前已知对方名(先登记,HELLO 再刷新)
    if let Some(n) = &peer {
        let mut g = match STATE.lock() { Ok(g) => g, Err(_) => return };
        if let Some(st) = g.as_mut() {
            st.peers.entry(n.clone()).or_insert_with(|| (stream.clone(), std::time::Instant::now()));
        }
    }
    let clone = stream.lock().map(|g| g.try_clone()).ok().map(|r| r.ok()).flatten();
    let Some(read_side) = clone else { return };
    let mut reader = BufReader::new(read_side);
    let mut buf: Vec<u8> = Vec::new();
    loop {
        buf.clear();
        // 读层强制行长上限(M16:整行读入内存后再检查是马后炮,防无换行垃圾流撑爆内存)
        let n = {
            let mut limited = (&mut reader).take((MAX_LINE + 1) as u64);
            match limited.read_until(b'\n', &mut buf) { Ok(n) => n, Err(_) => break }
        };
        if n == 0 { break; }   // EOF
        if buf.len() > MAX_LINE {
            crate::kflog::kflog("lan: 超长行,断开该连接(防灌包)");
            break;
        }
        let line = String::from_utf8_lossy(&buf).into_owned();
        let s2 = stream.clone();
        handle_line(&app, &line, &s2, &mut peer);
    }
    // 断开:清邻居(仅当映射还是这条连接,防误删新连接)
    if let Some(n) = &peer {
        {
            let mut g = match STATE.lock() { Ok(g) => g, Err(_) => return };
            if let Some(st) = g.as_mut() {
                let same = st.peers.get(n).map(|(s, _)| Arc::ptr_eq(s, &stream)).unwrap_or(false);
                if same { st.peers.remove(n); }
            }
        }
        emit_event(&app, "peersChanged", n);
    }
}

#[tauri::command]
pub fn lan_start(app: AppHandle, name: String, theme: String) -> Result<(), String> {
    // 参数校验(评审建议:IPC 面不信任前端载荷)
    let name = name.trim().to_string();
    if name.is_empty() || name.len() > 64 || name.chars().any(|c| c.is_control()) {
        return Err(format!("lan: 非法代号(len={})", name.len()));
    }
    let theme = theme.trim().chars().take(32).collect::<String>();
    {
        let g = STATE.lock().map_err(|e| e.to_string())?;
        if g.as_ref().map(|s| s.running).unwrap_or(false) { return Ok(()); }
    }
    // 资源先备齐,全部成功才置位(R3:此前先置 running=true,失败残留=之后 start 永远假成功)
    let listener = TcpListener::bind("0.0.0.0:0").map_err(|e| format!("bind: {e}"))?;
    let _ = listener.set_nonblocking(true);   // accept 轮询化:stop 后线程可退(不再永阻塞在 incoming)
    let listener_stop = listener.try_clone().map_err(|e| format!("listener clone: {e}"))?;
    let port = listener.local_addr().map_err(|e| format!("addr: {e}"))?.port();
    let daemon = ServiceDaemon::new().map_err(|e| format!("mdns: {e}"))?;
    // 多网卡防线:虚拟/隧道网卡不跑 mDNS(N5105 实锤:WSL vSwitch 抢组播源地址,
    // 源 IP 不在接收端网段 → RFC 6762 判火星包丢弃 → 双端互不可见)
    for ip in virtual_adapter_ipv4s() {
        match daemon.disable_interface(IfKind::Addr(IpAddr::V4(ip))) {
            Ok(()) => crate::kflog::kflog(&format!("lan: mDNS 排除虚拟网卡 {ip}")),
            Err(e) => crate::kflog::kflog(&format!("lan: disable_interface({ip}) 失败: {e}")),
        }
    }
    let svc = ServiceInfo::new(SERVICE_TYPE, &name, &lan_hostname(),
                               IpAddr::from(Ipv4Addr::UNSPECIFIED), port, HashMap::<String, String>::new())
        .map_err(|e| format!("svc: {e}"))?
        .enable_addr_auto();
    daemon.register(svc).map_err(|e| format!("register: {e}"))?;

    let generation = 1 + GENERATION.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let id = Ident { name: name.clone(), mid: machine_id(), theme };
    let daemon2 = daemon.clone();   // browse 线程用(daemon 本体随后 move 进 STATE)
    {
        let mut g = STATE.lock().map_err(|e| e.to_string())?;
        if g.as_ref().map(|s| s.running).unwrap_or(false) {
            // 竞态:期间另一路已启动 → 拆掉自己这套资源返回
            drop(g);
            let _ = daemon.shutdown();
            return Ok(());
        }
        *g = Some(LanState { my_name: name.clone(), my_mid: id.mid.clone(), theme: id.theme.clone(),
                             peers: HashMap::new(), daemon: Some(daemon), listener: Some(listener_stop),
                             generation, running: true });
    }

    // 接入循环:非阻塞轮询(running 翻 false 后 50ms 内退出,不再泄漏线程)
    let app_accept = app.clone();
    let id_accept = id.clone();
    std::thread::spawn(move || {
        loop {
            match listener.accept() {
                Ok((c, _)) => {
                    let _ = c.set_nodelay(true);
                    let _ = c.set_write_timeout(Some(WRITE_TIMEOUT));
                    let app2 = app_accept.clone();
                    let id2 = id_accept.clone();
                    std::thread::spawn(move || reader_loop(app2, c, None, id2));
                }
                Err(_) => {
                    if !lan_running(generation) { break; }
                    std::thread::sleep(Duration::from_millis(50));
                }
            }
        }
    });

    // 浏览:发现名字 > 自己的邻居 → 主动连(避免双连接;macOS 同款规则)。
    // daemon.shutdown() 会关闭事件通道 → recv 返回 Err → 线程自退
    let my_name2 = name.clone();
    let app3 = app.clone();
    let id3 = id.clone();
    std::thread::spawn(move || {
        let receiver = match daemon2.browse(SERVICE_TYPE) { Ok(r) => r, Err(e) => {
            crate::kflog::kflog(&format!("lan: browse 失败: {e}")); return;
        } };
        while let Ok(ev) = receiver.recv() {
            if let ServiceEvent::ServiceResolved(info) = ev {
                let peer = info.get_fullname().to_string();
                // full_name 形如 "翠鸟-XXXX._kingfisherpet._tcp.local";取实例名部分
                let short = peer.split('.').next().unwrap_or("").to_string();
                if short.is_empty() || short <= my_name2 { continue; }
                {
                    let g = match STATE.lock() { Ok(g) => g, Err(_) => continue };
                    let Some(st) = g.as_ref() else { continue };
                    if st.peers.contains_key(&short) { continue; }
                }
                let addrs = info.get_addresses();
                // 优先 IPv4(虚拟网卡已被排除,这里自然只剩真实地址)
                let addr = addrs.iter().find(|a| a.is_ipv4()).or_else(|| addrs.iter().next());
                let Some(addr) = addr else { continue };
                // connect 限时(M17:默认阻塞式 connect 在 Windows 上 ~21s,一个不可达
                // 地址会拖住整个 browse 串行循环)
                let sa = std::net::SocketAddr::new(*addr, info.get_port());
                let Ok(c) = TcpStream::connect_timeout(&sa, CONNECT_TIMEOUT) else { continue };
                let _ = c.set_nodelay(true);
                let _ = c.set_write_timeout(Some(WRITE_TIMEOUT));
                let app4 = app3.clone();
                let id4 = id3.clone();
                crate::kflog::kflog(&format!("lan: 发现邻居 {},发起连接", short));
                std::thread::spawn(move || reader_loop(app4, c, Some(short), id4));
            }
        }
    });

    // 心跳:5s PING 全员;10s 未收包判离线。代际不匹配即退出(防双心跳);
    // 目标先在锁内收集、锁外发送(评审 R5:绝不持锁写 socket)
    let app5 = app.clone();
    let hb_name = id.name.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_millis(HEARTBEAT_MS));
        let (targets, gone) = {
            let mut g = match STATE.lock() { Ok(g) => g, Err(_) => return };
            let Some(st) = g.as_mut() else { return };
            if !st.running || st.generation != generation { return; }
            let mut targets: Vec<Arc<Mutex<TcpStream>>> = Vec::new();
            let mut gone: Vec<String> = Vec::new();
            for (n, (s, last)) in st.peers.iter_mut() {
                if last.elapsed().as_secs() > PEER_TIMEOUT_SECS { gone.push(n.clone()); continue; }
                targets.push(s.clone());
            }
            for n in &gone { st.peers.remove(n); }   // 遍历结束后再删(不重蹈遍历中删改)
            (targets, gone)
        };
        let ping_id = Ident { name: hb_name.clone(), mid: String::new(), theme: String::new() };
        for s in &targets { send_line(s, "PING", &ping_id); }
        for n in gone { emit_event(&app5, "peersChanged", &n); }
    });

    crate::kflog::kflog(&format!("lan: 服务启动 {}", name));
    Ok(())
}

#[tauri::command]
pub fn lan_stop() -> Result<(), String> {
    let (my_name, peers, daemon, listener) = {
        let mut g = STATE.lock().map_err(|e| e.to_string())?;
        let Some(st) = g.as_mut() else { return Ok(()) };
        st.running = false;   // 心跳/accept 轮询线程随后自退(STATE 置 None 亦为退出判据)
        let peers = std::mem::take(&mut st.peers);
        let daemon = st.daemon.take();
        let listener = st.listener.take();
        (st.my_name.clone(), peers, daemon, listener)
    };   // 锁到此释放:以下网络收尾绝不持锁
    // 先广播 BYE(对端立即感知下线,不再干等 10s 超时),再硬断
    let bye_id = Ident { name: my_name, mid: String::new(), theme: String::new() };
    for (_, (s, _)) in &peers { send_line(s, "BYE", &bye_id); }
    for (_, (s, _)) in peers {
        let _ = s.lock().map(|c| c.shutdown(Shutdown::Both));   // 读线程随即 EOF 退出
    }
    drop(listener);
    if let Some(d) = daemon { let _ = d.shutdown(); }
    if let Ok(mut g) = STATE.lock() { *g = None; }
    crate::kflog::kflog("lan: 已关闭");
    Ok(())
}

/// 前端主动动作。v1.7.21 点对点纪律(老板实锤"送一条鱼不能全体+亲密度"):
/// - PEEP 对唱 = 广播(环境音性质,全邻居应答)
/// - VISIT/FISH = 点对点:target 指定收件人;未指定则发给第一个【双向已配对】在线邻居
/// 返回 Some(收件人名) = 送达;None = 没有合格收件人
#[tauri::command]
pub fn lan_send(kind: String, target: Option<String>) -> Result<Option<String>, String> {
    let t = match kind.as_str() {
        "peep" => "PEEP", "visit" => "VISIT", "fish" => "FISH",
        _ => return Ok(None),
    };
    let (targets, my_name) = {
        let g = STATE.lock().map_err(|e| e.to_string())?;
        let Some(st) = g.as_ref() else { return Ok(None) };
        let mut targets: Vec<(String, Arc<Mutex<TcpStream>>)> = Vec::new();
        match (&target, t) {
            (Some(name), "VISIT") | (Some(name), "FISH") => {
                if let Some((s, _)) = st.peers.get(name) { targets.push((name.clone(), s.clone())); }
            }
            (None, "VISIT") | (None, "FISH") => {
                // 未指定目标:取第一个双向已配对(我允许+对方允许)的在线邻居
                let c = crate::lan_cfg_load();
                if let Some((n, (s, _))) = st.peers.iter()
                    .find(|(n, _)| c.allowed.contains(n) && c.inbound.contains(n)) {
                    targets.push((n.clone(), s.clone()));
                }
            }
            _ => {   // PEEP:广播
                for (n, (s, _)) in st.peers.iter() { targets.push((n.clone(), s.clone())); }
            }
        }
        (targets, st.my_name.clone())
    };   // 锁外发送(评审 R5)
    let id = Ident { name: my_name, mid: String::new(), theme: String::new() };
    let mut sent_to: Option<String> = None;
    for (n, s) in &targets { send_line(s, t, &id); if sent_to.is_none() { sent_to = Some(n.clone()); } }
    Ok(sent_to)
}

/// 本端配对决定 → 通知对端(不在线则忽略:重连握手时 HELLO 后会自动补发 PAIR)
pub fn lan_notify_pair(name: &str, paired: bool, app: &AppHandle) {
    let (target, id) = {
        let g = STATE.lock().unwrap_or_else(|e| e.into_inner());
        let Some(st) = g.as_ref() else { return };
        match st.peers.get(name) {
            Some((s, _)) => (s.clone(), Ident { name: st.my_name.clone(), mid: st.my_mid.clone(), theme: st.theme.clone() }),
            None => return,
        }
    };
    send_line(&target, if paired { "PAIR" } else { "UNPAIR" }, &id);
    let _ = app;
}

/// 双向已配对的在线邻居(托盘子菜单数据源:串门/送鱼选目标)
pub fn dual_online_names() -> Vec<String> {
    let c = crate::lan_cfg_load();
    let g = STATE.lock().unwrap_or_else(|e| e.into_inner());
    let Some(st) = g.as_ref() else { return vec![] };
    let mut v: Vec<String> = st.peers.keys()
        .filter(|n| c.allowed.contains(n) && c.inbound.contains(n))
        .cloned().collect();
    v.sort();
    v
}

/// 在线邻居名单(托盘状态行用)
#[tauri::command]
pub fn lan_peers() -> Vec<String> {
    let g = STATE.lock().unwrap_or_else(|e| e.into_inner());
    let Some(st) = g.as_ref() else { return vec![] };
    let mut v: Vec<String> = st.peers.keys().cloned().collect();
    v.sort();
    v
}

/// mDNS 主机名(SRV 记录 target)。mdns-sd 的 register() 强制要求以 ".local." 结尾——
/// v1.7.0 起一直传裸 COMPUTERNAME 被拒,但旧代码 `let _ =` 吞错+在注册前就打
/// 「服务启动」日志,= Win 端 mDNS 服务从未注册成功过(v1.7.18 的错误留痕首次照出)。
/// 隐私红线(广播不含主机名):用机器指纹哈希派生,不泄漏 COMPUTERNAME。
fn lan_hostname() -> String {
    format!("kf-{}.local.", &machine_id()[..8])
}

/// 机器指纹:机器名 FNV 哈希 16 位十六进制(稳定/不可逆,不广播原名)。
/// 同机多实例握手即断(老板红线:本机的鸟不跟本机的鸟通信)
fn machine_id() -> String {
    let src = std::env::var("COMPUTERNAME").unwrap_or_else(|_| "kf-win".into());
    let mut h: u64 = 0xcbf29ce484222325;
    for b in src.bytes() { h = (h ^ b as u64).wrapping_mul(0x100000001b3); }
    format!("{:016x}", h)
}

pub struct Lan;

impl Lan {
    /// 随机代号(与前端 shared.mjs lanCodename 同格式;Rust 侧兜底生成)
    pub fn lanCodename_stub() -> String {
        use std::time::{SystemTime, UNIX_EPOCH};
        let n = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.subsec_nanos() as u64).unwrap_or(0);
        format!("翠鸟-{:04X}", (n % 0x10000) as u32)
    }
}

/// 枚举「不该跑 mDNS」的虚拟/隧道网卡的 IPv4 地址。
/// 判据:接口类型为环回/虚拟/隧道,或友好名带已知虚拟标识。枚举失败返回空
/// (=不过滤,退回全接口行为)。只影响 mDNS,不影响 TCP 连接地址选择。
#[cfg(windows)]
fn virtual_adapter_ipv4s() -> Vec<Ipv4Addr> {
    use windows::Win32::NetworkManagement::IpHelper::{
        GetAdaptersAddresses, IP_ADAPTER_ADDRESSES_LH,
        GAA_FLAG_SKIP_ANYCAST, GAA_FLAG_SKIP_DNS_SERVER, GAA_FLAG_SKIP_MULTICAST,
    };
    const AF_INET: u32 = 2;
    const IF_OPER_STATUS_UP: i32 = 1;
    // IfType(IFTYPE, RFC 2863):24=softwareLoopback 53=propVirtual 131=tunnel
    const BAD_TYPES: [u32; 3] = [24, 53, 131];
    const MARKERS: [&str; 13] = [
        "wsl", "default switch", "内部", "internal", "zerotier", "tailscale",
        "openvpn", "tap-", "tun ", "loopback", "vmware", "vbox", "bluestacks",
    ];

    let flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER;
    let mut buf: Vec<u8> = vec![0; 16 * 1024];
    let mut size: u32 = buf.len() as u32;
    let mut rc = unsafe {
        GetAdaptersAddresses(AF_INET, flags, None, Some(buf.as_mut_ptr() as *mut IP_ADAPTER_ADDRESSES_LH), &mut size)
    };
    if rc == 111 && size as usize > buf.len() {
        // ERROR_BUFFER_OVERFLOW:按系统要求扩容重试一次
        buf = vec![0; size as usize];
        rc = unsafe {
            GetAdaptersAddresses(AF_INET, flags, None, Some(buf.as_mut_ptr() as *mut IP_ADAPTER_ADDRESSES_LH), &mut size)
        };
    }
    if rc != 0 { return vec![]; }

    let mut out = Vec::new();
    let mut cur = buf.as_ptr() as *const IP_ADAPTER_ADDRESSES_LH;
    while !cur.is_null() {
        unsafe {
            let a = &*cur;
            if a.OperStatus.0 == IF_OPER_STATUS_UP {
                let fname = if a.FriendlyName.is_null() {
                    String::new()
                } else {
                    String::from_utf16_lossy(a.FriendlyName.as_wide())
                };
                let lf = fname.to_lowercase();
                if BAD_TYPES.contains(&a.IfType) || MARKERS.iter().any(|m| lf.contains(m)) {
                    let mut ua = a.FirstUnicastAddress;
                    while !ua.is_null() {
                        let u = &*ua;
                        let sa = u.Address.lpSockaddr;
                        if !sa.is_null() && *(sa as *const u16) == AF_INET as u16 {
                            // sockaddr_in 布局:family(2)+port(2)+addr(4);按字节取避开字节序坑
                            let b = std::slice::from_raw_parts(sa.cast::<u8>().add(4), 4);
                            out.push(Ipv4Addr::new(b[0], b[1], b[2], b[3]));
                        }
                        ua = u.Next;
                    }
                }
            }
            cur = a.Next;
        }
    }
    out
}

#[cfg(not(windows))]
fn virtual_adapter_ipv4s() -> Vec<Ipv4Addr> { vec![] }
