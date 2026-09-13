# 翡 · KingfisherPet 全量 Code Review（2026-09-12）

> **评审对象**：main @ `d8660b3`（v1.6.0 代码态，分发批已入、tag 未打）。
> **方法**：五路并行深审（Mac 行为渲染层 / Mac 应用服务层 / Win 前端 TS / Win Rust+Tauri / 构建链+CI+素材管线），逐行通读非抽样；主审另亲读 `UpdateService.swift` 全文并对关键发现逐条抽查复核（源码 grep + 本地验证）。
> **与旧报告关系**：`CODE_REVIEW-2026-09-07.md`（基线 7e2337b）与 `CODE_REVIEW-2026-09.md`（v1.4.59 后）之后又有三波提交：v1.5.0 天气批、v1.5.x 成长批、v1.6.0 分发批。本次对旧问题做回归对照（见 §7），对三波新代码做首次深审。
> 本文档自包含：每条带 `文件:行号`，可凭仓库直接复核。分级：🔴 必修（生产级） / 🟡 建议 / 🟢 可选。
> **用途**：交外部 Agent / 人工评审复核。文末附「给评审者的抽查指引」。

---

## 0. 覆盖度声明

| 域 | 范围 | 状态 |
|---|---|---|
| Mac 行为/渲染 | KingfisherPetCore 13 文件（Behavior 1217 行、PetView、Effects、SpriteLibrary、Poop/Crack/Branch/ShadowController、Growth、DayRhythm、ThemeColors、PetWindowController、WindowTracker），共 3204 行 | ✅ 逐行 |
| Mac 应用/服务 | KingfisherPetApp 664、Settings 517、WeatherService 444、UpdateService 220、DndMonitor 167、WatchdogService 136、VisitorService 195、Language 206、main 8、Tests 280 | ✅ 逐行 |
| Win 前端 | windows/src 15 个 .ts（behavior 1128 行、main 439、weathersvc 223 等）+ 3 个 .mjs 共享纯函数 + 6 个 HTML + tests/ 4 个单测 | ✅ 逐行 |
| Win Rust | src-tauri 全部 .rs（lib 688、windows 477、system 197、kflog 77、main 6）+ tauri.conf.json + capabilities + Cargo.toml/build.rs；另核对本机 registry 中 tauri-plugin-updater 2.11.0 真实源码 | ✅ 逐行 |
| 构建链/CI/素材 | build.sh、release.yml 200 行、lint.yml、run_tests.sh、gen_sprites.py 1305 行（**上次报告唯一盲区，本次全量逐行**）、.gitignore、版本号全仓对照 | ✅ 逐行 |
| 实证项 | git 全历史无私钥/p12 入库（`git log --all -S "PRIVATE KEY"` 零命中）；`tools/certs/` 仅含公开 G2 中介证书（openssl 验证）；Resources 与 windows/public 全量 cmp；URLComponents 畸形输入行为本地实测；Open-Meteo 默认风速单位官方文档确认；`ps %cpu` 语义本地实测 | ✅ |
| 未审 | Resources 产物本身、dist/、.zcode/ | 产物，不属源码 |

---

## 1. 总评

CLAUDE.md 里沉淀的历史顽疾（代际取消、粒子 opacity=0、CGWindowList 降频、累积上限、睡眠 suspend 配对、树枝三坑）**全部守住了**，v1.5.x 四新行为（炸毛/寒颤/觅食/访客）规规矩矩走 hold/代际链。Windows 侧 capabilities 与前端调用面双向零偏差（上次 allow-set-size 类静默失效不存在），updater 走官方插件 + minisign 验签架构正确。

窟窿集中在**三波新代码的接缝**上：

1. **v1.6.0 更新链路（Mac 侧）是最大的洞**：自研「下载→验签→替换→重启」的验签环节形同虚设（🔴A1），且主交互弹窗用原生 NSAlert 违反项目自绘红线（🔴A6）。
2. **勿扰（DND）状态机的两套可见性语义（onScreen/dndActive）接缝**：泄漏链（隐身鸟行为循环复活、特效盖全屏视频，🔴A2）与死锁（隐藏态下 dndActive 永不清除，🔴A3）——后者是旧 R4 的**变体复发**，被 Mac 两路审查独立发现，交叉验证。
3. **Windows 侧状态机纪律在新增菜单动作上掉队**：callOver 缺 beginAction（🔴W1）、三个飞行动作缺 leavePerchWin（🔴W2）、更新弹窗死局（🔴W3）。
4. **CI 供应链**：公证凭据以 job 级 env 暴露给未 pin SHA 的第三方 action（🔴B1）。

