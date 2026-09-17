# KingfisherPet 全站 Code Review(第四轮)

- **基线**:main = fedbf1b(v1.7.17),距上轮评审(09-12, 0eed61a)64 个提交、+3728 行
- **范围**:macOS Swift 全部 25 文件(~7400 行)、Windows TS+HTML(~3800 行)、Rust 后端(~1900 行)
- **方法**:四路并行评审 + 人工逐条对源码核验(全部 🔴 与主要 🟡 均已亲验,标注见各条),双端测试基线全绿(Swift 147/147、Win 36+5)
- **结果**:🔴9 / 🟡25 / 🟢27。文末附两个线上实锤问题的根因分析(和风测试按钮无反应、LAN 互不可见)

---

## 一、🔴 严重(9 条,全部人工核验)

### R1. Win 设置窗开即 TDZ 崩溃——7be137d「修 TDZ」的修复自己引入的
`windows/settings.html:244` 同步调用 `applyLang()`,其首行(130 行)调 `zhUI()`;而 `const zhUI` 声明在 **246 行**(同一 module script,71 行起)。TDZ ReferenceError,整个脚本在 244 行中止:
- `paintWxStat`/`wx-state` 监听(254 行)、`settings-sync` 回填(256 行)永不注册 → 状态行停在 HTML 静态初值「状态:未开启」,滑杆/主题/语言显示假默认值,一动就提交错值;
- Key 测试按钮的 onclick(206 行)虽已挂上,但 211 行 `zhUI()` 处于永久 TDZ → **每次点击抛异常静默死**(线上实锤见附录 A);
- 115 行的 `lang` 监听已注册,每次切语言再抛一次。

git log -L 实锤:7be137d 把 `applyLang(); paintQW();` 插在 `const zhUI` 之前,同块注释还写着「初始化(必须在全部 const 声明之后)」。**v1.7.17 带发。**
**修复**:把 244-245 两行(或整个初始化段)移到 254 行 `listen("wx-state")` 之后;顺手把 `const zhUI` 上移到 `applyLang` 定义之前更稳。建议把设置窗脚本抽成 .ts 入口——`tsc --noEmit` 对 .html 内联脚本不设防(本轮 tsc 通过 0 错误即是证明)。

### R2. lan.rs HELLO 回敬重入死锁(STATE 锁)
`windows/src-tauri/src/lan.rs:59` `handle_line` 持有 `STATE.lock()` 期间,77 行回敬 HELLO → `send_line`(35 行)在 39 行**同线程再次 `STATE.lock()`**。std::sync::Mutex 不可重入 → 该 reader 线程永久阻塞且 STATE 被永久持有 → 心跳线程(201 行)、所有 reader、`lan_peers`/`lan_send`/`lan_stop`/`lan_config`(同步 IPC 命令)全部冻死。
**任何入向连接收到一条 HELLO 即触发**。mac 端 `LanBirds.swift:184` 在 `.ready` 时主动发 HELLO——Mac 连 Win 必中(Mac↔Win 组网至今未做,故未暴露)。
**修复**:`send_line` 不再自锁 STATE(`my_mid` 由调用方传参);或在调 `send_line` 前先 `drop(g)`。

### R3. lan_start 失败不回滚 → 永久假启动
`lan.rs:141-142` 先置 `running: true`,随后 bind/mDNS 注册失败(147/149/154 行)直接 `return Err`,STATE 残留 running=true → 之后每次 `lan_start` 命中 141 行防重入**返回 Ok(()) 假成功**。且两处调用方 `let _ =` 吞错(lib.rs:277/713),用户勾选开关看似成功、功能静默失效、零日志。
**修复**:bind/注册全部成功后再写 STATE(或失败回滚 `*g = None` + kflog);调用方不要丢弃 Err。

### R4. lan_stop 清理不完整:listener/accept 线程/peer 连接/读线程全部泄漏
`LanState`(19-27 行)不保存 listener;`lan_stop`(222-231 行)只 `peers.clear()`(drop 写端 Arc,reader 仍持读端阻塞在 `read_line`)+ shutdown daemon。accept 线程(158 行)永阻塞在 `incoming()`;对端心跳维持连接时 reader 线程永不退出。桌宠常驻 + 反复开关 LAN = 线程/socket 单调增长。
**修复**:LanState 增加 `listener: Option<TcpListener>`;stop 时对每个 peer `shutdown(Both)`、drop listener 让 accept 退出,顺带广播 BYE(协议已定义,90 行有处理,正常停服却从不发——对端要多挂 10s 才感知)。

