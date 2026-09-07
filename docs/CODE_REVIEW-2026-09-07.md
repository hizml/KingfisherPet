# 全仓代码评审报告(2026-09-07 · 三轮合并版)

> 评审基线:`7e2337b`(2026-08-25,工作区 clean)。
> 本文合并当日三轮评审:①首轮全量逐行(Mac Swift 14 文件 / Win TS 14 + HTML 5 / Rust 全部 / 构建配置);②深审轮(三路深挖 Mac/TS/Rust+构建链);③补漏轮(CI workflows、tools/run_tests.sh、覆盖基线核对)。
> 状态:**只报未改**。每条给位置、证据、影响、置信度;标注 `【已复核】`= 定稿前在源码上重新验证过,`【静态推演】`= 代码证据链完整但未运行验证,`【未实测】`= 需构造场景。
> 评审者不需要读原始对话,但请先读 CLAUDE.md 的不变量章节与下文「坐标与平台背景」。

---

## 0. 覆盖情况(诚实声明)

| 范围 | 方式 | 状态 |
|---|---|---|
| `Sources/KingfisherPet/*.swift`(14 文件) | 逐行 | ✅ |
| `windows/src/*.ts`(14)+ 5 个 HTML | 逐行 | ✅ |
| `windows/src-tauri/`(6 个 .rs + conf/capabilities/Cargo) | 逐行 | ✅ |
| 构建配置(Package.swift/build.sh/vite/tsconfig/package.json) | 逐行 | ✅ |
| `.github/workflows/`(release/lint)、`tools/run_tests.sh` | 逐行 | ✅ |
| `tools/gen_sprites.py`(1210 行,离线画图工具,不进产物) | 结构 + json.dump 位点 | ⚠️ **唯一有分量的盲区**,未逐行 |
| 资产(png/wav)、lockfile、docs、README、`windows/src/*.js`(tsc 产物) | — | ➖ 跳过(但见 B8:tsc 产物本身是个坑) |

**坐标与平台背景**(评审 A 类发现的共同前提):
- macOS:CGWindowList 矩形为 CG 全局坐标(顶左原点,**锚定主屏**),换算 NS-y 唯一正确公式 `主屏高 - cgY`。`WindowTracker.swift` 四处均正确用 `NSScreen.screens.first` 并有注释说明。
- Windows:全链物理像素、顶左原点(behavior.ts 文件头注释);逻辑常量进物理世界必须乘 `_scale`。
- Tauri 2:CSP 只在**打包版**注入(dev 不注入——dev 测不出 CSP 问题);窗口 API 受 capabilities 白名单管控,未授权的调用被 deny 且项目里大量 `catch { /* */ }` 静默吞。

---

## 一、P0 · 生产级(打包版才发作 / 功能整体坏死)

### P0-1. CSP 缺 `connect-src`,打包版检查更新必失败 【已复核·静态】

- 位置:`windows/src-tauri/tauri.conf.json:31`
- 证据:
  ```json
  "csp": "default-src 'self'; img-src 'self' data: blob: asset: http://asset.localhost; script-src 'self'; style-src 'self' 'unsafe-inline'"
  ```
  `fetch("https://api.github.com/...")`(main.ts:111)受 `connect-src` 管控;未声明时回退 `default-src 'self'` → 域外请求全部被 CSP 拦截。
- 影响:**打包版(v1.4.x 生产包)手动检查更新永远弹「检查更新失败」,自动检查永远不亮「发现新版本」**。dev 模式 Tauri 不注入 CSP,所以本地 dev 全程测不出。
- 建议方向:补 `connect-src 'self' https://api.github.com`;修完必须打一次包实测(dev 验证无效)。

### P0-2. capabilities 缺 `core:window:allow-set-size`,跨 DPI 尺寸修正静默失效 【已复核·静态】

- 位置:`windows/src-tauri/capabilities/default.json`(权限清单无 set-size)vs `windows/src/main.ts:143-145`:
  ```ts
  petWin.onScaleChanged(async () => {
    try { await petWin.setSize(new LogicalSize(160, 160)); } catch { /* */ }
  });
  ```
- 影响:该调用的目的是跨不同 DPI 显示器时把窗口重设为 160 逻辑尺寸(注释:否则坐标全链错位)。capabilities 未授权 → IPC deny → 被 `catch` 静默吞 → 200% 屏等场景尺寸修正从未生效。与历史上 `currentMonitor` 幽灵 API 事故同构(调用失败被吞,功能默默不存在)。
- 建议方向:capabilities 补 `core:window:allow-set-size`,打包实测跨 DPI 拖拽。