---

## 2. 🔴 必修

### Mac 侧

**A1. 更新包「验签」形同虚设：未签名包直接放行，全链无 quarantine，恶意二进制可被静默安装执行**
- 位置：`Sources/KingfisherPetCore/UpdateService.swift:153-163`（主审亲读确认）
- 证据：
  ```swift
  if out.contains("TeamIdentifier=") && !out.contains("TeamIdentifier=5CTLSL2C9X") {
      DispatchQueue.main.async { done(false, "签名校验不符") }; return
  }
  ```
  `codesign -dv` 只 dump 元信息**不做完整性校验**；判定逻辑只拦「有 TeamIdentifier 但不匹配」——**完全未签名的包**（`-dv` 输出 `code object is not signed at all`，不含 `TeamIdentifier=`）第一个条件为 false，直接放行。即使 Team 匹配，被篡改的已签名包 `-dv` 仍打印原 TeamIdentifier（需 `--verify` 才能发现）。下载链 `data.write → ditto → moveItem → open -n`（128-187 行）全程不打 quarantine 属性，Gatekeeper 不参与。
- 影响：传输层有 HTTPS，但 GitHub 账号被盗/Release 附件被替换时无第二道防线——用户点「下载并更新」即以本人身份执行任意未签名二进制。
- 置信度：已复核源码（codesign 行为为公认语义，未实际构造恶意包）。
- 修法：改 `codesign --verify --strict` 且要求 Team 精确匹配（未签名 = 失败）；发布时附 SHA256（GitHub API 有 digest 字段）做完整性校验；可选 `spctl -a -t exec`。

**A2. DND 泄漏链：`enterDnd` 不停 `perchChecker` 且 `think`/`startFly` 等无 `dndActive` 守卫，隐身鸟的行为循环可被自动复活，特效窗口盖在全屏视频上**
- 位置：`Behavior.swift:998-1017`（enterDnd）、`841-887`（checkPerch）、`466`（think）、`596`（startFly）；`DndMonitor.swift:61-67`
- 证据：`enterDnd` 停了 view/branch/poop 的 timer 但没停 `perchChecker`；`checkPerch` 的 `occlStreak >= 2` 分支直接 `leavePerch(); startFly(minDist: 300)`（869-871 行）无任何 dnd/onScreen 守卫；`think()` 开头只有 `guard !busy, !perchWinMoving`。
- 推演链：鸟栖窗时前台 App 进全屏 → `enterDnd`（鸟 orderOut）→ 全屏窗口盖住栖点 → occlStreak 达标 → `startFly` 在**隐身鸟**上执行（window 仅 orderOut 仍非 nil，60fps 动画照跑）→ `finish()` → `scheduleThink()` → **think 循环在 DND 中复活**。此后随机到 sing/sun/fish/poop 时，`Effects.notes/sun/splash` 以 `.statusBar` 层 + `canJoinAllSpaces` + `orderFrontRegardless` 新建窗口——**直接盖在全屏视频上**；且 poopCtl 已 suspend，新掉的屎冻结在视频上不动。即使不触发 startFly，`perchChecker` 也以 20fps 空转 + 每 10 帧一次全窗口枚举贯穿整场电影。
- 影响：全屏看片/游戏期间特效窗盖视频（DND 的存在意义被击穿）+ 隐身鸟整套行为循环空转烧 CPU（正是 CLAUDE.md 红线场景）。
- 置信度：已复核源码（代码路径逐环确认）；特效实际可见性需实测复核一次。
- 修法：`enterDnd()` 补 `stopPerchCheck()`；`think()` 开头加 `guard !dndActive else { return }`（或各 start* 统一加守卫）。

**A3. DND 死锁：勿扰中手动隐藏鸟后 `dndActive` 永不清除，`hatchIn` 永远拒绝复活，鸟永久消失**
- 位置：`DndMonitor.swift:64-67` + `Behavior.swift:975,997`
- 证据：
  ```swift
  } else if behavior.dndActive == true && self.fsOffStreak >= 2 {
      if active { behavior.exitDnd() }   // 鸟隐藏时只清标志,不强制显示(下次 hatchIn 自然复活)
  }
  ```
  注释声称「鸟隐藏时只清标志」，但 `!active` 分支**什么都没做**（`dndActive` 是 `private(set)`，全仓只在 `exitDnd` 一处赋 false）。死锁链：DND 激活 → 菜单「显示/隐藏」`fallAway()`（`onScreen=false`，不清 dnd 标志）→ 全屏退出（`fsOffStreak≥2` 命中但 `active=false` 跳过 exitDnd）→ 此后 `setVisible(true)→hatchIn()` 永远被 `guard !dndActive else { return }`（Behavior.swift:975）挡回 → **只能重启**。
