# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

翡(KingfisherPet):一只住在你 Mac 菜单栏的翠鸟桌面宠物。纯 **Swift + AppKit**(无 Xcode 工程,SwiftPM 托管),无边框透明置顶窗口常驻后台。所有美术素材由 Python 脚本生成,不依赖外部图片。

仓库 `hizml/KingfisherPet`。**先读 `README.md`(功能与目录)和 `docs/DEV_NOTES.md`(深入架构与已知坑)**——本文件只补充跨文件才能看出来的「承重」知识与必须遵守的不变量。

## 常用命令

```bash
./build.sh                          # SwiftPM release 编译 → 组装 build/KingfisherPet.app → ad-hoc 签名 → 杀旧进程并启动(开发主循环)
swift build                         # 只编译不打包(快速看编译错误)
.venv/bin/python tools/gen_sprites.py   # 重新生成素材(改了 gen_sprites.py 才需要);首次:python3 -m venv .venv && .venv/bin/pip install pillow
```

**无测试套件、无 lint 配置**——验证靠人工观察 + 快照(见下)。没有"跑单个测试"的概念。

### 验证外观(关键坑)

`screencapture` 在本机被屏幕录制权限挡,看不到窗口截图。改了视觉后用:

```bash
KF_SNAPSHOT=1 .build/release/KingfisherPet   # 用 cacheDisplay 自渲染到 /tmp/kf_snapshot.png + 写坐标到 /tmp/kf_debug.log(不经屏幕录制权限)
KF_DEMO=1 .build/release/KingfisherPet       # 2.5s 后自动拉一坨屎,便于截图看下落/落地
```

入口在 `KingfisherPetApp.writeDebugSnapshot()`,受环境变量门控。**移动项目目录后若 SwiftPM 报 module cache 旧路径错**:`rm -rf .build` 再 `./build.sh`(缓存含绝对路径)。

## 架构大图

入口 `@main enum KingfisherPetApp` 手动建 `NSApplication` + `setActivationPolicy(.accessory)`(不进 Dock,只留菜单栏图标)。`AppDelegate` 装配所有子系统:`PetWindowController`(鸟) + 四个常驻覆盖层控制器 + 菜单栏 `NSStatusItem` + 设置窗口。

**五层窗口分置不同 `level`**(决定谁能超出屏幕、盖过谁):

| 内容 | level | 超屏 |
|---|---|---|
| 鸟 | `statusBar + 1`(26) | 最上,盖一切 |
| 裂纹 / zzz / 音符 / 太阳 | `statusBar`(25) | 可超屏,盖过 Dock/菜单栏 |
| 阴影 / 树枝 / 水花 / 屎 | `floating`(3) | 桌面层,不超 |
| 普通 App | `normal`(0) | — |

**三类覆盖层,生命周期不同**(改特效必读):
- **常驻**:鸟窗口、`ShadowController`、`BranchController`、`CrackController`——各自一个透明 click-through `NSWindow`,由 AppDelegate 持有。
- **短命**:`Effects.swift` 里的水花/音符/zzz/鸟屎——用 `Effect` 类包装,靠 `Effect.active` **静态数组**保活,`close(after:)` 到点 `dismiss()` 自撤。太阳硬上限同时 1 个(`sunEffectInstance`,防堆积卡死)。
- **鸟窗**:唯一的交互承载者,`isMovable=false`,所有移动都由 `Behavior` 的动画 timer 调 `setFrameOrigin` 驱动。

### `Behavior` 的代际(generation)取消——核心并发原语

`Behavior` 是状态机,`gen: Int` 是它的命脉:

- `beginAction()` 做 `gen &+= 1` 并停掉 think/zzz/poop timer。**任何**新动作、点击、拖拽、`callOver()` 都先 `beginAction()`。
- `hold(t){ done }`、`animateWindow/animateFlight/animateArc` 的 timer 回调都**捕获调用时的 `gen`**,回调里 `guard self.gen == g else { 作废 }`。代际一 bump,所有进行中的 hold/动画自动失效、不再推进。
- **含义**:写新动作必须用 `hold`/`animateWindow` 串阶段,不要用裸 `DispatchQueue.asyncAfter` 或独立 `Timer` 不挂代际——否则旧动作被抢占后还会推进,造成鬼影/位置错乱。
- `beginAction()` **故意不清** `onWindow`/`leavePerch`:原地静态动作(watch/sing/sun/sleep/peck/poop)停在窗口上时要继续踩在窗口、不出树枝;真正移动的动作(walk/fly/dart)自己调 `leavePerch()`。

### 主题系统(资源 fan-out)