### R5. 全部 TCP 无超时 + 持 STATE 锁写 socket → 坏邻居可全局冻结
`lan.rs:45-47` `writeln!` 无超时,且所有 `send_line` 调用点(心跳 206、BYE 66、PONG 88、lan_send 245)都在持有 STATE 锁的上下文。对端挂起/睡眠致 TCP 发送窗口满 → `writeln!` 无限期阻塞 → STATE 卡死(与 R2 同一冻结链)。`lan_send` 在 IPC 线程上执行,一个坏邻居即可冻 UI。
**修复**:每条连接 `set_write_timeout`;写失败即判 peer 下线;绝不持 STATE 锁做网络 IO(与 R2 同批重构)。

### R6. 主动连接方从不发 HELLO → Win↔Win(及修复组播后的 Win→Mac)永远配不上对
`reader_loop`(100-113 行)对主动连接(`mark_name=Some`)只登记自己的 peers 就进读循环,全程不发任何包。被动方(85 行)对未登记连接的 PING 静默丢弃 → 主动方 10s 超时踢除 → mDNS 再 resolve → 重连,死循环。全文件唯一发 HELLO 的路径是收到 HELLO 后的回敬(77 行,即 R2 死锁点)——**R2 与 R6 互为掩盖**。
**修复**:connect 成功后立即 `send_line(stream, "HELLO", …)` 再进读循环。

### R7. mac fallAway 可被点击/拖拽/锁屏打断:鸟可见存活但 onScreen=false
`Behavior.swift:1064-1087`:`onScreen = false` 在 1067 行先行落账,真正的 orderOut/suspend 在 gen 守卫的 done 闭包(1071-1085)里。~1.15s 动画窗内一次 `beginAction()`(点击 139 行/拖拽 152 行/锁屏)即把代际 bump 掉 → done 永不执行 → 鸟复活,但:
- DndMonitor(`DndMonitor.swift:57` 用 `isOnScreen`)永不进勿扰 → **鸟持续盖全屏视频**(红线);
- 菜单 7 个动作全哑(KingfisherPetApp.swift:701 等 7 处 `guard isOnScreen`);
- 唤醒不恢复 poop/branch(849 行);天气/成长插播全被 guard 挡掉;toggleVisibility 会瞬移右下角重孵化。
**修复**:`onScreen=false` 移入 done 闭包;或 `petViewWasClicked/petViewDidBeginDrag` 忽略 `"dead"` 态。

### R8. mac LanBirds 三张字典跨线程并发读写,无锁
`LanBirds.swift`:browser 回调线程(166-180 写 peers/connNames)、connection queue(198/217-231 写 lineBuf、drop)、主线程(handle 231-259 写 peers/lastRecv、heartbeat 282)同时碰 `peers/connNames/lineBuf`。NW 对象都 `start(queue: .global(qos:.utility))` 并发队列,字典并发读写 = UB,随机 EXC_BAD_ACCESS。另 186/252 行在 queue 线程读 `SpriteLibrary.shared.currentTheme` 同性质。
**修复**:所有 NW 回调第一步 `DispatchQueue.main.async` 再碰状态(与 handle 现做法对齐),或串行队列+锁。

### R9. mac heartbeat 遍历字典中调 drop(原地删除)
`LanBirds.swift:282-286` `for (n, p) in peers { ... drop(n) }`,而 `drop`(289 行)第一行 `peers.removeValue(forKey:)`——遍历中修改字典是 Swift 未定义行为,邻居超时掉线(网络抖动 10s)即触发,轻则漏断漏发、重则崩溃。
**修复**:先 `filter` 出超时名单,遍历后逐个 drop。

---

## 二、🟡 中等(25 条,按主题分组;标 ✅ 者已人工核验原文)