- 备注：这是旧报告 R4 的变体——streak 累计问题已修（DndMonitor.swift:36-39），但「清标志」的注释意图从未落到代码。**Mac 两路审查独立发现同一条，交叉验证。**
- 置信度：已复核源码（全仓 `dndActive` 赋值点逐一核对）。
- 修法：Behavior 增加 `clearDndFlag()`（只置 `dndActive=false` 不复活窗口），DndMonitor 在 `!active` 时调用；或 `hatchIn` 放行条件改为「全屏已退出」。

**A4. 用户输入的和风 Host 可使主线程强制解包崩溃（整 app 退出）**
- 位置：`WeatherService.swift:174-179`（入口 `Settings.swift:341-349`）
- 证据：`var comp = URLComponents(string: "https://\(host)\(path)")!`——host 来自用户设置文本框。本地实测：host 含空格/tab（粘贴时带入，或粘贴完整 `https://devapi.qweather.com` 拼成双协议串）时 `URLComponents(string:)` 返回 nil → `!` 崩溃。触发链：设置窗 Host 框失焦提交 → `weather.settingsChanged()` 立即 `start()→refresh()` → 崩。
- 影响：违反「外部数据防畸形值」红线（与版本比较 bug 同型）。
- 置信度：已实测 URLComponents 行为 + 调用链复核。
- 修法：`guard let comp = URLComponents(...)` 失败走 `fail("host 无效")`；对 host 做字符白名单/剥协议前缀。

**A5. Open-Meteo 风速单位错乱：km/h 当 m/s 用，wind 档触发阈值低 3.6 倍**
- 位置：`WeatherService.swift:106`（请求未带 `windspeed_unit=ms`）+ `263`（`windSpeed > 10.8`）
- 证据：官方文档确认 `wind_speed_10m` 默认单位 **kmh**；代码阈值 10.8 的语义是 m/s（6 级风，注释自证）。11 km/h ≈ 3 m/s（2 级轻风）即判 wind 档 → `factors(.wind): fly×0.3`，微风天鸟几乎不飞。行 121 raw 诊断串自标 "m/s" 误导排障。**单测（Tests/main.swift:141-145）全按 m/s 口径构造——测试绿但与线上单位脱节（假绿）。**
- 置信度：已复核源码 + 官方文档确认。
- 修法：请求加 `URLQueryItem(name: "windspeed_unit", value: "ms")` 或阈值改 38.9 km/h；Windows 侧 weather 逻辑同步核对。

**A6. 产品红线违反：更新/权限引导/关于弹窗均为原生阻塞式 NSAlert**
- 位置：`UpdateService.swift:75-114`（v1.6.0 新更新弹窗，主交互面）、`KingfisherPetApp.swift:646-658`、`DndMonitor.swift:152-165`
- 证据：三处均 `NSAlert()` + `runModal()`（主审 grep 复核）。项目红线明文「弹窗必须自绘（不允许原生阻塞式 alert）」；DND 引导弹窗还在 3s 巡检回调里 runModal（主线程模态阻塞）。
- 置信度：已复核源码。
- 修法：换项目内已有的自绘窗基建（Settings 窗同款 NSWindow+控件）。

### Windows 侧

**W1. `callOver` 缺 `beginAction()`，旧动作链不取消**
- 位置：`windows/src/behavior.ts:890-895`
- 证据：`export async function callOver() { if (dndActive) return; if (!onScreen) return; growth.add(2); leavePerchWin(); enter("fly"); ... }`——CLAUDE.md 明文「任何新动作、点击、拖拽、callOver() 都先 beginAction()」，所有兄弟菜单动作（doSing/doFish/doPeck/feedFish）都走了，唯独 callOver 漏。
- 影响：召唤时若鸟正在走/飞，两个 RAF 循环同帧双写 setOrigin（抖动/撕裂）；若正处 startFish 嵌套链，旧的 hover/dive、dropPoopAt、schedulePoopAfter 会在召唤飞行途中照常插播。
- 置信度：已复核源码。
- 修法：`leavePerchWin()` 前加 `beginAction()`。

