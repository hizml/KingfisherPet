# 翡 · KingfisherPet 开发备忘

> 这份文件记录在本机之外也能续上的项目知识:构建、素材、验证、已知坑、架构、如何扩展。
> (随仓库走,换机器 clone 即可继续。)

## 环境

- macOS 13+(本机为 Apple Silicon / macOS 26)
- Swift 命令行工具(无需完整 Xcode,SwiftPM + AppKit 用 CommandLineTools 即可)
- Python 3 + Pillow(仅用于生成素材,仓库已带产物,可不装)

## 构建 / 运行

```bash
./build.sh          # SwiftPM release 编译 → 组装 build/KingfisherPet.app → ad-hoc 签名 → 启动
```

`build.sh` 干的事:
1. `swift build -c release` → `.build/release/KingfisherPet`
2. 组装 `.app`:
   - `Contents/MacOS`(可执行)
   - `Contents/Resources/Sprites/<theme>/`(每个主题一个子目录,各含 png + sprites.json)
   - `Contents/Resources/peep_*.wav`(4 种叫声)
   - `Contents/Resources/{zh-Hans,en}.lproj/Localizable.strings`(本地化)
   - `Contents/Info.plist`(`LSUIElement=true` 不占 Dock;`CFBundleLocalizations` 声明 zh-Hans/en)
   - `Contents/Resources/AppIcon.icns`(由 flat/idle_0 经 iconutil 生成)
3. `codesign -s - --force --deep`(ad-hoc)
4. `open`

手动只编译不打包:`swift build`

## 素材生成

```bash
python3 -m venv .venv && .venv/bin/pip install -i https://pypi.tuna.tsinghua.edu.cn/simple pillow
.venv/bin/python tools/gen_sprites.py
```

- 输出 `Resources/Sprites/<theme>/*.png`(各状态帧,256×256 透明,4× 超采样抗锯齿)——**每个主题一个子目录**
- 输出 `Resources/Sprites/<theme>/sprites.json`(序列与帧率,所有主题序列一致,只是帧内容不同)
- 输出 `Resources/Sprites/<theme>/{shadow,branch}.png`(阴影/树枝贴图,像素风做硬边、霓虹做发光)
- 输出 `Resources/peep_0..3.wav`(4 种叫声:短啾/长颤/低咕/兴奋,代码合成,不随主题)
- 每个主题输出一张 `contact.png` 检查图(不进包)

**主题架构**(`gen_sprites.py`):
- `BASE_PALETTE` / `THEME_PALETTES`:调色板(flat 用基础色,其余主题覆盖部分色)
- `draw_kingfisher()` / `draw_egg()`:几何绘制对所有主题一致,只通过 `pal`(调色板)取色
- 后处理器 `post_*()`:作用在 flat 成品帧上做风格转换
  - `clay`(粘土)、`pixel`(像素)、`neon`(霓虹)、`ink`(水墨)、`watercolor`(水彩)
- 主题清单见 `THEME_NAMES`(id + 中文名);加新主题 = 在 `THEME_PALETTES`/`POSTPROCESSORS` 各加一条

改美术 = 改 `tools/gen_sprites.py` 的 `draw_kingfisher()`、调色板或后处理器后重跑,再 `./build.sh`。
Swift 侧靠 `sprites.json` 驱动,帧名对上即可。

## 架构

```
KingfisherPetApp.swift   入口(@main) + AppDelegate + 菜单栏 NSStatusItem + 设置窗口托管
PetWindowController      透明置顶 borderless 窗口(level statusBar+1, canJoinAllSpaces)
PetView                  CALayer 逐帧动画;按像素 alpha 重写 hitTest 做点击穿透;鼠标拖拽(半空松手飞走)
Behavior                 状态机: idle/walk/fly/sleep/happy...,定时自主决策 + 移动窗口(代际取消)
SpriteLibrary            加载当前主题的 png + sprites.json(按子目录);切换主题 reload;多种叫声随机
Settings                 全局设置单例:活跃度/动画速度/声音/主题(UserDefaults + 通知)
SettingsWindowController 独立设置窗口:滑块/复选框/主题下拉,实时生效
WindowTracker            CGWindowList 找普通窗口上沿(停靠/落屎/遮挡检测),无状态
PoopController / CrackController / ShadowController / BranchController
                         各自一个常驻透明 click-through 覆盖层,跟随鸟所在屏
```

