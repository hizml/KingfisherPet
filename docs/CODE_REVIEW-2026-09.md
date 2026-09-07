# 翡 · KingfisherPet 全量 Code Review(2026-09)

> 评审对象:main @ v1.4.59 之后(215 commits)。方法:三轮五路并行深审,逐行通读,非抽样。
> 本文档自包含:每条带 `文件:行号`,可凭仓库直接复核。分级:🔴 必修(生产级) / 🟡 建议 / 🟢 可选。
> 用途:交外部 Agent / 人工评审复核。文末附「给评审者的抽查指引」。

---

## 0. 覆盖度声明

| 域 | 文件 | 状态 |
|---|---|---|
| Mac 源码 | Sources/KingfisherPet/*.swift 全部 14 文件 3996 行 | ✅ 逐行 |
| Windows 前端 | windows/src/*.ts 14 个 + index/settings/update/crack/poop.html 5 个 | ✅ 逐行 |
| Windows Rust | src-tauri/src/{lib,system,windows,kflog}.rs | ✅ 逐行 |
| 构建链 | build.sh、Package.swift、Cargo.toml、tauri.conf.json、capabilities/、package.json、vite.config.ts | ✅ 逐行 |
| CI | .github/workflows/release.yml、lint.yml | ✅ 逐行 |
| 素材管线 | tools/gen_sprites.py(约 1210 行)+ 磁盘产物比对(sprites.json×6、PNG 抽查) | ✅ 逐行 |
| 文档 | README.md(中英)、docs/TODO.md、docs/TESTING.md、DEV_NOTES.md(对照实现) | ✅ 逐节核对 |
| 未审 | Resources 产物本身、dist/、.zcode/ | 产物/生成物,不属源码 |

---

## 1. 🔴 必修(9 条)

### R1 Windows:生产包「检查更新」已被 CSP 拦截
- **位置**:`windows/src-tauri/tauri.conf.json:31`(CSP)、`windows/src/main.ts:111`(fetch)
- **问题**:CSP 为 `default-src 'self' ...` 无 `connect-src`,回落 default-src `'self'` → 打包版(Tauri 注入 CSP)中 `fetch("https://api.github.com/...")` 被阻断。dev 模式(devUrl)不注入 CSP,本地一切正常——**典型"只在发布版坏"**。
- **影响**:v1.4.59 生产包:手动检查永远弹"失败",自动检查永不亮「发现新版本」。
- **修法**:CSP 追加 `connect-src 'self' https://api.github.com`;打一次本地包实测。

### R2 Windows:capabilities 缺 allow-set-size,跨 DPI 尺寸修正静默失效
- **位置**:`windows/src-tauri/capabilities/default.json`(缺失项)、`windows/src/main.ts:144`
- **问题**:`petWin.setSize(new LogicalSize(160,160))`(200% 屏跨 DPI 专项修复核心语句)无 IPC 权限,被 catch 静默吞。与幽灵 API 事故(currentMonitor)同构:**catch 静默 + 权限缺失 = 看不见的失效**。
- **修法**:permissions 加 `core:window:allow-set-size`。

### R3 Mac:AX 引导弹窗硬编码开发机路径
- **位置**:`Sources/KingfisherPet/KingfisherPetApp.swift:302`
- **问题**:辅助功能引导文案硬编码 `~/Developer/KingfisherPet/build/KingfisherPet.app`,其他用户机器路径不存在,引导必失败。
- **修法**:改 `Bundle.main.bundleURL.path` 动态生成。

### R4 Mac:勿扰中隐藏鸟 → 状态机死锁,鸟唤不回
- **位置**:`KingfisherPetApp.swift:179-205`(dndCheck 第一道 guard)、`Behavior.swift:680`(hatchIn 拒绝)
- **路径**:勿扰激活(dndActive=true)→ 用户点「显示/隐藏」走 fallAway(onScreen=false)→ dndCheck 第一道 guard `isOnScreen` 直接 return → **fsOffStreak 永不累计 → dndActive 永真** → hatchIn 在勿扰中拒绝复活 → 只能重启。
- **修法**:dndCheck 对 offscreen/sleeping 也累计 fsOffStreak,只跳过 enter/exitDnd 副作用;或 fallAway 时同步退 dnd。

### R5 Windows:doCheckUpdate 无 r.ok 校验
- **位置**:`windows/src/main.ts:108-121`
- **问题**:GitHub API 403 限流返回 JSON 无 tag_name → `latest=undefined` → `undefined !== "v"+cur` 恒真 → 弹「发现新版本 undefined」。
- **修法**:`if (!r.ok || !latest) throw new Error(...)` 后再比较。

### R6 素材:霓虹主题 13 个色键未覆盖,flat 残留
- **位置**:`tools/gen_sprites.py:58-73`(THEME_PALETTES.neon)vs `:74-99`(ink 覆盖完整可作对照)
- **问题**(实测 diff):neon 未覆盖 `EGG_SHELL/EGG_SPCK/FISH_BODY/FISH_DARK/BRANCH/BRANCH_L/BRANCH_D/LEAF/LEAF_D/MOUTH/TONGUE/SWEAT/BLUSH` → 霓虹主题的蛋是米色奶油蛋、树枝棕枝绿叶、叼着灰鱼,与"青+品红"设计冲突。
- **修法**:按 ink 键集补齐;加启动断言 `ink 覆盖键集 ⊆ 各主题覆盖集` 防再漏。

### R7 素材:水墨「保留一抹橙」是死分支,漏的是嘴舌红晕
- **位置**:`tools/gen_sprites.py:523-530`(post_ink 橙检测)、`:74-99`(ink 调色板)
- **问题**:ink 调色板已把 ORANGE 压灰褐,`r>150 and r-b>60` 检测不到喙/腹(docstring 声称的意图失效);真正命中的是未覆盖的 MOUTH/TONGUE/BLUSH(flat 高饱和橙红)——水墨帧的嘴腔/红晕是橙红色,恰违背 L77 注释「去掉朱砂橙红」。
- **修法**:二选一——ink 调色板补 MOUTH/TONGUE/BLUSH/SWEAT 墨色,或删橙检测分支。

### R8 素材:特效颜色双源且已互相矛盾
- **位置**:`tools/gen_sprites.py:1003-1097`(gen_colors,生成 colors.json)vs `:713-734`(_effect_palette,烘焙进 PNG)
- **问题**(实测):neon 音符 PNG=品红(255,60,160) vs colors.json=橙(255,140,40);ink 太阳 PNG=墨灰 vs colors.json=朱红(200,70,30,直接违背「水墨不用红太阳」设计注释);flat 太阳 PNG=(240,145,59) vs json=(255,204,64)。同一主题下 layer.contents 的 PNG 特效与 CA 矢量特效不同色。
- **修法**:删 gen_colors 手写表,由 _effect_palette 单源生成 colors.json。

### R9 文档:README 中英两版双双缺失最近两个功能
- **位置**:`README.md:77/81-85`(中文菜单/设置清单)、`:226/230-234`(英文)
- **问题**:菜单清单缺「检查更新…」(KingfisherPetApp.swift:608-610 / lib.rs:337-339 均存在),设置清单缺「啄屏幕」(Settings.swift:209-217 / settings.html:31-33)。README 停在 v1.4.49。
- **修法**:两版各补两处;顺带修 3.5-7s(实际默认 2.5-5s)、放音机制 Mac/Win 区分等(见文档组 🟡)。

---

## 2. 🟡 建议修(按域)

### 2.1 行为正确性
| 位置 | 问题 | 修法 |
|---|---|---|
| Behavior.swift:703-721 | enterDnd 不清 `dragging`(suspend():911 有同款清理)——拖鸟时进勿扰,mouseUp 丢失,出勿扰后树枝永不显示 | 补 `dragging = false` |
| behavior.ts:737-761 | dndSet(on) 不清 thinkTimer 也不设 wakeGrace:勿扰中若定时器被限流未停,隐藏鸟空跑动作、唤醒后「迟到屎」闪现 | 进入时 clearTimeout |
| behavior.ts:534-545 | sleepForUserAbsence 缺 stopPerchCheck:锁屏期间 20fps window_rect IPC 照跑且移动睡着的鸟(Mac 对照 L859 有停) | 加一行 |
| behavior.ts:816-840 | setMainVisible 返回值无人消费;hide 路径无验证重试——DND 进入时 hide 失败 = 鸟叠在全屏视频上无兜底 | hide 后验证+重试 |
| SpriteLibrary.swift:195-199 | 叫前探针 5s 超时自愈只清 busy,那声叫永久丢失——与注释「fail-open」矛盾(超时路径实为 fail-closed) | 自愈时补 peepPlay() |
| lib.rs:271-278 | tray_pin_guidance 先写 prefs 标记再 emit:慢机(WebView 加载>3s)时事件丢失且标记已落盘 → 引导永不弹 | prefs_set 挪到 emit 后,或前端 ack 回写 |
| behavior.ts:317-324/530 | zzz 出口 y=50,Mac 是 maxY-34,低 16px | 50→34 |
| behavior.ts:327-334 | startSun 按朝向硬编码不钳屏;Mac 按屏幕空侧取位 | 对齐 |
| behavior.ts:240-259 | startWalk 走出栖窗语义偏差(重栖同窗悬空 vs Mac 50% 换窗/飞走);栖窗消失时 Win 留半空 | 对齐 afterWalk |
| behavior.ts:356-364 | startPoop 时序:Mac 0.5 酝酿+0.4 收尾;Win 立即掉+0.8 | 对齐分段 |
| Behavior.swift:233-264 | think 权重未归一:activity=1 时 sleep 兜底桶占 ~37% 反成最高频(若非有意) | 归一化 |
| Behavior.swift:605 + PoopController:201 | CG↔NS y 换算用鸟所在屏高,CG 全局坐标实锚定主屏——双屏不同分辨率时判定错位(单屏全对) | 统一 screens[0].height |
| CrackController 启动序(KingfisherPetApp:107-109) | crack.start() 先于 bird 赋值:副屏恢复时裂纹层尺寸按 main 屏布局且永不再重算 | start 挪 bird 赋值后 |
| poop.ts:56-60 | stage-origin 在子页 listener 注册前发出:ox/oy≠0 布局(任务栏在左/上、副屏负坐标)舞台整体错位 | 挪到 childReady 握手后 |
| main.ts:99-104 | openUpdateDialog:close 异步销毁与 new 竞速可撞 label;Promise 未 catch | catch+确认销毁 |

### 2.2 状态链 / 协议
| 位置 | 问题 | 修法 |
|---|---|---|
| main.ts:105-107 + settings.html:84 | **语言链断裂**:kf_lang 只读不写(死键);"lang" 事件无发送方 → 设置窗语言永远高亮「跟随系统」 | lang 收到时回写 + settings-sync 带 lang |
| settings.html:87-88 | 滑杆 oninput 每 tick emit → Rust refresh_menu 每次重建托盘菜单(拖一下重建几十次) | onchange 或防抖 |
| main.ts:78-84 | "setting" 协议 Number() 无 NaN 防护,畸形载荷 → 行为链静默瘫痪 | isFinite 兜底 |
| update.html:48 | URL 异常默认显示「已是最新版本 v」误导 | 默认 error 分支 |
| KingfisherPetApp:179 vs Behavior:702 | dndActive 双份真值靠手工同步,emergencyReset 等旁路不回滚 | 单一权威 |

### 2.3 构建链 / CI
| 位置 | 问题 | 修法 |
|---|---|---|
| package.json build | `tsc` 产出 .js 且 vite resolveExtensions **.js 优先于 .ts**——改 .ts 未重跑 build 时 dev 跑旧编译产物(本次实抓 behavior.js 比 .ts 新) | `tsc --noEmit && vite build` + 删 src/*.js |
| tauri.conf.json:4 | version 1.4.53 落后 v1.4.59 六版(CI tag 覆盖,但 dispatch/本地 dev 版本错) | 打 tag 时同步提交 |
| lint.yml:3-5 | 无 pull_request 触发;paths 不含 Sources//build.sh——Swift 编译错误要烧版本号才暴露 | 加 PR 触发 + macos job(swift build) |
| lint.yml:28 | `as any` 检查漏 `: any`(8 处绕过,含 main.ts/poop.ts/crack.ts) | grep 正则收紧 |
| release.yml:151-152 | workflow_dispatch 时 tagName=分支名,产出畸形 release | dispatch 守卫 |
| release.yml:135/86 | npm install(应 ci);签名失败回退 ad-hoc 无 warning(授权失效无人知) | npm ci + ::warning |
| release.yml:31-35 | 资源 cp 一条 `|| true`:任一 json 缺失则该主题 png 全丢仍绿灯(本地 build.sh 是分条容错) | 分条对齐 |
| release.yml:76 | plist 版本 sed 无匹配校验,静默留 1.3.0 | sed 后 grep 校验 |
| kflog.rs:33-39 | 时间戳 UTC,与用户本地差 8h,排障时间线对不上 | 本地时区偏移 |
| Cargo.toml:26/30 | 死 features:Win32_System_Power(未用)/ Win32_System_Memory(LocalFree 实在 Foundation) | 删+check |
| lib.rs:196-218 | is_zh() 每次 build_menu spawn reg.exe | 启动探测一次缓存 |

### 2.4 素材管线(gen_sprites.py)
| 位置 | 问题 | 修法 |
|---|---|---|
| :553-556 | 水彩 GaussianBlur 未预乘,透明区黑 RGB 渗入 → 轮廓内缘 1px 黑边 | 预乘/边缘外扩 |
| :453 | 像素风 NEAREST 降采样只取左上像素,腿/喙细部跨帧闪烁 | 降采样改 BOX |
| :455-461 | 像素量化色板手抄 BASE_PALETTE 且不全,改动即漂移 | 由 BASE_PALETTE 派生 |
| :535-541 | 水墨阈值 lum=200 处硬带跳变 | 180-220 线性过渡 |
| :516-541/:560-565 | post_ink 逐像素 getpixel(约 350 万次)+ 水彩每帧重生成纸纹——全量再生分钟级 | 向量化+噪声缓存 |
| :121-138 | 字体路径 macOS 独占,非 mac 静默降级(音符变豆腐) | 警告+补字体路径 |
| :908-912 | fly_0/fly_fish_0 孤儿帧(12 张 PNG 白打包) | 删或入序列 |
| :54-112 | 三张平行表(THEME_PALETTES/POSTPROCESSORS/THEME_NAMES)无一致性断言 | 启动 assert |

### 2.5 文档
| 位置 | 问题 | 修法 |
|---|---|---|
| README:54 | 「3.5–7 秒」把最低活跃度当默认值(默认 2.5–5.25s) | 改写 |
| README:67 | 放音检测把 Mac「叫前查」写成双平台通则(Win 是 2s 轮询) | 分开标注 |
| README:74 | 「鸟跨屏移动」不准确(自主行为全钳当前屏,跨屏仅拖拽) | 改「可拖拽跨屏」 |
| README:55 | 「已在顶端则直线俯冲」无对应分支(实际是省去飞升段,悬停照旧) | 改写 |
| README 中英 | 结构性不对等:中文独有目录结构/技术要点;英文独有 Windows/Robustness/Bilingual 整节 | 对齐 |
| TODO.md:21-22 | 「现在是 ad-hoc 签名」已不成立(自签证书已落地) | 更新 |
| TODO.md:40-42 | 「文案走 NSLocalizedString」已不成立(Language.swift 运行时表;.strings 成死文件且缺新键) | 更新+处理 .strings |
| TESTING.md:14 | 断言写 3-6,代码实际 2-8 | 改 2-8 |
| DEV_NOTES:71-96 | stationary 已全线移除/特效与层级章节落后实现两代 | 重写该段 |

---

## 3. 死代码清扫清单

**Windows**:`lib.rs` show_window_bottom_right(死命令,且不查 DND)、login/act_/spd_/lang_ 四个不可达菜单分支、`let menu = Menu::with_items(...); let _ = menu;` 白建、windows.rs `let _ = HWND::default();`;`main.ts:22` #effects 死变量 + index.html 同款 div/keyframes、setupCrack/THEMES 死导出、poop.ts/crack.ts 未读 win、settings.html L72/86 自启残留注释;Cargo 死 features(2.3 组)。
**Mac**:axWarnOnce+axWarned(零调用)、Behavior.headOffset、PetView.mouseDownTime、fsDiagSnapshot 生产噪音(建议环境变量门控)、launchPath 废弃 API、feetOffset 三文件三种写法(26/27/字面量)。
**gen_sprites.py**:_split_alpha、post_clay 的 edge 链、rim 重复 putalpha、alpha_composite no-op、ImageChops_mul 恒等链、render_shadow 死形参、montage label 死项(约 15 行)。
**注释腐化(比死代码更危险)**:behavior.ts:200 旧权重表(与 :205 及代码不符)、:654-660 描述已废弃的「先显示再执行」方案;KingfisherPetApp:172 注释 5s 实为 15s;Behavior:152 注释 ±20 实为 70。

---

## 4. 明确不在本批(记录待办)

1. 双屏坐标统一(R4 组的屏高换算类,需双屏实测)
2. 双端行为细节对齐 5 项(walk 语义/sun 侧选/zzz 高度/poop 时序/onGround 容差)
3. AppDelegate 拆分(DND/Update/Watchdog 独立类型)、WindowTracker 四函数去重、三套 60fps 动画骨架提炼、AssetLoader 统一 —— 纯重构
4. gen_sprites 向量化 + pose 参数数据表化
5. `: any` 8 处逐个改 unknown(CI 收紧后逐步)
6. 同步 AX IPC 挪后台队列(前台 App 卡死可拖主线程,当前可接受)

---

## 5. 总体评价(三路一致结论)

**架构健康度:中上。** 亮点:单 UI 线程模型贯彻彻底(全部 Timer 挂 main RunLoop .common,网络/看门狗回调显式回主线程);**代际取消(gen)**干净解决桌面宠物"动作链被打断继续推进"的经典竞态;visBusy 串行锁+双向让位是教科书级显隐处理;窗口生命周期纪律统一(orderOut/close/池化各得其所),未发现真实内存泄漏路径;双看门狗(心跳+出屏)+熔断+自重启的兜底成熟度超出同体量项目;素材管线 seed 全定死、跨主题逐位可复现,sprites.json 与双端消费契约实测零漂移;注释密度极高且几乎每条绑定真实事故。

**风险集中两处**:① 近期勿扰/检查更新改造引入的状态机裂缝(R1-R5,其中两个"只在发布版坏");② 素材管线的调色板覆盖不完整与特效双源(R6-R8)——都是"增量改造没有全量回归"的产物。修复批优先于任何新功能。

---

## 6. 给评审者的抽查指引

本报告的结论最容易被证伪的点,建议优先抽查:
1. **R1(CSP)**:本地 `cd windows && npm run tauri build`,装包后点托盘「检查更新」——若弹「失败」即证实;dev 模式对照(正常)。也可读 tauri.conf.json:31 确认无 connect-src。
2. **R4(勿扰死锁)**:Mac 开全屏视频等勿扰触发(约 6s)→ 退出全屏前点菜单「显示/隐藏」→ 再点「显示/隐藏」——鸟是否唤不回。代码路径:KingfisherPetApp.swift:184 guard + Behavior.swift:680。
3. **R6(neon 色键)**:直接 diff THEME_PALETTES 的 neon 与 ink 键集合(gen_sprites.py:58-99);或看 Resources/Sprites/neon/egg_0.png 是否米色蛋。
4. **R8(特效双源)**:对比 Resources/Sprites/neon/colors.json 的 note 值与 _effect_palette(713-734)neon 的 note 值。
5. **R2(set-size)**:capabilities/default.json permissions 列表 grep set-size;main.ts:144 是否在 try/catch 中被吞。