**W2. 三个飞行类动作缺 `leavePerchWin()`，飞行期间旧栖窗跟随定时器仍活跃**
- 位置：`behavior.ts:249`（weatherRetreat）、`304`（affectionVisit）、`640`（startPerchWindow）
- 证据：beginAction 故意不停栖窗跟随（静态动作要继续踩窗），移动类动作须自己调 leavePerchWin——startWalk/startFly/startDart/startFish/startForage/dragBegin/fallAway 都调了，这三个没调。
- 影响：栖窗时触发这三者，飞行 1.1s 内旧 perchTimer(20fps) 继续跑：①遮挡检测在半空误判 → perchFlee 把进行中的落窗/躲雨/来访飞行**中途腰斩**（躲雨彩蛋失效）；②用户拖动栖窗时双写者打架。
- 置信度：已复核源码（触发概率取决于时序，静态推演）。
- 修法：三处 beginAction 后补 `leavePerchWin()`。

**W3. 「立即更新」后 UI 死局：按钮已清空，无包/失败路径不再驱动弹窗**
- 位置：`windows/src/main.ts:178-196` + `windows/update.html:66-75`
- 证据：update.html 点「立即更新」后清掉全部按钮、只留「正在更新…」+ 0% 进度条。此后两条路都不再通知弹窗：①do-update 复查 `!up?.available`（latest.json 与 GitHub tag 短暂不一致、网络抖动）→ 静默 return，弹窗永远停在 0%；②downloadAndInstall 抛错 → catch 只开浏览器回退，弹窗同样冻结。用户唯一出路是标题栏 X——**v1.6.0 新流程的第一屏即坏态**。
- 置信度：已复核源码。
- 修法：do-update 全路径 emit `update-done`/`update-fail` 事件，update.html 收到后恢复按钮或自关。

### 构建/CI

**B1. 公证凭据以 job 级 env 暴露给未 pin SHA 的第三方 action**
- 位置：`.github/workflows/release.yml:21-28`（job env）+ `:134-140`（softprops 步骤）
- 证据：job 级 `env:` 注入该 job 每一个 step（包括 `uses:` 的 action 进程）：`APPLE_PASSWORD`（notarization 专用密码）、`APPLE_DEV_ID_P12_B64` 等对 `softprops/action-gh-release@v2` 全量可见，而该 action 以**可变的 v2 tag** 引用（tag 可被移动）。对照：`build` job 里 `TAURI_SIGNING_PRIVATE_KEY` 做对了（step 级 env，`release.yml:187-191`）。
- 影响：供应链单点失守 = 公证凭据 + Developer ID 私钥泄露，可签发通过 Gatekeeper 的恶意软件。
- 置信度：高（GHA job-env 语义是文档化行为）。
- 修法：①secrets 下沉到「组装 .app」单个 step 的 `env:`；②`softprops/action-gh-release`、`tauri-apps/tauri-action`、`dtolnay/rust-toolchain` pin 到 commit SHA。

---

## 3. 🟡 建议

### Mac

