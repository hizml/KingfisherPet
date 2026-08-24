# 翡 · KingfisherPet

[中文](#中文) · [English](#english)

<a id="中文"></a>

一只住在你 Mac 菜单栏的翠鸟桌面宠物。原生 **Swift + AppKit**,无边框透明置顶窗口,常驻后台、不占 Dock、点击穿透。

美术素材全部由脚本(`tools/gen_sprites.py`)生成,不依赖任何外部图片。

## 灵感来源

2018 年,同事给我分享了一只小鸟——Windows 版的小 EXE,不到 1 MB,
名字叫 **尘.exe**。应该是日文软件,名字到底是什么意思,我看不懂日文,
至今也没弄明白。它就躺在我的微信收藏里,一直没删。

工作里无聊的时光,多半是它陪着熬过去的。无聊的时候看它蹦跶两下,
心情总会好一点。

后来想再养一只,发现它没有 Mac 版。于是干脆以它为灵感,重新构建一份——
Mac 原生 Swift + Windows Tauri 双平台,行为照着当年的它比着做,再加点新花样。
这不是复刻,是给老朋友的一封情书。

现在 AI 来临了,各种开发的上手难度都低了很多——**人人都可以构建起自己想要的作品**。
这个项目本身就是一份证明:美术脚本、双平台行为对齐、勿扰模式里那些
深到辅助功能和私有框架的坑,大半代码是与 AI 结对趟出来的。
你心里的那个"尘",也值得被做出来。

## 下载安装

前往 [Releases](https://github.com/hizml/KingfisherPet/releases/latest) 获取最新安装包:

| 平台 | 文件 |
|---|---|
| macOS(原生版,推荐) | `KingfisherPet-mac-native.zip`(解压即用)· [直接下载](https://github.com/hizml/KingfisherPet/releases/latest/download/KingfisherPet-mac-native.zip) |
| macOS(Tauri 版) | `.dmg` / `.app.tar.gz` |
| Windows | `x64-setup.exe`(NSIS,中/英可选)或 `zh-CN.msi` / `en-US.msi` |

> **签名**:本地与 CI 用同一张自签证书(非 Apple Developer ID)——首次运行若提示"无法验证开发者",右键 App → 打开;Windows SmartScreen 选"仍要运行"。签名固定意味着辅助功能授权一次、升级不失效。
>
> **辅助功能授权(Mac 可选)**:勿扰模式(全屏看片鸟自动隐身)需要;未授权时鸟会弹窗引导,一键直达系统设置。不给也能用,只是没有勿扰。


## 预览

素材位于 `Resources/Sprites/<theme>/`,由 `tools/gen_sprites.py` 用 Pillow 生成。
**6 种主题**:扁平卡通(默认)/ 粘土软陶 / 像素风 / 霓虹 / 水墨国风 / 水彩手绘——
几何绘制一致,靠调色板 + 后处理器换风格,从设置面板实时切换。

## 它能做什么

**自主行为(全自动)**
- 待机:轻微呼吸 + 眨眼
- 每 3.5–7 秒随机抽取:走动 / 挪窝飞行 / **俯冲捕鱼** / 鸣唱 / 低空快飞掠过 / 栖枝守候探头 / 日光浴 / 打盹
- **俯冲捕鱼**:抛物线飞到屏幕顶 → 悬停瞄准 → 急速俯冲到屏幕底"水线" → 溅起水花 → 叼鱼飞回栖处 → 仰头吞掉;已在顶端则直线俯冲
- 吃完过会儿会拉一坨白色鸟屎;飞行途中偶尔空中排泄
- **地面阴影**:固定在 Dock 上边、正对鸟下方(鸟飞高时变大变淡、留在地面,不跟着飞);移动走线性、同步刷新,不延迟
- 停到屏幕高处歇脚时,脚下会出现一根树枝
- 打盹时头顶飘起带描边的 zzz(可超出屏幕顶)
- **啄屏幕**:连啄几次,随机把屏幕啄裂(裂纹以鸟嘴尖为中心放射);菜单"修复屏幕"可清
- **停到窗口上**:飞到最前面那个窗口的上沿歇脚
- 走和飞自动转向
- 叫声有 4 种(短啾 / 长颤 / 低咕 / 兴奋),每次随机

**勿扰模式(全自动)**
- **全屏看片/游戏**:检测到全屏应用,鸟带着树枝、鸟屎、裂纹一起消失,绝不盖视频;退出全屏按层级原样恢复(Mac 用辅助功能的窗口属性 + pid 直连判定;Windows 比对前台窗口与屏幕矩形)
- **系统在放音**:听歌/看片时鸟不叫——想叫的那一刻先查一次系统播放状态,在播就吞掉这声(Mac 查 Now Playing;Windows 查音频输出峰值),放完自动恢复
- 鸟隐藏/勿扰期间,菜单动作一律不响应(不会对着空屏唱歌)

**交互**
- 点击 → 啾一声 + 心眼害羞反应
- 拖拽 → 移动位置;半空松手会自己飞走落下;靠近窗口上沿 / Dock(±70px)松手会精准吸附
- 透明区域点击穿透,不挡后面 App
- 支持多屏 / 外接屏:鸟跨屏移动,屎/裂纹/阴影跟随鸟所在屏

**菜单栏控制(右上角翠鸟图标)**
- 召唤过来 / 去抓条鱼 / 唱一个 / 停到窗口上 / 啄一下 / 显示·隐藏 / 啾鸣声开关 / 开机自启 / 修复屏幕 / **设置…** / 语言(跟随系统 / 中文 / English)/ 关于 / 退出
- 显示 = 破壳而出(整蛋→裂纹→探头);隐藏 = 死掉(✕眼翻肚)从天上掉出屏幕
- 记住上次位置与声音设置;可选开机自启

**设置面板(菜单 → 设置…)**
- 主题:扁平 / 粘土 / 像素 / 霓虹 / 水墨 / 水彩(实时切换)
- 活跃度:低 / 中 / 高(行为触发频率与 idle 占比)
- 动画速度:0.5×–1.5×
- 啾鸣声开关

## 构建

需要 macOS 13+ 与 Swift 命令行工具。

```bash
# 1. 生成素材(可选,仓库已带产物)
python3 -m venv .venv && .venv/bin/pip install pillow
.venv/bin/python tools/gen_sprites.py

# 2. 打包并启动
./build.sh
```

产物:`build/KingfisherPet.app`,直接双击或 `open` 即可。签名:优先用钥匙串里的"KingfisherPet Dev"自签证书(签名固定,辅助功能授权不随重打包失效),没有则回退 ad-hoc。

## 目录结构

```
KingfisherPet/
├── Package.swift                  # SwiftPM
├── build.sh                       # 编译 + 打包 .app + 启动
├── tools/gen_sprites.py           # 生成 6 主题 sprite / sprites.json / 4 种 peep 音效
├── Resources/
│   ├── Sprites/<theme>/*.png      # 各主题各状态帧(6 个子目录)
│   ├── Sprites/<theme>/sprites.json
│   ├── peep_0..3.wav              # 4 种啾鸣音效
│   ├── zh-Hans.lproj/             # 中文本地化
│   └── en.lproj/                  # 英文本地化
└── Sources/KingfisherPet/
    ├── KingfisherPetApp.swift     # 入口 + AppDelegate + 菜单栏 + 设置窗口托管
    ├── PetWindowController.swift  # 透明置顶窗口
    ├── PetView.swift              # 逐帧动画 + alpha 命中穿透 + 拖拽
    ├── Behavior.swift             # 状态机: idle/walk/fly/sleep/happy...(代际取消)
    ├── SpriteLibrary.swift        # 按主题加载 png/json + 多种叫声 + 主题切换
    ├── Settings.swift             # 设置单例(activity/speed/sound/theme)+ 设置窗口
    ├── WindowTracker.swift        # CGWindowList 找普通窗口上沿
    ├── Effects.swift              # 水花/音符/zzz/太阳 短命特效
    ├── ShadowController.swift     # 地面阴影(随鸟移动同步)
    ├── BranchController.swift     # 树枝(高处停靠)
    ├── PoopController.swift       # 鸟屎物理(下落/落地/消失)
    └── CrackController.swift      # 啄屏裂纹(全屏覆盖)
```

## 技术要点

- **无边框透明置顶窗口**:`NSWindow` borderless + `isOpaque=false` + `backgroundColor=.clear` + `level=statusBar+1`,可加入所有 Space、忽略窗口循环。
- **按像素点击穿透**:对每帧预计算 alpha 缓冲,重写 `hitTest(_:)`,透明像素返回 nil,事件落到后面的 App。
- **逐帧动画**:CALayer `contents` 按 `sprites.json` 的序列与帧率切换;`animTime` 受全局动画速度倍率影响。
- **主题系统**:资源按主题分目录打包,切换时 `SpriteLibrary.reload(theme:)` 重载帧缓存并通知 PetView/Shadow/Branch 重取贴图——瞬时,无运行时生成。
- **设置**:`Settings` 单例持久化到 UserDefaults,变化发通知;活跃度影响思考节奏、速度影响所有动画时长。
- **不占 Dock**:`LSUIElement=true` + `setActivationPolicy(.accessory)`,仅留菜单栏图标。
- **多屏**:窗口/屎/裂纹跟随鸟所在屏,`didChangeScreenParametersNotification` 监听插拔屏自动钳位。
- **全屏检测**:NSWorkspace 取前台 pid 后 `AXUIElementCreateApplication` 直连查窗口(原生全屏属性 + 盖屏几何双判定)。不走 systemWide 的 `focusedApplication`——它对 Chromium 系(Edge/Chrome/Electron)恒返回空值,原生 App 却正常,是个伪装成授权问题的系统坑。
- **放音检测**:GUI 进程内 MediaRemote(macOS 15.4+)拿不到全局播放状态,由无身份子进程(osascript)代查;只在鸟想叫的那一刻查一次,零轮询。

## License

MIT

---

---

<a id="english"></a>

# Fei · KingfisherPet (English)

A kingfisher desktop pet living in your Mac's menu bar. Native **Swift + AppKit**: borderless, transparent, always-on-top window; runs in the background, no Dock icon, click-through.

All artwork is generated by script (`tools/gen_sprites.py`) — no external images.

## Inspiration

Back in 2018, a coworker shared a tiny bird with me — a little Windows EXE, under 1 MB,
named **尘.exe ("Dust.exe")**. It's a Japanese program, I believe; what the name
actually means, I never figured out — I can't read Japanese. It still sits in my
WeChat Favorites, never deleted.

It kept me company through many dull hours at work. Watching it hop around
always lifted my mood a little.

Years later I wanted to keep one again, only to find it never had a Mac version.
So I rebuilt it from scratch as a tribute — native Swift on macOS, Tauri on Windows,
its behaviors faithfully mirrored from the original, plus a few new tricks.
This is not a port. It's a love letter to an old friend.

AI has now arrived, and the barrier to building things has dropped enormously —
**anyone can create the work they imagine**. This project itself is proof:
the art pipeline, the cross-platform behavior parity, the DND mode that dug
through accessibility APIs and private frameworks — most of it was pair-written with AI.
Whatever your own "Dust" is, it deserves to be built too.

## Download

Grab the latest from [Releases](https://github.com/hizml/KingfisherPet/releases/latest):

| Platform | File |
|---|---|
| macOS (native, recommended) | `KingfisherPet-mac-native.zip` (unzip & run) · [direct link](https://github.com/hizml/KingfisherPet/releases/latest/download/KingfisherPet-mac-native.zip) |
| macOS (Tauri) | `.dmg` / `.app.tar.gz` |
| Windows | `x64-setup.exe` (NSIS, zh/en selectable) or `zh-CN.msi` / `en-US.msi` |

> **Signing**: local and CI builds share one self-signed certificate (not an Apple Developer ID) — on macOS right-click → Open on first run; on Windows SmartScreen "More info → Run anyway". The signature is stable, so a one-time Accessibility grant survives upgrades.
>
> **Accessibility (optional, macOS)**: the DND mode (auto-hide during fullscreen video) needs it; if missing, the bird pops a dialog with a shortcut to System Settings. Everything else works without it.


## Preview

Assets live in `Resources/Sprites/<theme>/`, generated by `tools/gen_sprites.py` (Pillow).
**6 themes**: Flat (default) / Clay / Pixel / Neon / Ink / Watercolor — same geometry,
different palette + post-processing, switchable live from the settings panel.

## What It Does

**Autonomous behaviors (all automatic)**
- Idle: gentle breathing + blinking
- Every 3.5–7s picks one: walking / relocating flights / **diving to catch fish** (arc to top → hover → dive → splash → fly back with fish → swallow) / singing / low darting runs / perching & watching / sunbathing / napping
- Poops after eating (physics: falls and lands on window tops or the Dock, re-falls when its window moves away); occasionally mid-air
- **Ground shadow**: pinned above the Dock, right under the bird (grows & fades with height, stays on the ground)
- A branch appears under its feet when it rests high — the branch always arrives *before* the bird
- Outlined zzz bubbles while napping
- **Screen pecking**: pecks in bursts, may crack the screen (radial cracks from the beak); "Repair Screen" in the menu clears them
- **Perches on windows**: flies to the top edge of the frontmost window; follows the window; flies off when it's gone
- Auto-turns when walking/flying
- 4 chirp variants (short/long-trill/low/excited), random each time

**Do-not-disturb (all automatic)**
- **Fullscreen video/games**: on detecting a fullscreen app, the bird vanishes together with its branch, poops and screen cracks — nothing floats over your video; everything is restored by layer on exit. (macOS: AX window attribute + pid-direct lookup; Windows: foreground window vs. monitor rect)
- **While audio is playing**: no chirping — at the moment it wants to sing, it checks the system playing state once and swallows that chirp if something is playing (macOS: Now Playing; Windows: audio output peak). Resumes when quiet.
- While hidden / in DND, menu actions are ignored (no singing to an empty screen)

**Interactions**
- Click → chirp + shy heart-eyes
- Drag to move; release mid-air and it flies off; drop near a window top / the Dock (±70px) and it snaps on precisely
- Fully click-through on transparent pixels — never blocks apps behind it
- Multi-display: poops/cracks/effects follow the bird's screen

**Menu bar control (kingfisher icon, top-right)**
- Call Over / Catch a Fish / Sing / Perch on a Window / Peck / Show·Hide / Sound / Launch at Login / Repair Screen / **Settings…** / Language / About / Quit
- Show = hatch from an egg; Hide = plays dead and falls off-screen
- Remembers last position & sound; optional launch-at-login

**Settings panel (menu → Settings…)**
- Theme: Flat / Clay / Pixel / Neon / Ink / Watercolor (live)
- Activity: low / mid / high (behavior frequency)
- Animation speed: 0.5×–1.5×
- Sound on/off

**Bilingual** (中文 / English): follows system language by default; switch anytime from the menu.

## Build (macOS 13+)

```bash
# 1. Generate assets (optional, repo ships with them)
python3 -m venv .venv && .venv/bin/pip install pillow
.venv/bin/python tools/gen_sprites.py

# 2. Package & launch
./build.sh
```

Output: `build/KingfisherPet.app` — double-click or `open`. Signed with a stable self-signed identity when present (falls back to ad-hoc).

## Windows

A Tauri 2 port lives in `windows/`: same behaviors (walking/fishing/sleeping/poop physics/
cracks/themes/tray with checkable submenus, language switch, lock-screen detection,
plus DND: fullscreen-app hide & audio-playing mute). Build with `cd windows && npm install && npm run tauri build`.

## Robustness

- Sleep/wake handled end-to-end: timers suspended before sleep, maintenance (DarkWake) events ignored, wake is gentle (3s delay + lie-in)
- Window-leak root-caused & fixed; watchdog with circuit breaker (auto-reset / self-relaunch)
- Multi-display: overlays follow the bird's screen; display hot-plug auto-clamps

## License

MIT