### P0-3. Mac 勿扰 + 用户隐藏 = 死锁,鸟永远唤不回 【已复核·静态推演】

- 位置链:`KingfisherPetApp.swift:184-186`(dndCheck 首个 guard)+ `Behavior.swift:679-680`(hatchIn 拒绝勿扰)
- 推演(每一环都有代码依据):
  1. 全屏应用触发 `enterDnd()`(鸟 orderOut,但 `onScreen` **保持 true**——enterDnd 不改它);
  2. 勿扰中用户点「显示 / 馁藏」→ `toggleVisibility` → `setVisible(false)` → `onScreen==true` → `fallAway()` → `onScreen=false`;
  3. 全屏退出后,`dndCheck` 的首个 guard `behavior.isOnScreen else { dndSkip; return }` 提前返回 → `fsOffStreak` 永不累计 → `dndActive` **永久卡 true**;
  4. 用户再点「显示 / 隐藏」→ `hatchIn()` 开头 `guard !dndActive else { return }` → 拒绝复活。
  结果:**鸟消失且唯一恢复入口失效,只能重启进程**。
- 建议方向:offscreen 时也累计 `fsOffStreak`(只跳过 enterDnd/exitDnd 的副作用);或 hatchIn 在 `onScreen==false && dndActive` 时先清 DND。
- 验证:全屏视频进入勿扰 → 菜单隐藏鸟 → 退出全屏 → 菜单显示鸟 → 观察是否唤得回。

---

## 二、P1 · 确定功能 bug

### A1. Windows 空中拉屎 X 坐标漏乘 DPI 缩放 【已复核】

- 位置:`windows/src/behavior.ts:286-287`(`startFly`)
- 证据:
  ```ts
  const g = gen, ax = o.x + 80 + (tx > o.x ? -50 : 50);   // 逻辑像素直接加物理坐标
  setTimeout(() => { if (gen === g) dropPoopAt(ax, o.y + (SIZE - 40) * _scale); }, ...);  // y 乘了,x 没乘
  ```
  同文件正确写法对照(`:360`,`startPoop`):`o.x + (80 + (facingRight ? -50 : 50)) * _scale`。
- 影响:125%/150%/200% 缩放下空中屎横向偏位 20~80 物理像素。

### A2. Windows 唤醒时「鸟隐藏」分支不解除静音 【已复核】

- 位置:`windows/src/behavior.ts:556`:`if (!onScreen) { userSleeping = false; return; }` 缺 `setSleepMuted(false)`。
- 对照 macOS 对应分支(`Behavior.swift:884-889`)有 `mutedForSleep = false`——移植漏行。
- 影响:隐藏鸟经一次锁屏/睡眠再唤醒,叫声永久静音(直到 watchdogKick/dndSet 碰巧解禁)。

### A3. Windows 睡眠期间栖窗跟随轮询不停 【已复核·程度未实测】

- 位置:`behavior.ts:534-545`(`sleepForUserAbsence`)只清 think/zzz,不停 `perchTimer`(50ms `window_rect_cmd` + 每 10 跳全窗口枚举)。
- 对照:macOS 同路径显式 `stopPerchCheck()`(`Behavior.swift:859`);CLAUDE.md 把「睡眠期间不能有任何待处理 timer」列为不变量。
- 影响:锁屏(未睡)时 IPC 空转(WebView2 遮挡节流可缓解,程度未实测);锁屏期间栖窗消失 → `perchFlee → startFly` 鸟在锁屏后飞。

### A4. Windows「锁屏后睡眠」唤醒时鸟在锁屏后满血活动 【静态推演·未实测】

- 位置:`windows/src-tauri/src/system.rs:30-41`:时钟跳变无条件「emit sleep → 3s 后 emit wake」,发 wake 前不检查是否仍锁屏。
- 推演:锁屏离开 → 系统自动睡 → 唤醒(屏仍锁)→ 前端收到 wake → RAF 恢复 + 赖床后 finish,鸟在锁屏后活动/拉屎;真解锁时第二个 wake 被 `userSleeping==false` 吞掉。macOS 用 DarkWake 守卫 + 独立 `screenUnlocked` 规避。
- 建议方向:发 wake 前用同文件 `is_locked_here()` 复查。

### A5. macOS 叫前探针判据过窄(只认 "1") 【已复核】

- 位置:`SpriteLibrary.swift:212`。探针 JS(`:233-238`)返回 playbackRate 原值字符串,Swift 判 `txt == "1"`。
- 影响:2×/0.5× 速播放返回 "2"/"0.5" → 判「没在播」→ 照叫,放音勿扰失效。("0"/"nil" 两个分支是对的。)
- 建议方向:解析数值判 `> 0`,解析失败 fail-open 照叫。