| # | 问题 | 位置 | 说明 |
|---|---|---|---|
| A7 | `resumeAfterWake` 不查 `dndActive` | KingfisherPetApp.swift:594-598 | DND 中睡眠→唤醒，三套常驻 timer 在 orderOut 窗口上恢复空转；与 A2 同根（onScreen/dndActive 两套语义）。修：resume 条件加 `&& dndActive == false` |
| A8 | VisitorService.timer 不随睡眠/锁屏 suspend | VisitorService.swift:175-184 | 睡眠/锁屏 suspend 清单漏访客演出 timer；锁屏瞬间恰有演出则黑屏空转到播完（自累计 dt，无堆积，危害有限）。修：suspend 清单加 `VisitorService.shared.interrupt()` |
| A9 | `Growth.feedAllowed` 时钟回拨反向 | Growth.swift:100-107 | 负 interval 被判「冷却中」，回拨多久锁多久。「防反向」红线漏网点。修：`guard now >= last`；补 kf-tests 用例 |
| A10 | CrackController 多屏错位 | CrackController.swift:51-56,71-93 | overlay 只按建层时鸟所在屏布局，鸟换屏后裂纹画在 overlay 外不可见。修：peck 前检测换屏则 sizeToScreen（迁移已有裂纹坐标） |
| A11 | 多屎遮挡查询放大 | PoopController.swift:134,194-208 | 8 屎满编时各自独立做全窗口枚举 ≈24 次/秒；可共享一次枚举快照砍 8 倍 |
| A12 | 隐藏/勿扰期间 fading 屎冻结 | PoopController.swift:30 | suspend 停 update → 半透明屎常驻屏幕直到 resume。修：suspend 时快进清场，或 sitRemain 改绝对时间戳 |
| A13 | 更新失败零用户反馈 + 无并发防护 | UpdateService.swift:100-102,121-189 | `done(false)` 只 kfLog，注释说「回退浏览器」实际无动作；无 in-flight 防护可并发 moveItem 竞态。触「菜单状态必须可见」红线 |
| A14 | 下载无大小上限、整包进内存、tmp 不清理 | UpdateService.swift:128-144,193-209 | 仅 `>1MB` 下限无上限；zip 全量读进 Data；成功/失败均不清理临时目录 |
| A15 | 替换回滚吞错 | UpdateService.swift:171-177 | 回滚 `try? moveItem` 吞错，回滚再失败时 app 只剩 Trash 一份且无指引 |
| A16 | relaunch 先启后杀，短时双实例 | UpdateService.swift:181-187 | 两只鸟/两个菜单图标短时并存（WatchdogService.swift:104-111 同款） |
| A17 | tag 拼进 URL 未防畸形 | UpdateService.swift:124 | `URL(string: "…/download/\(tag)/…")!`，tag 来自 GitHub API；畸形即崩。红线同型（A4 同病） |
| A18 | kfLog 全局可变状态无锁 | KingfisherPetApp.swift:9-43 | 裸全局 var 被 URLSession 后台线程/global queue/主线程并发写，数据竞争 UB |
| A19 | 设置相同值提交也重启天气网络请求 | Settings.swift:76-91 + WeatherService.swift:40-48 | 失焦即写不比旧值 → 点任意其他控件都触发一轮 2-3 个请求，与「约 30 分钟一次」文案不符。触「厌恶无谓请求」红线 |
| A20 | 「发现新版本」菜单标注在语言切换后丢失 | KingfisherPetApp.swift:427-434 | 重建菜单后回默认标题，要等下个 24h 周期 |
| A21 | 单测缺口恰在本次崩溃/死锁点 | Tests/main.swift | host 校验（A4）、DND 状态转移（A3）、更新 URL 构造（A17）都内联在回调里不可测；抽纯函数补用例 |

### Windows 前端

| # | 问题 | 位置 | 说明 |
|---|---|---|---|
| W4 | doCheckUpdate 无超时 + 静默失败零日志 | main.ts:146,165 | 无 AbortSignal（weathersvc.jget 有 15s，此处没有）；自动检查 catch 静默分支连 log 都没有 |
| W5 | openUpdateDialog 关旧建新竞态 | main.ts:130-139 | 150ms 定值重建，快速连点第二次可能无声失败；改模块级串行锁 |
| W6 | 栖窗跟随 interval 无重入护栏 | behavior.ts:143-177 | IPC 慢于 50ms 时相邻两跳重叠执行 → 跟随漂移/perchFlee 双触发；hittest.ts 有 polling 旗标先例 |
| W7 | 逻辑常量漏乘 _scale 两处 | behavior.ts:669,701 | dart 的 20、fish 返航的 30/60 裸物理像素；701 还缺窄工作区钳制（span 负值时出界） |
| W8 | session-change → reload 丢 dnd 状态，看门狗把鸟强显在全屏应用上 | main.ts:201,396-421 | Rust dnd 事件仅边沿触发，reload 后模块态复位而窗口实际隐藏 → 看门狗「卡隐身自愈」强显。修：加 `get_dnd_state` 电平查询 |
| W9 | 预警文案疑似「色色」叠字 | weathersvc.ts:214 | 和风 level 字段通常已含「色」→「黄色色预警」；需实测确认字段形态 |
| W10 | 更新判定与安装内容版本源混用 | main.ts:152-164 + 178-196 | 文案版本来自 GitHub tag，实际安装来自 updater latest.json，两者不同步时说的和装的不一致 |

### Windows Rust / Tauri

