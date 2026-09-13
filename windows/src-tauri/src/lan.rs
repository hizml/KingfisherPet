// 局域网小鸟(v1.7.0 串门批):mdns-sd 发现 + TCP 换行 JSON 协议
// (HELLO/PING/PONG/PEEP/VISIT/FISH/BUSY/BYE)。对称 macOS LanBirds.swift。
// 隐私红线:广播仅昵称+主题(不含主机名/IP);配对/冷却判定在前端(localStorage)。
use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tauri::{AppHandle, Emitter};
use std::net::Ipv4Addr;

const SERVICE_TYPE: &str = "_kingfisherpet._tcp.local.";
const PROTO_V: i64 = 1;
const MAX_LINE: usize = 1024;
const HEARTBEAT_MS: u64 = 5_000;
const PEER_TIMEOUT_SECS: u64 = 10;

struct LanState {
    my_name: String,
    theme: String,
    /// 邻居名 → (写端, 最后收包时刻)。连接所有权:每条连接一个读线程。
    peers: HashMap<String, (Arc<Mutex<TcpStream>>, std::time::Instant)>,
    daemon: Option<ServiceDaemon>,
    running: bool,
}

static STATE: Mutex<Option<LanState>> = Mutex::new(None);

fn emit_event(app: &AppHandle, kind: &str, name: &str) {
    let _ = app.emit("lan-event", serde_json::json!({ "type": kind, "name": name }));
}

fn send_line(stream: &Arc<Mutex<TcpStream>>, t: &str, my_name: &str, theme: &str) {
    let mut obj = serde_json::json!({ "t": t, "v": PROTO_V, "name": my_name });
    if t == "HELLO" {
        obj["theme"] = serde_json::json!(theme);
    }
    let s = obj.to_string();
    if s.len() + 1 > MAX_LINE { return; }
    if let Ok(mut g) = stream.lock() {
        let _ = writeln!(g, "{}", s);
    }
}

/// 处理一行:登记/心跳/转发给前端(配对与演出由前端裁决)
fn handle_line(app: &AppHandle, line: &str, stream: &Arc<Mutex<TcpStream>>, peer_of_conn: &mut Option<String>) {
    let line = line.trim_end();
    if line.len() > MAX_LINE { return; }
    let obj: serde_json::Value = match serde_json::from_str(line) { Ok(o) => o, Err(_) => return };
    if obj["v"].as_i64() != Some(PROTO_V) { return; }
    let t = match obj["t"].as_str() { Some(s) => s.to_string(), None => return };
    let name = obj["name"].as_str().unwrap_or("").to_string();

    let mut g = match STATE.lock() { Ok(g) => g, Err(_) => return };
    let Some(st) = g.as_mut() else { return };

    if t == "HELLO" {
        if name.is_empty() || name == st.my_name { return; }
        let now = std::time::Instant::now();
        let is_new = !st.peers.contains_key(&name);
        st.peers.entry(name.clone()).or_insert_with(|| (stream.clone(), now));
        *peer_of_conn = Some(name.clone());
        // 回敬 HELLO(入向连接对方不知道我是谁)
        send_line(stream, "HELLO", &st.my_name, &st.theme);
        if is_new {
            crate::kflog::kflog(&format!("lan: 邻居上线 {}", name));
            drop(g);
            emit_event(app, "peersChanged", &name);
        }
        return;
    }
    let Some(pname) = peer_of_conn.clone() else { return };
    if let Some(p) = st.peers.get_mut(&pname) { p.1 = std::time::Instant::now(); }
    match t.as_str() {
        "PING" => send_line(stream, "PONG", &st.my_name, ""),
        "PONG" => {}
        "PEEP" | "VISIT" | "FISH" | "BYE" => {
            let kind = t.to_lowercase();
            drop(g);
            emit_event(app, &kind, &pname);
        }
        _ => {}
    }
}

/// 连接读循环:按行喂 handle_line;连接断 → 邻居下线
fn reader_loop(app: AppHandle, stream: TcpStream, mark_name: Option<String>) {
    let stream = Arc::new(Mutex::new(stream));
    let mut peer: Option<String> = mark_name;
    // 名字大者主动连的场景,连接前已知对方名(先登记,HELLO 再刷新)
    if let Some(n) = &peer {
        if let Ok(mut g) = STATE.lock() {
            if let Some(st) = g.as_mut() {
                st.peers.entry(n.clone()).or_insert_with(|| (stream.clone(), std::time::Instant::now()));
            }
        }
    }
    let clone = stream.lock().map(|g| g.try_clone()).ok().map(|r| r.ok()).flatten();
    let Some(read_side) = clone else { return };
    let mut reader = BufReader::new(read_side);
    let mut line = String::new();
    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) | Err(_) => break,
            Ok(_) => {
                let s2 = stream.clone();
                handle_line(&app, &line.clone(), &s2, &mut peer);
            }
        }
    }
    // 断开:清邻居(仅当映射还是这条连接,防误删新连接)
    if let Some(n) = &peer {
        let mut g = match STATE.lock() { Ok(g) => g, Err(_) => return };
        if let Some(st) = g.as_mut() {
            let same = st.peers.get(n).map(|(s, _)| Arc::ptr_eq(s, &stream)).unwrap_or(false);
            if same { st.peers.remove(n); }
        }
        drop(g);
        emit_event(&app, "peersChanged", n);
    }
}