资源按主题分目录打包:`Contents/Resources/Sprites/<theme>/{*.png, sprites.json, colors.json}`。切换主题时 `SpriteLibrary.reload(theme:)` 重载帧缓存,再通过 `observeThemeChanged { }` 广播给监听者(`PetView` 清帧名重画、`ShadowController`/`BranchController`/`ThemeColors` 重取贴图/取色)。**切换瞬时,运行时不重新生成图**。

特效颜色不走 sprites.json,走 **`colors.json`**(`ThemeColors.shared.color("poop_white", fallback:)`),这样屎/zzz/音符/太阳/水花/裂纹能跟主题走。

### 设置 fan-out

`Settings` 单例 → UserDefaults(`kingfisher.settings.*`)→ `NotificationCenter` 发 `didChangeNotification`(userInfo["key"] = 改的字段)。`AppDelegate.settingsChanged` 把声音/主题应用到 `SpriteLibrary`;活跃度/速度由 `Behavior`(`scheduleThink`/`think` 权重、`sp()` 时长缩放)和 `PetView.tick`(`animTime *= speed`)和 `Effects.sp()` 直接读 `Settings.shared`。

## 素材管线(`tools/gen_sprites.py` 是事实之源)

**几何绘制对所有主题一致**(`draw_kingfisher()`/`draw_egg()` 只通过调色板 `pal` 取色),风格差异靠**后处理器** `post_*()` 作用在 flat 成品帧上。所有主题共用同一份 `sprites.json` 序列(`sequences`/`fps`),只是帧内容不同。

- **加新主题**:① `gen_sprites.py` 在 `THEME_PALETTES`/`POSTPROCESSORS`/`THEME_NAMES` 各加一条 → ② `SpriteLibrary.themes` 加 `(id, 名字)` → ③ 重跑 gen_sprites → ④ `./build.sh`。
- **加新行为**:① gen_sprites 加帧 + 在 `sequences`/`fps` 加状态 → ② `Behavior` 加 `startXxx()`(参考 `startWalk`: `beginAction()` → `enter("xxx")` 切动画 → `animateWindow`/`animateFlight` 移动 → 完成回调回 `finish()` + `scheduleThink()`)→ ③ 要朝向就设 `view?.facingRight` → ④ 要菜单触发,在 `AppDelegate.configureStatusItem()` 加项 + `@objc` 方法。

## 必须遵守的不变量(踩过坑,违反会静默出 bug)

- **粒子层 `opacity` 必须 = 0**:CA 动画播完后图层会回弹到模型属性的初始位置,不置 0 就闪一下(鬼影)。`Effect` 里每个粒子层都显式设 `opacity = 0`。
- **`CALayer.contents` 去重用帧名字符串**,不要写 `contents as? CGImage`(Swift 报"对 CF 类型条件向下转换永远成功")。`PetView.applyFrame` 靠 `lastName` 去重避免每帧重设。
- **阴影无自身定时器**:`ShadowController.tick()` 只由 `Behavior` 在鸟移动/拖拽时调 `shadow?.updateNow()` 触发(零延迟)。给阴影加独立 timer 会引入合成差。
- **睡眠/唤醒/锁屏纪律**:`AppDelegate` 监听 `willSleepNotification`/`didWakeNotification`(`NSWorkspace`)+ `com.apple.screenIsLocked`/`screenIsUnlocked`(`DistributedNotificationCenter`)。入睡统一走 `Behavior.sleepForUserAbsence(systemSleep:)`:锁屏(`false`)用 `beginAction`+`startZzz` 自然睡(进程不挂起);系统睡眠(`true`)走 `suspend` 停所有 timer + 代际 bump(进程将挂起,防唤醒补发堆积卡死)。唤醒/解锁走 `wakeFromUserAbsence()`(赖床 2–4s 再 `finish`)。睡觉期间 `SpriteLibrary.mutedForSleep=true` 禁声。**睡眠期间不能有任何待处理 timer/asyncAfter**,否则唤醒密集补发堆出几十个特效卡死(反复修过的顽疾)。
- **多屏跟随**:鸟在哪个屏(`bird?.screen ?? NSScreen.main`),屎/裂纹/阴影跟哪个屏;`didChangeScreenParametersNotification` → 裂纹 `relocate()` + 鸟 `clampToCurrentScreen()`。拖拽起点屏单独记(`PetView.dragScreen`),拖拽 clamp 跟它,别用主屏。

## 易重犯的坑(历史修过 ≥2 次,改 Behavior/BranchController 前必读)