### A6. macOS 多屏 CG→NS 换算用错屏高(两处) 【静态推演·触发条件=副屏】

- 位置:`Behavior.swift:605`(`wouldOvershootTop(surfaceY: scr.frame.height - f.minY)`)、`PoopController.swift:201`(`topNS = screenH - b.minY`)。
- `frameOfWindow` 返回 CG 全局坐标,换算必须用**主屏**高;两处用了鸟所在屏 `scr`。`WindowTracker` 四处均正确(screens.first)。
- 影响:鸟在与主屏**高度不同**的副屏时,「拖太高飞走」判定与屎承载判定系统性偏移。`checkPerch` 的 dyw 增量两侧屏高相抵消,不受影响。
- 验证:外接高度不同的屏,鸟拖去副屏做栖窗拖高实验。

### A7. Windows 进入勿扰不清 thinkTimer,幽灵行为链持续 【已复核】

- 位置:`behavior.ts:737-761`(`dndSet(true)`)手动 `gen++; busy=false`,**没走 `beginAction()`**,thinkTimer 不清;`think()`(198)只查 `busy/perchMoving/wakeGrace`,不查 dnd。
- 影响:勿扰(全屏看片)期间,先前排程的 think 照常触发 → 隐形鸟起飞/拉屎/唱歌出特效(部分被舞台隐藏掩盖,但行为链全程空转,状态在 DND 结束时是脏的)。
- 对照:macOS `enterDnd` 走 `beginAction()`(invalidates thinkTimer)。
- 修法:`dndSet(true)` 里 `if (thinkTimer) { clearTimeout(thinkTimer); thinkTimer = null; }`。

### A8. macOS 进入勿扰不清 `dragging`,树枝此后永不显示 【已复核·触发窗口极窄】

- 位置:`Behavior.enterDnd`(macOS)调 `beginAction()`,但 `dragging` 只由 `petViewDidEndDrag`/`suspend()` 清。
- 影响:用户正拖着鸟的瞬间进勿扰(mouseUp 在窗口 orderOut 后丢失)→ `dragging` 永真 → `BranchController.tick` 的 `shouldShow` 含 `!beh.dragging` → 树枝永不再现,直到下次拖拽。触发窗口极窄,与 A7 同类(勿扰入口的清理不全),建议一并补。

---

## 三、P2 · 健壮性 / 一致性

### B1. emergencyReset 后裂纹数据与图层永久脱节 【已复核】

- `CrackController.swift:56-62` `purgeLayers` 注释称「下次 peck/setVisible 时会重建」,实际 `setVisible(true)`(39-42)只 orderFront 不重建;唯一挂回路径是 peck 里 55px 内再啄那条(`:71`)。
- 影响:看门狗熔断后老裂纹永久隐形,但 `cracks` 数据、`hasCracks=true`、空覆盖层窗口常驻(僵尸状态)。

### B2. 更新/权限弹窗绕过本地化 + 写死开发机路径 【已复核】

- `KingfisherPetApp.swift`:`updateAlert`(858-882)硬编码中文;`autoCheckUpdate`(841-850)用 `Language.current == "zh"` 三元而非词条;`promptAccessibilityOnce`(294-312)硬编码中文 + 写死 `~/Developer/KingfisherPet/build/KingfisherPet.app`(发布版用户照做找不到,建议改 `Bundle.main.bundleURL`)。
- 影响:英文用户看中文弹窗;引导路径对正式用户错误。

### B3. `Localizable.strings`/`.lproj` 死资源 【已复核】

- 全仓无 `NSLocalizedString` 调用(Language.swift 自建表);`build.sh:41-46`、`release.yml:37-40` 仍打包;docs/TODO 描述过时。白占包体 + 误导维护者。

### B4. Windows 检查更新不校验响应 【已复核】

- `main.ts:114-115`:`(await r.json()).tag_name as string` 无 `r.ok`/`typeof` 校验;GitHub 限流返回 error 对象时 `tag_name` undefined → 手动路径弹「发现新版本 undefined」,静默路径菜单错误标亮。

### B5. Windows settings.ts 无 NaN 防护 【已复核】

- `settings.ts:5-8`:`Number(localStorage.getItem(...))` 脏数据 → NaN 传染 `think` 随机区间(`setTimeout(NaN)` 按 0)→ 行为链空转。macOS 侧有 clamp,Windows 没有。

### B6. Windows 语言状态链断裂(两个独立缺口) 【已复核·grep 验证】