关键实现点:
- **透明置顶**:`NSWindow` borderless + `isOpaque=false` + `backgroundColor=.clear` + `level=statusBar+1`,无 Dock(`LSUIElement` + `setActivationPolicy(.accessory)`)。`collectionBehavior` 含 `canJoinAllSpaces`/`stationary`/`fullScreenAuxiliary`/`ignoresCycle`。
- **点击穿透**:每帧预计算 `[UInt8]` alpha(顶行在前);`PetView.hitTest(_:)` 把父坐标转本视图坐标采样,透明像素返回 `nil`,事件落到后面的 App。
- **逐帧**:60fps Timer 推进 `animTime`,`applyFrame()` 按 `sprites.json` 的序列+fps 选当前帧,赋给 `CALayer.contents`(按帧名去重避免重设)。`animTime` 累加受全局 `Settings.speed` 倍率影响。
- **转向**:`facingRight` → `spriteLayer.setAffineTransform(scaleX:-1)`,水平翻转。
- **主题系统**:资源按主题分目录(`Contents/Resources/Sprites/<theme>/`);`SpriteLibrary.reload(theme:)` 清空帧缓存重载,通过 `observeThemeChanged` 通知 PetView(清 lastName 重画)、Shadow/Branch(reloadTheme 重取贴图)。切换瞬时,无重新生成。
- **设置**:`Settings` 单例持久化到 UserDefaults(`kingfisher.settings.*`),变化发 `didChangeNotification`;AppDelegate 监听并应用到 SpriteLibrary(声音/主题)。活跃度影响 `scheduleThink` 间隔 + `think()` idle 权重;速度影响 `animTime`/`Behavior` 各 duration(`sp()`)/Poop 下落/Effects CA 时长。
- **多屏**:`WindowTracker`/`Poop`/`Crack` 用 `bird?.screen ?? NSScreen.main` 跟随鸟所在屏;`didChangeScreenParametersNotification` 监听插拔屏 → 裂纹 `relocate()` + 鸟 `clampToCurrentScreen()`。拖拽起点屏单独记(`dragScreen`),拖拽 clamp 跟随它。

状态机 `Behavior` 的状态(都对应 `sprites.json` 里的序列):idle / walk / fly / hover / dive / fly_fish / eat / sing / dart / watch / sun / sleep / happy / egg / dead。多阶段动作(如 `startFish`)用 `animateWindow(...){ done }` 的完成回调 + `hold(t){}` 串成阶段链。

特效(`Effects.swift`):水花 / 音符 / 鸟屎 / zzz 是**独立的短命透明 click-through 窗口**(`Effect` 类,靠 `Effect.active` 静态数组保活,播完 `orderOut` 自撤),因为宠物主窗口只有 160×160、装不下屏幕底的水花。俯冲捕鱼入水时在 `(targetX, minY+8)` 放水花;鸣唱时在鸟头上方放音符;拉屎从屁股掉白色鸟屎;打盹时 zzz 从鸟头往上飞(带描边)。**注意**:所有粒子层模型 `opacity` 必须 = 0,否则动画播完后图层回弹到初始位置闪现一下(鬼影 bug)。

两个**常驻**透明 click-through 覆盖层(30fps timer 读鸟窗口位置):
- `ShadowController`:屏幕底一条,**无自身定时器**,只在鸟移动/拖拽时由 Behavior 调 `updateNow()` 同步刷新 → 零延迟。固定 Dock 上边、正对鸟下方,鸟飞高变大变淡。
- `BranchController`:鸟停到屏幕上 40% 区域且歇脚(非拖拽/非停窗)时,脚下出现 `branch.png` 树枝。

**窗口层级(谁能超出屏幕)**:
| 内容 | level | 超屏 |
|---|---|---|
| 鸟 | statusBar+1 (26) | 最上,盖一切 |
| 裂纹 / zzz / 音符 | statusBar (25) | ✓ 可超屏,盖过 Dock/菜单栏 |
| 阴影 / 树枝 / 水花 / 屎 | floating (3) | 桌面层,不超 |
| 普通 App | normal (0) | — |
鸟永远 > 裂纹,保证鸟盖在裂纹上。