| # | 问题 | 位置 | 说明 |
|---|---|---|---|
| R1 | `open_url` 无协议/URL 白名单 | lib.rs:449-461 | webview 字符串直通 ShellExecuteW；当前调用点全是固定值无现实注入链，但这是唯一 webview→Shell 桥，建议白名单 `https://github.com/hizml/` 与 `ms-settings:taskbar` |
| R2 | `front_perch` 兜底与 `window_at_point` 漏 `IsWindowVisible` 过滤 | windows.rs:70-83,374-389 | 隐藏普通窗口会被选为栖窗/遮挡物（幽灵栖窗变体）；对照 surfaces_below 有该过滤。修：各加一行 |
| R3 | kflog 多线程写文件无锁，轮转非原子 | kflog.rs:37-65 | IPC/power/watchdog/菜单线程并发调用；行交错损坏 + 轮转竞态。修：Mutex 串行化 |
| R4 | 自定义天气 Host 生产被 CSP 拦、开发不拦 | tauri.conf.json:31 + settings.ts:21 | CSP `connect-src` 只放行 `*.qweather.com`，用户改 host 即静默失效（dev 测不出——历史同款） |
| R5 | capabilities 过度授权/重复 4 项 | capabilities/default.json:14,15,20,22 | `allow-start-dragging`（已弃用）、`allow-show`（无调用）未用；`core:event:default`、`allow-current-monitor` 已含于 core:default。删之 |
| R6 | relaunch 成功日志是死路径 | main.ts:190-195 | 插件 downloadAndInstall 在 Windows 启动安装器后自行 exit(0)，不会 resolve；日志与浏览器回退误导用户重装 |

### 构建链 / CI / 素材 / 文档

| # | 问题 | 位置 | 说明 |
|---|---|---|---|
| B2 | 公证失败仍产出正式 release 产物 | release.yml:105-112 | notarytool 失败仅 warning，未公证 zip 照常上传同名产物；配合 A1（自研更新器不经 Gatekeeper）扩散无感知。修：exit 1 或改名标注 |
| B3 | sprites.json 缺失只发注记不阻断 | release.yml:44-45 | `\|\| echo "::error::"` 后无 exit 1，主题丢 manifest 照常发版（用户切主题鸟静止） |
| B4 | gen_sprites 镜像顺序倒置 | gen_sprites.py:1169 vs 1302-1305 | mirror 在 main() 尾部，但 colors.json/peep wav 在其后才写——改色/叫声后单跑一遍，windows/public 拿到**上一版**（正是该函数要杀的漂移，变成滞后一代） |
| B5 | 镜像「只增改不删」→ 12 个孤儿帧已入库 | gen_sprites.py:1136 | `fly_0.png`/`fly_fish_0.png`×6 主题，Phase 1 遗留、代码零引用、随每个 Windows 安装包分发。修：镜像加集合差清理 |
| B6 | run_tests.sh 丢 build.sh 退出码 | run_tests.sh:90 | 打包失败时拿旧 .app 继续测且可能全绿——与它自己修过的「旧二进制全绿」坑同构 |
| B7 | themecycle 断言扫全量日志可误报 | run_tests.sh:52 | 日志追加写，历史低帧行混入；应与 sleepwake 同款分段 |
| B8 | tag 直发的 release 无任何测试门 | release.yml 全文件 | kf-tests / node --test 不在流水线内；lint.yml paths 也不含 build.sh/tools/release.yml。修：native-mac job 加一行 `swift run -c release kf-tests` |
| B9 | 仓库版本号滞后无机器防线 | windows/package.json:4、Cargo.toml:3（三处 1.5.1） | 见 §4 版本号专项 |
| B10 | README/DEV_NOTES 与 v1.6.0 签名实现直接矛盾 | README.md:39,102,201；DEV_NOTES.md:24,27,35 | README 仍写「非 Apple Developer ID…右键打开」反向否定公证卖点；DEV_NOTES 声称有 .lproj 文件（仓库无）；素材环境只装 pillow 但 gen_sprites 需要 numpy（新机器 ink 主题中途崩且 mirror 未执行 → 双树不一致） |
| B11 | TESTING.md 帧数断言与实现不符 | TESTING.md:17 | 写「frames=35」，实际阈值 <30 报错、当前每主题 65 张 |

---

## 4. 专项一：版本号一致性（发版阻断项裁定）

| # | 出处 | 当前值 @d8660b3 | 打 tag v1.6.0 后 |
|---|---|---|---|
| 1 | build.sh:66-78（Info.plist，本地） | git describe → 1.5.1 | 不变（本地开发用） |
| 2 | release.yml:57-85（Info.plist，CI） | 占位 sed 写入 | **1.6.0**（tag 驱动，有 grep 复核） |
| 3 | tauri.conf.json:4 | 1.5.1 | **1.6.0**（CI 改写，release.yml:178-183） |
| 4 | windows/package.json:4 | 1.5.1 | **不改写**（仅 lint 一致性用） |
| 5 | Cargo.toml:3 | 1.5.1 | **不改写**（Tauri v2 运行时以 conf 为准） |
| 6 | git tags | 最新 v1.5.1 | — |