### 功能承诺/状态失真
| # | 位置 | 问题 |
|---|---|---|
| M1 ✅ | WeatherService.swift:38 / weathersvc.ts:46 | **「失败 5 分钟重试」双端均未实现**:86de4db(v1.7.13)在 mac 端只加了一行从未读写的 `retryScheduled` 死变量,Win 端 0 改动,至今固定 30 分钟周期(提交说明半件空头支票;「测试通过即重刷」半件在 Settings.swift 是真的) |
| M2 ✅ | settings.html:253 | 天气状态行初值读设置窗自己的隔离 localStorage,恒「未开启」(152 行注释自认隔离);修好 R1 后立即暴露 |
| M3 ✅ | settings.html:137 | 城市 placeholder 中文「留空 = IP 定位」vs 英文 "empty = Beijing",两语言矛盾且描述已砍掉的行为 |
| M4 ✅ | main.ts:67 + lansvc.ts:20 | `m.lan.enabled = m.lan.enabled` 自赋值:getter 读主窗隔离缓存(可陈旧"1")→ setter 把它倒灌回 Rust 权威 → 设置窗关 LAN 后主窗重启复活服务;`kf_lan_name` 全仓零写点,`lan.name` 每次当场随机代号(重启换名) |
| M5 | KingfisherPetApp.swift:103-113 | 首启自启先 `set(true)` 落盘再 `try?` 丢注册错误 → 失败时菜单显示「自启 ✓」实际未注册(与 toggleAutoLogin 881-896 的失败语义自相矛盾);且成功路径 register 两次 |
| M6 | weathersvc.ts + settings.html:206-230 | Win 端 Key 测试按钮成功后不触发主窗天气重刷(mac 端 v1.7.13 已做) |

### 稳定性/资源
| # | 位置 | 问题 |
|---|---|---|
| M7 ✅ | behavior.ts:997 + main.ts:250-261 | 破壳 `hold(1.4)` 的 resolve 被 gen 守卫吞:启动 1.4s 内进一次勿扰 → `main()` 永卡在 `await behavior.start()`,tick/watchdog/心跳全不跑(启动时正看全屏视频=高概率) |
| M8 ✅ | KFDialog.swift:210-216 + UpdateService.swift:129-149 | `finish()` 不清 `onAction`,handler 强捕获 `dlg` → dlg→onAction→dlg 自环,每次「检查更新」泄漏一份 NSWindow 对象图 |
| M9 ✅ | Effects.swift:36 vs 207/405/441 | `Effect.init` 已 `active.append`,rain/notes/snow 外层再 append 一次 → `active.count` 虚高一倍,污染 WatchdogService.swift:65 泄漏监控与测试断言 |
| M10 ✅ | ProgressWin.swift:19-20 | 漏 `bar.isIndeterminate = false`(KFDialog.swift:232 同坑已修且留注释),dev 进度样例条不走 |
| M11 | SpriteLibrary.swift:73-96 | 主题加载失败仅 print(GUI 不可见)、`currentTheme` 先行变更致半加载(帧表残缺→动画冻结)、`reload` 的 `guard theme != currentTheme` 挡住重试 |
| M12 | DndMonitor.swift:59-63/116-118 | 后台串行队列访问 `NSScreen.frame`/`NSScreen.main`/`NSWorkspace.frontmostApplication`(AppKit 主线程类) |
| M13 | lib.rs:553 | `&url[..url.len().min(60)]` 字节切片,UTF-8 多字节边界即 panic;Cargo.toml `panic="abort"` → 全进程退 |
| M14 | lib.rs:625 | 唯一一处 `duration_since().unwrap()`(同文件其余全 `.unwrap_or(0)`),系统时钟早于 1970 即崩 |
| M15 | windows.rs:424-449 | 全屏判定:任务栏**自动隐藏**时最大化窗口矩形=整屏 → 误判全屏进勿扰,鸟「随机消失」(需排除 WS_MAXIMIZE 或比对 rcWork) |
| M16 | lan.rs:117/53 | `read_line` 无行长上限,MAX_LINE 检查是整行读入内存后的马后炮;监听 0.0.0.0,同网段任意主机可直连喂无换行垃圾流撑内存 |
| M17 | lan.rs:186 | `TcpStream::connect` 无超时(Windows SYN ~21s),browse 线程串行 → 一个不可达地址拖住所有邻居发现 |
| M18 | lan.rs:139-154/215-217 | 置位 STATE 后放锁,bind/注册期间 lan_stop 可插入 → daemon 句柄丢失成幽灵服务(与 R3 同批修) |
| M19 | kflog.rs:43/61 | 时区偏移 OnceLock 只算一次,DST 切换后日志时间错 1h;时间戳无日期段 |
| M20 | UpdateService.swift:129-146 | 更新进度态无取消:点关闭 → 下载照跑 → 完成即 `NSApp.terminate` 强制重启 |