抛物线飞行:`Behavior.animateArc(to:duration:apexDy:done:)` 用 60fps Timer 沿二次贝塞尔采点 `setFrameOrigin`(窗口不能直接 CAKeyframe)。俯冲捕鱼:`startFish` 已在高位→直线俯冲,否则抛物线上顶再俯冲。

## 已知坑

- **`screencapture` 被屏幕录制权限挡**:`screencapture` 报 `could not create image from display`。验证窗口外观用快照:设环境变量 `KF_SNAPSHOT=1` 直接跑二进制,App 会在 `/tmp/kf_snapshot.png` 用 `cacheDisplay` 自渲染视图、并在 `/tmp/kf_debug.log` 写窗口/屏幕坐标。代码见 `KingfisherPetApp.writeDebugSnapshot`(受 `KF_SNAPSHOT` 门控)。
- **移动项目目录后 SwiftPM 报 module cache 旧路径错**:`rm -rf .build` 再 `./build.sh`。缓存里含绝对路径。
- **CALayer.contents 转 CGImage**:不要写 `contents as? CGImage`(Swift 会报"对 CoreFoundation 类型条件向下转换永远成功");改用帧名字符串比较去重。

## 如何加新行为

1. 在 `tools/gen_sprites.py` 加新帧(新状态序列),重跑生成 png + 更新 `sprites.json` 的 `sequences`/`fps`。
2. `Behavior` 里加状态分支:参考 `startWalk()`/`startFly()`——`enter("xxx")` 切动画,`animateWindow(to:duration:done:)` 移动窗口,完成后回到 `idle` 并 `scheduleThink()`。
3. 若需要移动方向,设 `view?.facingRight`。
4. 想让菜单能触发,在 `AppDelegate.configureStatusItem()` 加菜单项 + `@objc` 方法,调 `petController.behavior.xxx()`。

## 仓库

- 开源:github.com/hizml/KingfisherPet

## 发布策略(用户指令)

改完认为有必要打包时**直接自动打 tag**(推 `v*` 触发 release.yml 三端打包,产物进 draft)。
- 判定标准:用户可见的改动(功能/美术/行为修复)→ 打;纯文档/CI 调试 → 不打
- 版本:小改 patch(+0.0.1),新功能 minor(+0.1.0)
- CI 全绿后**停在 draft,用户确认后再发布**(仓库已公开,发布动作由用户拍板);CI 挂了先修复重打,不发坏的

## 验证与措辞纪律

见 docs/TESTING.md。要点:改完汇报必须注明验证方式(编译/场景/快照/仅推理四档),
"仅推理"不得表述为"已修复/没问题";发版前跑 `./tools/run_tests.sh` + 手动清单。

## API 使用纪律(用户指令:幽灵 API 事故后立,以后不许再犯)

2026-08-20 事故:Windows 端把 `currentMonitor/availableMonitors` 当 Window 方法调用
(实际是模块级函数),`as any` 绕过类型检查 + catch 静默吞错,导致缩放系数
自启动起永远=1,200% 缩放屏全链坐标错位,连蒙四个版本才靠诊断数据破案。

1. **禁止 `as any`**(CI lint.yml 机器强制,grep 到即红)。API 不确定存在时,
   写正确类型让 TS 检查;类型对不上 = 大概率调错了,去查装的包而不是 cast 绕过
2. **API 以装的包为准,不以记忆/文档为准**:核实去读
   `windows/node_modules/@tauri-apps/api/` 的实际实现(读完整个文件再下结论,
   WebviewWindow 的方法混入在文件末尾 applyMixins,读一半会冤枉好人)
3. **catch 不许全静默**:承载型失败(舞台窗/坐标/IPC)用 `src/log.ts` 的
   `warnOnce` 留痕(每 key 只报第一次);热路径轮询可静默但首次异常要能被发现
4. **修 bug 先铺可观测性**:连修两轮未果必须停下加诊断/日志拿地面真值,
   禁止第三轮继续盲改(本轮"诊断信息"功能就是这个教训的产物)
5. Rust 侧 cfg(windows) 代码必须过 windows target 的 cargo check
   (本地 `cargo check --target x86_64-pc-windows-gnu`,CI lint.yml 同款)