**裁定**（两路审查结论冲突，主审复核后裁定）：走 CI tag 发版时产物版本正确、双端更新比较闭环成立（Win Rust 路判 🔴、构建路判无碍，差异在于是否考虑 CI 改写——已确认 release.yml:178-183 存在改写逻辑）。**真实风险**是：①本地 `npm run tauri build` 直出的包自报 1.5.1，若走此路径分发即触发「装完新版仍报有新版」的更新循环（版本比较历史 bug 的变体）；②仓库三处一致滞后一个发布，无机器防线，纯靠事后人工同步提交（如 9be3282）。**结论：打 v1.6.0 tag 前必须同步 bump 或确认只走 CI**；建议在 DEV_NOTES 固化「版本三处同 bump」步骤（B9）。

## 5. 专项二：v1.6.0 更新链路安全性（双端）

**Mac（自研，UpdateService.swift）**——骨架正确（下载→校验→替换→回滚→重启，失败路径有 done 兜底，版本方向性有单测），但第 3 环「验签」是纸糊的：

| 面 | 结论 |
|---|---|
| 传输加密 | ✅ API 与下载均 https |
| 完整性（hash/大小） | ❌ 无 SHA256；仅 >1MB 下限，无上限 |
| 签名校验 | ❌ **核心缺陷**：`codesign -dv` 字符串包含判断——未签名包放行、被篡改的已签名包不验完整性（🔴A1） |
| Gatekeeper | ❌ 全链不打 quarantine，恶意/损坏包执行无系统拦截（A1 放大器） |
| 版本方向性 | ✅ isNewer 逐段比较、解析失败保守 false、反向用例已入单测 |
| 下载失败/磁盘满 | ✅ HTTP≠200/<1MB/write throws → done(false)；ditto 60s 超时 terminate |
| 替换失败/回滚 | ⚠️ 回滚 try? 吞错（A15） |
| 重启 | ⚠️ 先启后杀双实例（A16） |
| 弹窗形态 | ❌ 原生 NSAlert runModal（🔴A6）；静默发现新版只标菜单 ✓；安装失败零反馈（A13） |
| 并发 | ⚠️ 无 in-flight 防护（A13） |

**Windows（tauri-plugin-updater 2.11.0，已核对本机 registry 插件源码）**——架构正确，无自研下载执行代码：

- 仅 https ✅（reqwest 默认校验证书，dangerous 未开）；执行前 **minisign ed25519 全量字节验签** ✅（pubkey 嵌入 tauri.conf.json:64，`createUpdaterArtifacts: true` 配套；仓库全历史无私钥 ✅）；无路径拼接注入 ✅（tempfile 随机目录）；残余面为上游已知 TOCTOU 窗口（业界接受）。
- 前端流程问题见 W3（死局）、W10（版本源混用）、R6（relaunch 死路径）。
- Windows 安装包未配 Authenticode 签名（SmartScreen 首跑拦截，更新完整性由 minisign 保证不受影响）。

## 6. 专项三：CI 供应链收口

- ✅ secrets 全走 GitHub Secrets 引用无明文；git 全历史 276 commits 无 p12/pem/私钥入库（`-S "PRIVATE KEY"` 零命中）；`tools/certs/` 仅含公开 G2 中介证书（openssl 验证 subject/issuer）；无 `set -x`。
- ❌ 唯一结构性风险 = 🔴B1（job-env 扩散 + action 未 pin）。
- ⚠️ B2（公证失败仍发产物）、B3（sprites.json 缺失不阻断）、B8（无测试门）。

## 7. 旧报告回归对照（抽查复核）