### 双口径/残留
| # | 位置 | 问题 |
|---|---|---|
| M21 ✅ | main.ts:104-111 | `weather_on/weather_key/weather_host` 各重复一遍,4 行永不可达死分支(修复残留) |
| M22 ✅ | WeatherService.swift:235 vs 212 | locate 判新旧 API 用未清洗 host(qwURL 却先 sanitizedHost),尾带空格即两路径分裂;geo 与天气对 key 清洗口径也不一(filter 全空白 vs 仅首尾 trim) |
| M23 ✅ | windows/package.json `test` 脚本 | 漏挂 `tests/lan.test.mjs`(文件在、单跑 5/5 绿,但 npm test/CI 不跑它) |
| M24 | crack.html:21/41、poop.html:29 | `const DPR` 启动快照 vs resize 动态 devicePixelRatio 双口径,切显示缩放后裂纹/特效错位 |
| M25 | WatchdogService.swift:31 | `watchdogBusy` 在后台线程 catch 里直接写(38/56 行都特意回主线程),数据竞争+线程模型不统一 |

## 三、🟢 轻微(27 条,摘要)

死代码/残留:lib.rs:789-793 diag 菜单分支、lib.rs:715 `let _ = app.handle().clone()`、lib.rs:65 `let _ = ()`、settings.html:175-178 与 240-242 三对 onchange 双赋值;WeatherService.swift:38 死变量(见 M1);BranchController.swift:121 魔数 27 vs feetOffsetConst=26。
防御性:lib.rs ~15 处 `lock().unwrap()` 与 kflog 的毒化恢复风格不一;lib.rs:731 `default_window_icon().unwrap()`;KFDialog.swift:8 头注释称 Esc 关窗但无实现;UpdateService.swift:263 shell 单引号拼接未转义;WeatherService/UpdateService 常驻 timer 用 default mode(其余服务 .common);windows.rs:465 COM 每 2s init/uninit 往返;lan.rs stop 后 5s 内重启双心跳线程;shadow.ts:38 每次 scaleFactor() IPC(有成熟缓存模式未复用);main.ts:227 下载无 contentLength 时进度恒 0%;weathersvc.ts:172 locate 未走 qwHost() 净化;update.html:29 `try{void listen}catch` 捕不到 promise rejection,变形失败弹窗永卡「正在检查…」。
加固建议:tauri.conf.json CSP 补 `base-uri 'none'; form-action 'none'`;lan_config/lan_start 参数零校验;NSIS 无 Authenticode 配置(SmartScreen 拦截,分发体验)。

## 四、值得肯定

open_url 的 host 白名单提取(挡 `github.com@evil.com` 类)、updater minisign+逐域 connect-src+最小 capabilities、XSS 面全仓干净(唯一 innerHTML 是清空赋值)、设置键名 11 个双端零漂移、跨屏坐标数学核过无误、和风 icon/code 兼容解析正确、Win32 unsafe 指针/句柄处理整体扎实。

---

## 附录 A:线上实锤①「和风测试按钮没反应、状态恒未开启」——根因即 R1

现象(N5105,11588 用户,v1.7.17):点「测试」无反应,状态行恒「未开启」。
证据链:①HTML 静态初值即「状态:未开启」(settings.html:54),`paintWxStat` 初始化(253 行)与 `wx-state` 监听(254 行)都在 TDZ 崩溃点(244)之后,永不执行;②测试按钮 onclick 挂在 206 行(崩溃前,按钮有反应会进 handler),但 handler 211 行 `zhUI()` 永久 TDZ → async 函数内 ReferenceError → 静默 unhandled rejection,表现为「点了没反应」;③主窗天气本身正常(N5105 kf.log 22:32 `weather: ok QW#501`),证明只在设置窗。
**修复 R1 即愈。** M2/M3 顺手同批。

## 附录 B:线上实锤②「Mac 与 Win 互不开现在 LAN」——双层根因