- 缺口 1:`localStorage.kf_lang` **只读不写**(读点 main.ts:105、update.html:26;全仓无写入点。语言实际持久化在 Rust 侧 `%APPDATA%/KingfisherPet/settings.json` 的 `lang` 键,两套存储互不相通)。影响:update.html / zhUI() 的语言判断永远走 `navigator.language` 兜底——碰巧多数场景正确,但用户显式选了 en/zh 后弹窗语言可能不符。
- 缺口 2:Rust 打开设置窗时 `emit("settings-open", {lang, autostart})`(lib.rs:568),但 **settings.html 只监听 `settings-sync`**(settings.html:92),而 main.ts 的 `settings-sync` 快照**不含 lang 字段**(main.ts:88-91)→ 设置窗重开后语言按钮永远高亮「跟随系统」,与真实状态不符。
- 修法方向:统一语言状态到 Rust 一处;`settings-sync` 快照补 lang(或 settings.html 直接监听 settings-open)。

### B7. stage-origin 在子窗 listener 注册前发出 【已复核·条件性发作】

- `poop.ts:57-60`:`emitOrigin()` 在创建窗口后立刻调用,而子窗(poop.html/crack.html)的 `stage-origin` listener 要等页面模块加载后才注册——事件丢失。
- 单屏 + 任务栏在底部时 ox/oy=0,translate(0,0) 丢不丢无感;**任务栏在左/上、或副屏负坐标**(工作区并集原点 ≠ 0)时舞台整体错位。修法:把 emitOrigin 挪到 childReady 握手完成后。

### B8. `tsc` 产物 `.js` 与 `.ts` 同目录,vite 解析 `.js` 优先 → dev 跑旧代码 【已复核·静态】

- `package.json` `"build": "tsc && vite build"`,tsconfig 无 `noEmit`/`outDir` → `tsc` 把 `.js` 落在 `src/` 旁边(gitignore 了);vite 默认扩展名解析顺序 `.js` 在 `.ts` **之前** → 改了 `.ts` 没重跑 build 时,`import "./poop"` 解析到**过期的 `.js`**(本机 behavior.js 1071 行 vs behavior.ts 861 行,即旧版残留的实证)。
- 修法:`"build": "tsc --noEmit && vite build"` + 删除存量 `src/*.js`。

---

## 四、P3 · 死代码与注释漂移

- **C1** Rust 死命令 `show_window_bottom_right`(lib.rs:130-139 注册,:400 handler;前端零调用;behavior.ts:656 注释描述的流程与现 hatchIn 不符——stale 注释)。
- **C2** Rust 死事件 `emit("menu","recall")`(lib.rs:481),main.ts 无 recall 分支。
- **C3** lib.rs 死菜单分支:`"login"`(577)/`act_*`(611)/`spd_*`(617)/`lang_*`(623)对应菜单项在改版后已不存在。
- **C4** lib.rs:343-346 建完即弃的 `Menu::with_items`。
- **C5** `Language.didChangeNotification`(Language.swift:13-17)发了无人观察。
- **C6** 注释漂移合集:Behavior.swift:152「±20px」vs 代码 70;BranchController.swift:7「60fps」vs 实际 30fps(L68);behavior.ts:199-205 两行权重注释互相矛盾且与代码不符(代码对);hittest.ts:6-8「睡眠/隐藏归零」vs `refreshGeom` 2s interval 不受门控(L42)。
- **C7** feetOffset 三处三个值:Behavior.swift:25=26、BranchController.swift:23=27、PetView.swift:191 硬编码 26——核心几何无单一事实源。
- **C8** `CrackController.peck`(:69)`cracks.last(where:)` 选「最新」非「最近」裂纹(Windows crack.html:98-100 同样从后往前;两端一致地不是 nearest,影响极小)。

## 五、P4 · 小 nit

- **D1** lib.rs:422/520/607 每次切语言/主题 `Box::leak` 泄漏小字符串(UiState 字段应改 `String`)。
- **D2** main.ts:342-353 「卡隐身自愈」块缩进嵌在 `wdLastZ` 条件内但排版像同级(功能无差,15s tick > 5s 冷却,纯误导)。
- **D3** windows.rs `window_at_point`(:383)用 `GetWindowRect`(含最大化窗口 7-8px 隐形边框),其余表面判定都用 `visible_rect`——遮挡检测可能误判,不一致。
- **D4** system.rs:86/101 `wts_tick` 一个计数器两处 `+=1` 复用做 %4/%5(实际 4s/10s);`is_locked_here()` 与主循环内联锁检测(128-133)重复。
- **D5** KingfisherPetApp.swift:340 `Process.launchPath` deprecated(SpriteLibrary.swift:201 已用 `executableURL`,风格不一)。
- **D6** 版本号漂移:tauri.conf.json 1.4.53(生效)vs Cargo.toml/package.json 1.0.0(僵尸);dispatch 构建产 conf 里的旧号。
- **D7** 死变量/死字段:poop.ts:10,55、crack.ts:10,47 的 `win` 从不读取;`poop-drop` 载荷 `scale` 字段(behavior.ts:386 发→poop.ts:111 传→poop.html 不消费)。
- **D8** kflog.rs:37-39 时间戳按 epoch 直算 = **UTC**,本机(UTC+8)日志时间差 8 小时,排障时间线对不上。