#[tauri::command]
pub fn lan_start(app: AppHandle, name: String, theme: String) -> Result<(), String> {
    {
        let mut g = STATE.lock().map_err(|e| e.to_string())?;
        if g.as_ref().map(|s| s.running).unwrap_or(false) { return Ok(()); }
        *g = Some(LanState { my_name: name.clone(), theme, peers: HashMap::new(), daemon: None, running: true });
    }
    crate::kflog::kflog(&format!("lan: 服务启动 {}", name));

    // 监听 TCP(端口随机),注册 mDNS 服务(服务名=昵称)
    let listener = TcpListener::bind("0.0.0.0:0").map_err(|e| e.to_string())?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    let daemon = ServiceDaemon::new().map_err(|e| e.to_string())?;
    let svc = ServiceInfo::new(SERVICE_TYPE, &name, &lan_hostname(),
                               std::net::IpAddr::from(Ipv4Addr::UNSPECIFIED), port, HashMap::<String, String>::new())
        .map_err(|e| e.to_string())?
        .enable_addr_auto();
    daemon.register(svc).map_err(|e| e.to_string())?;

    // 接入循环:每条入向连接一个读线程(HELLO 时登记)
    let app_accept = app.clone();
    std::thread::spawn(move || {
        for conn in listener.incoming() {
            let Ok(c) = conn else { continue };
            let _ = c.set_nodelay(true);
            let app2 = app_accept.clone();
            std::thread::spawn(move || reader_loop(app2, c, None));
        }
    });

    // 浏览:发现名字 > 自己的邻居 → 主动连(避免双连接;macOS 同款规则)
    let daemon2 = daemon.clone();
    let my_name2 = name.clone();
    let app3 = app.clone();
    std::thread::spawn(move || {
        let receiver = match daemon2.browse(SERVICE_TYPE) { Ok(r) => r, Err(_) => return };
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
                let Some(addr) = addrs.iter().next() else { continue };
                let Ok(mut c) = TcpStream::connect((*addr, info.get_port())) else { continue };
                let _ = c.set_nodelay(true);
                let app4 = app3.clone();
                crate::kflog::kflog(&format!("lan: 发现邻居 {},发起连接", short));
                std::thread::spawn(move || reader_loop(app4, c, Some(short)));
            }
        }
    });

    // 心跳:5s PING 全员;10s 未收包判离线
    let app5 = app.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_millis(HEARTBEAT_MS));
        let mut gone: Vec<String> = Vec::new();
        {
            let mut g = match STATE.lock() { Ok(g) => g, Err(_) => return };
            let Some(st) = g.as_mut() else { return };
            if !st.running { return; }
            for (n, (s, last)) in st.peers.iter_mut() {
                if last.elapsed().as_secs() > PEER_TIMEOUT_SECS { gone.push(n.clone()); continue; }
                send_line(s, "PING", &st.my_name, "");
            }
            for n in &gone { st.peers.remove(n); }
        }
        for n in gone {
            emit_event(&app5, "peersChanged", &n);
        }
    });

    if let Ok(mut g) = STATE.lock() {
        if let Some(st) = g.as_mut() { st.daemon = Some(daemon); }
    }
    Ok(())
}

#[tauri::command]
pub fn lan_stop() -> Result<(), String> {
    let mut g = STATE.lock().map_err(|e| e.to_string())?;
    if let Some(st) = g.as_mut() {
        st.running = false;
        st.peers.clear();
        if let Some(d) = st.daemon.take() { let _ = d.shutdown(); }
    }
    *g = None;
    crate::kflog::kflog("lan: 已关闭");
    Ok(())
}

/// 前端主动动作:PEEP 广播 / VISIT / FISH(在线邻居选第一个配对项由前端管,这里广播给全部)
#[tauri::command]
pub fn lan_send(kind: String) -> Result<bool, String> {
    let g = STATE.lock().map_err(|e| e.to_string())?;
    let Some(st) = g.as_ref() else { return Ok(false) };
    let t = match kind.as_str() {
        "peep" => "PEEP", "visit" => "VISIT", "fish" => "FISH",
        _ => return Ok(false),
    };
    let mut sent = false;
    for (_, (s, _)) in st.peers.iter() {
        send_line(s, t, &st.my_name, "");
        sent = true;
    }
    Ok(sent)
}

/// 在线邻居名单(托盘状态行用)
#[tauri::command]
pub fn lan_peers() -> Vec<String> {
    let g = match STATE.lock() { Ok(g) => g, Err(_) => return vec![] };
    let Some(st) = g.as_ref() else { return vec![] };
    let mut v: Vec<String> = st.peers.keys().cloned().collect();
    v.sort();
    v
}

fn lan_hostname() -> String {
    std::env::var("COMPUTERNAME").unwrap_or_else(|_| "kf-win".into())
}