| 旧条目 | 现状 | 复核方式 |
|---|---|---|
| R1/P0-1 CSP 缺 connect-src | ✅ **已修**：connect-src 覆盖 api.github.com/open-meteo/geocoding/ipapi.co/*.qweather.com 全部前端 fetch 域；无 innerHTML，动态内容全走 textContent（无 XSS 面） | 逐域 grep 比对 |
| R2 capabilities 缺 allow-set-size | ✅ **已修**：本轮 capabilities↔前端调用面双向对照，**零缺口**（15 自定义命令注册/调用全对齐）；反向查出 4 项过度授权（R5） | 全前端 grep + ACL 清单核对 |
| R3 AX 弹窗硬编码开发机路径 | ✅ **已修**：KingfisherPetApp/DndMonitor grep 无 `~/Developer` | grep |
| R4 勿扰隐藏死锁 | ⚠️ **半修复发**：streak 累计已移出 guard，但「隐藏态清标志」未落码 → 本轮 🔴A3（Mac 两路独立发现） | 源码全仓 dndActive 赋值点核对 |
| R5 doCheckUpdate 无 r.ok | ✅ **已修**：main.ts:151-152 有 r.ok + tag_name 类型/空值双校验 | 亲读 |
| R6 霓虹 13 色键未覆盖 | ✅ **已修**：15 键全覆盖，且 gen_sprites.py:1123-1130 有启动期断言防回归 | 脚本核对 |
| R7 水墨橙检测死分支 | ✅ **已随 numpy 重写移除**（当前无任何橙检测代码） | 全文通读 |
| 旧报告其余条目 | 本轮未见复发点名 | 三波深审顺带覆盖 |

---

## 8. 🟢 可选（摘要）

Mac：BranchController.swift:121 硬编码 27 vs feetOffset=26；Poop resumeFall 同帧覆盖 .falling；Effects.swift:195 音符尾长于 close 时限 0.1s；Behavior.swift:440 蛋落点不 clamp；SpriteLibrary.swift:205 探针超时悬跨睡眠；Behavior.swift:969 内层 hold 强捕获 self（非环，风格）；Effects.zzzIdleTimer 不随 clearAll 撤销；和风 Key 明文 UserDefaults（注释自认 accepted risk）；getJSON 放行 resp==nil；更新弹窗文案残留「前往下载？」；WeatherService start() 乐观置 .ok；frontmostApplication 后台队列读；英文界面带中文预警级别；勿扰无菜单状态行；Watchdog ps %cpu 判据实测健康。
Win：sprite.ts:50 注释与降级行为相反；hittest.ts:17 setIgnore 先置后调；effects.ts:43 对唱回调不随 speed 缩放；zhUI() 四处拷贝；poop.html:74 容量满计数漂移（自愈）；audio_active 2s 一次 COM 往返可降频；prefs_get/set 无锁读改写；kflog 时区偏移只算一次；release `panic="abort"` 下少量 unwrap；setSize 空 catch（历史事故同行的残留防御缺口）；is_zh 从 PATH 解析 reg.exe；workflow_dispatch 死码；gen_sprites poop 帧重复渲染、陈旧注释；release.yml 文案瑕疵（头注释、releaseBody 缺括号）；draw_note 依赖系统 ♪ 字形。

## 9. 正面确认（本轮核过无问题的面）

代际取消全链（四新行为全走 hold/gen，无裸 asyncAfter）；粒子 opacity=0 与 contents 帧名去重；遮挡检测每 10 帧降频；poops/cracks/sun 上限与置 nil；锁屏/睡眠 suspend-resume 配对（PetView/Poop/Branch/Behavior 四件套三入口全停 + resume 幂等）；fallAway 停 timer/hatchIn 恢复；树枝三坑（onWindow 标志/预显/nearestSurface/clampPerch）全守；Growth/Settings/DayRhythm 数值全 clamp 无除零；Win capabilities 零缺口无 XSS 面；Win updater minisign 验签链完整；FFI 句柄/结构体布局/回调 panic 安全干净；GetProcessMemoryInfo 历史坑已修；weathersvc 15s 超时+重入护栏+key 不落日志；growthsvc trunc+clamp 全程；audio 池化不叠加；双端单测同口径且直打真实现（.mjs/纯函数）。

---

## 10. 给评审者的抽查指引（高价值复核点）

1. **A1**：读 `UpdateService.swift:153-163`，对照 `codesign -dv` 与 `codesign --verify --strict` 语义；确认未签名 zip 在当前实现下的放行路径。
2. **A2/A3**：沿 `DndMonitor.swift:61-67` → `Behavior.swift:998-1017`（enterDnd）核对 suspend 清单与守卫；再全仓 grep `dndActive` 验证「唯一清零点是 exitDnd 且被 active 门控」。
3. **A5**：`WeatherService.swift:106` 请求参数 + `:263` 阈值，对照 Open-Meteo 文档 `wind_speed_10m` 默认单位；注意 Tests/main.swift:141-145 的口径。
4. **W1/W2**：`behavior.ts` grep `beginAction()` 与 `leavePerchWin()` 的调用矩阵，核对 callOver/weatherRetreat/affectionVisit/startPerchWindow 四处缺席。
5. **W3**：`main.ts:178-196` 的 `!up?.available` return 分支 + `update.html` 按钮清空逻辑，推演用户视角。
6. **B1**：`release.yml` job env 块与 `uses:` 清单，确认 secrets 可见范围与 action 引用方式。
7. **§4 版本号**：`release.yml:178-183` 的改写语句存在性——这是「Win 更新循环」判级的关键分歧点。