- **树枝显隐只用 `onWindow` 标志,绝不实时探测窗口**:`BranchController.tick` 的 `wantsBranch` 用 `beh.isResting() && !beh.onWindow && !onGround`,**不能**改成 `beh.isAirborne()`/`frontWindowAt`/`landingSpot` 实时查。实时探测会让"窗口拖过鸟脚下"时结果变化 → 树枝闪烁/消失;`onWindow` 只在主动停窗(`startPerchWindow`)/拖拽吸附时设 true,窗口移动不改它。**这条历史上修过 3 次(`ee2d2c0`/`290a611`/本次),别再改成实时探测。**
- **树枝必须起飞前预显,不能靠 tick 滞后检测**:所有"飞到某处落下"的路径(`startFly`/`callOver`/`diveFish`/`dart`)都要调 `perchBranchIfNeeded(at:)`(`→ branch.showAt` 在落点提前显树枝,鸟到了无缝接管)。`tick` 的 `eligibleAt + 0.3s` 只是兜底,不能当主要方式,否则"鸟落下后才冒树枝"。
- **悬空判断 `isPointAirborne` 用 `nearestSurface`**(脚附近最近的窗口上沿/Dock,上下都找)。不要用 `frontWindowAt`(2D 矩形包含会把"悬空在窗口前方"误判成"在窗口上",半空也不出树枝);也不要用 `landingSpot`(只找脚正下方,鸟踩窗台上沿时漏判悬空、冒树枝)。
- **停窗/吸附落点用 `clampPerch`,不要用通用 `clamp`**:通用 `clamp` 的 `maxY = visibleFrame.maxY - 鸟高` 会把停高窗口的鸟压进窗口内部;`clampPerch` 上界放宽到物理屏顶(鸟可盖菜单栏),脚精确踩窗台。落点会头超屏的过高窗口用 `wouldOvershootTop` 判定后直接飞走,别硬停。

## 性能与卡死红线(改 timer / 特效 / 窗口前必读)

桌面宠物常驻多个 60/30/20fps timer + 多个透明窗口,CPU 累积会拖垮整机。这几条是排查「睡眠/锁屏唤醒后整机卡死」得出的硬规矩:

- **锁屏(`screenIsLocked`)和系统睡眠(`willSleep`)都要 suspend 所有常驻 timer**——`PetView`(60fps)、`PoopController`(30fps)、`BranchController`(60fps)、`Behavior`(think/zzz/poop/perch)。**锁屏不是系统睡眠**(macOS 关屏默认走 `screenIsLocked`,进程不挂起),但锁屏时屏幕黑、timer 全跑 = 纯浪费 + 发烫,长时间会卡死。`screenLocked`/`screenUnlocked` 必须配对调用 `petView.suspendAnimation()`/`poopCtl.suspend()`/`branchCtl.suspend()` 和对应 resume,与 `systemWillSleep`/`systemDidWake` 对称。
- **`WindowTracker.frontWindowAt` / `CGWindowListCopyWindowInfo` 是全窗口枚举,贵——不能在每帧(60/30/20fps)回调里直接调**。栖窗遮挡(`checkPerch`)和屎遮挡(`Poop.sitting`)都用计数器(`perchOccludeFrame`/`occludeFrame`)降到每 10 帧一次;每帧只做单查 `frameOfWindow(id)`(按 id,便宜)。新增"每帧跑的逻辑"前,先想这一步有没有系统枚举。
- **凡会累积的对象必须有上限**:`poops`(屎,上限 8,超出移除最老)、`Effect.active`(短命特效,靠 close/dismiss 回收)、`CrackController.cracks`(上限 8)、`sunEffectInstance`(同时 1 个)。新建窗口/特效/屎前检查上限。
- **鸟隐藏(`fallAway`)必须停 timer**:`orderOut` 后调 `view?.suspendAnimation()` + `branch?.suspend()`,否则 PetView/Branch 60fps 空转;`hatchIn` 重新显示时 resume。
- **单例静态引用(`sunEffectInstance`)在 `clearAll`/`dismiss` 后必须置 nil**,否则已 orderOut 的空窗口对象常驻内存。
- **常驻 timer 的回调必须轻**:任何加入 `RunLoop.main.add(.common)` 的高频 timer,其回调里禁止同步长操作/系统枚举/锁;重活降频或挪到一次性触发。

## 坐标系

全程 NS 坐标(原点左下)。唯一例外:`PetView.isFlipped = true`,使 alpha 缓冲顶行 == 图像顶行,与 `hitTest` 点击穿透采样一致。`WindowTracker` 用 `screen.frame.height - y` 在 NS-y 与 CG-y(左上原点)间换算。鸟窗 160×160;`feetOffset=26` 是脚到窗口底的基准。

## 代码规范

遵循用户全局 CLAUDE.md(`~/.claude/CLAUDE.md`):中文注释、英文标识符、不用 emoji、函数职责单一、消除重复、命名语义化(布尔 `is/has/should`、函数动词+名词)。本仓代码已按此风格——新代码请读周围代码保持一致。