**第一层(机器级,主因):N5105 组播源地址选错网卡,mDNS 被 RFC 6762 判火星包丢弃。**
证据链:
1. 代号:Mac=`翠鸟-2AE1`(/tmp/kf_debug.log),N5105=`翠鸟-21E4`(kf.log 22:23:55「服务启动 翠鸟-21E4」)。规则=小名连大名 → 应由 Win 主动连;Win 日志零条「发现邻居」= Win 的 mdns-sd 浏览从未解析到 Mac。
2. Mac 侧 `dns-sd -B _kingfisherpet._tcp` 只看到自己(翠鸟-2AE1×3 接口),完全看不见 Win 实例;Mac 日志零「发现邻居」(本例中这是正确行为,21E4<2AE1)。
3. 防火墙清白:kingfisherpet.exe 入站 Allow×2(Private+Public)。
4. 双向组播探针(临时 UDP 5354/224.0.0.251):**裸组播双向都通**——Win 收到 Mac 的包(源 192.168.31.218);Mac 收到 Win 的包,**但源 IP=172.18.160.1 = WSL「Hyper-V firewall」虚拟网卡**,不是 LAN(vEthernet (LAN)=192.168.31.86)。
5. 该机网卡:LAN(27/.86)、内部交换机(39/.35,DHCP!)、Default Switch(172.29.64.1)、ZeroTier(192.168.192.107)、WSL(50/172.18.160.1)、WIFI热点(16/.74,也在 LAN 网段)——多卡混战,组播源/组加入接口选择不稳定(三次探针 Win 收包成功率 1/3,亦证明 wildcard 套接字在该机不可靠)。
6. mDNS 接收端(含 macOS mDNSResponder)按 RFC 6762 §11 丢弃源地址不属本链路子网的组播包 → **Win 发的一切 mDNS(通告/查询/应答)在 Mac 全被静默丢弃;Mac 的查询 Win 收到了、mdns-sd 的应答源仍是 172.18.160.1,Mac 照丢**。双向全灭。「网络发现」设置与此无关。
**机器级处置(二选一或叠加)**:①给 WSL/内部/热点网卡拔高 InterfaceMetric(如 4000/3000),让 LAN 成为最低 metric 的已连接网卡(WSL 网卡重启 WSL 后 metric 会回弹,需留意);②应用级才是根治(见下)。
**第二层(应用级):lan.rs 的 R2/R6。** 组播修通后,本例由 Win 主动连 Mac(21E4<2AE1),而 Win 主动连接不发 HELLO(R6)→ Mac 永不登记邻居;若反过来 Mac 主动连 Win,则 HELLO 触发 R2 死锁冻结 Win。**即组播修复后仍需修 lan.rs 才能配对。**
**应用级修复方向**:mdns-sd 0.11.5 已有 `ServiceDaemon::enable_interface(IfKind)`(service_daemon.rs:387)——lan.rs 应枚举网卡,仅在「已连接、私网地址、非虚拟(vEthernet/WSL/ZeroTier/热点)」的接口上启用 mDNS;至少提供设置项让用户指定网卡。同时 R2-R6 同批重构(STATE 锁内不做网络 IO、HELLO 参数化、bind 成功才置 running、stop 完整清理+BYE、写超时)。

### 运维备注(本轮诊断期间的操作记录)
诊断中曾在 N5105 做过一次临时路由试验,清理时 `route delete 224.0.0.0` 误删了系统自带的 5 条 224/4 在链路路由(该命令不做掩码过滤);**已按原快照逐条恢复**(接口/网关一致,metric 偏移 +15,相对顺序不变,功能等价;重启后系统会自动重生成原始值)。教训已记录:Windows 上清理组播路由必须带 mask 且按 if 逐条删。

---

## 五、建议修复批次

1. **B1 立即(小改,止血线上)**:R1(两行挪位)+ M23(npm test 补挂 lan.test.mjs)+ M21(删 4 行死分支)+ M3(placeholder 文案)。
2. **B2 天气批**:M1 双端补「失败 5 分钟重试」真实现(这次要带测试,杜绝再交白卷)+ M2/M6/M22。
3. **B3 LAN 批(动刀最大,单独一轮)**:R2-R6 + M16/M17/M18 + enable_interface 网卡选择;mac 端 R8/R9。**做完这批才能开 Mac↔N5105 组网验收**(先做机器级 metric 处置,再验 app 级)。
4. **B4 行为/杂项批**:R7 + M7-M15 + M19/M20 + M4/M5。

—— 评审:ZCode(2026-09-17)。🔴/✅ 条目均经第二遍人工对源码核验;测试基线:Swift 147/147,Win node --test 36+5 全绿。