## 六、CI 与测试

- **E1** release.yml:151 `tagName: ${{ github.ref_name }}`:手动 dispatch(无 tag)时 ref_name 是分支名(如 main),tauri-action 会以分支名建 tag/release——与「tag 不重打」纪律冲突。workflow 明确支持 dispatch(:70-75 还写了 dispatch 读版本的逻辑),该路径是活的。建议 dispatch 加 `if: startsWith(github.ref, 'refs/tags/')` 门。【静态推演·未实测】
- **E2** release.yml:86 `codesign -s "KingfisherPet Dev" ... || codesign -s - ...` 签名失败**静默降级 ad-hoc**(用户拿到授权会失效的包,CI 无警告);且签名后无 `codesign --verify`。【已复核】
- **E3** run_tests.sh:43 段尾正则 `/TEST sleepwave/`(少个 k)永不匹配 → 「唤醒后屎重落」断言段无终点,后续场景日志全计入(潜伏假阴/假阳性)。另 :83 编译失败检测只 grep 行首 `^error`,其他失败形态漏过、拿旧二进制继续测(应判 swift build 退出码)。【已复核】
- **E4** lint.yml 无 `pull_request` 触发(push main 才跑,PR 不检查);且 paths 只含 `windows/**`——**Swift 端无任何 CI 编译检查**,错误要烧 tag 才暴露。【已复核·grep 验证】
- **E5** lint 的「禁 as any」按字面量拦,漏 `: any` 家族(main.ts:272 `Promise<any>`、:355 `any[]` 等同样绕过类型检查)。【已复核】

---

## 七、汇总与优先序

| 分级 | 数量 | 编号 |
|---|---|---|
| P0 生产级 | 3 | P0-1 CSP、P0-2 set-size、P0-3 Mac 勿扰死锁 |
| P1 功能 bug | 8 | A1-A8 |
| P2 健壮性 | 8 | B1-B8 |
| P3 死代码/漂移 | 8 | C1-C8 |
| P4 nit | 8 | D1-D8 |
| CI/测试 | 5 | E1-E5 |

**建议修复优先序**(若全采纳):
1. **P0-1/P0-2**(生产包的检查更新是坏的;dev 测不出,修完必须打包实测);
2. **P0-3**(用户侧唯一「只能重启」级故障);
3. **A1/A2/A5**(一行级、收益直接)→ **A7**(勿扰清理补全)→ **E3**(测试防线本身是坏的);
4. **A3/A4**(Windows 睡眠纪律移植缺口,CLAUDE.md 不变量)→ **A6**(多屏,发作难排查);
5. B 组按需 → C/D 顺手清 → E1/E2/E4 发版纪律。

## 八、给评审者的验证指引

1. **静态可验**(读代码对账,本文档已附行号与证据;基线 7e2337b 之后若代码有动,先重对行号):P0-1/P0-2、A1-A3、A5、A7、A8、B1-B8、C1-C8、D1-D8、E2-E5。
2. **需构造场景**:P0-3(勿扰中隐藏→退出全屏→再显示)、A4(锁屏+睡眠叠加)、A6(双屏不同高度)、B1(触发熔断)、B7(任务栏挪到左侧)、E1(dispatch 发版行为——建议先读 tauri-action 文档再下结论)。
3. **打包版专项**(dev 测不出的整类):P0-1 的 CSP、P0-2 的 capability——评审时请以 `npm run tauri build` 产物为准,dev 模式无效。
4. 欢迎推翻「未实测」条目——尤其 E1(tauri-action 对无 tag 的 tagName 的行为)与 A3(WebView2 遮挡节流对 setInterval 的实际影响),这两条只有文档级/静态证据。
5. 已知盲区:`tools/gen_sprites.py` 未逐行(离线资产工具,不进产物;两处 `json.dump` 内容均 ASCII,无 ensure_ascii 风险)。若评审认为必要可单独补一轮。
