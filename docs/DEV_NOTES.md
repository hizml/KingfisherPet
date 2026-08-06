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
2. 组装 `.app`:`Contents/MacOS`(可执行)、`Contents/Resources`(png + sprites.json + peep.wav 铺平)、`Contents/Info.plist`(`LSUIElement=true`,不占 Dock)、`Contents/Resources/AppIcon.icns`(由 idle_0 经 iconutil 生成)
3. `codesign -s - --force --deep`(ad-hoc)
4. `open`

手动只编译不打包:`swift build`

## 素材生成

```bash
python3 -m venv .venv && .venv/bin/pip install -i https://pypi.tuna.tsinghua.edu.cn/simple pillow
.venv/bin/python tools/gen_sprites.py
```

- 输出 `Resources/Sprites/*.png`(各状态帧,256×256 透明,4× 超采样抗锯齿)
- 输出 `Resources/Sprites/sprites.json`(序列与帧率)
- 输出 `Resources/peep.wav`(代码合成的啾鸣,频率上扫 + 包络)

改美术 = 改 `tools/gen_sprites.py` 的 `draw_kingfisher()` 和各状态帧参数后重跑,再 `./build.sh`。Swift 侧靠 `sprites.json` 驱动,帧名对上即可。

## 架构

```
KingfisherPetApp.swift   入口(@main) + AppDelegate + 菜单栏 NSStatusItem
PetWindowController      透明置顶 borderless 窗口(level .floating, canJoinAllSpaces)
PetView                  CALayer 逐帧动画;按像素 alpha 重写 hitTest 做点击穿透;鼠标拖拽
Behavior                 状态机: idle / walk / fly / sleep / happy,定时自主决策 + 移动窗口
SpriteLibrary            启动加载所有 png + sprites.json;预计算每帧 alpha 缓冲;AVAudioPlayer 放 peep
```

关键实现点:
- **透明置顶**:`NSWindow` borderless + `isOpaque=false` + `backgroundColor=.clear` + `level=.floating`,无 Dock(`LSUIElement` + `setActivationPolicy(.accessory)`)。
- **点击穿透**:每帧预计算 `[UInt8]` alpha(顶行在前);`PetView.hitTest(_:)` 把父坐标转本视图坐标采样,透明像素返回 `nil`,事件落到后面的 App。
- **逐帧**:60fps Timer 推进 `animTime`,`applyFrame()` 按 `sprites.json` 的序列+fps 选当前帧,赋给 `CALayer.contents`(按帧名去重避免重设)。
- **转向**:`facingRight` → `spriteLayer.setAffineTransform(scaleX:-1)`,水平翻转。

状态机 `Behavior` 的状态(都对应 `sprites.json` 里的序列):idle / walk / fly / hover / dive / fly_fish / eat / sing / dart / watch / sun / sleep / happy / egg / dead。多阶段动作(如 `startFish`)用 `animateWindow(...){ done }` 的完成回调 + `hold(t){}` 串成阶段链。

特效(`Effects.swift`):水花 / 音符 / 鸟屎 / zzz 是**独立的短命透明 click-through 窗口**(`Effect` 类,靠 `Effect.active` 静态数组保活,播完 `orderOut` 自撤),因为宠物主窗口只有 160×160、装不下屏幕底的水花。俯冲捕鱼入水时在 `(targetX, minY+8)` 放水花;鸣唱时在鸟头上方放音符;拉屎从屁股掉白色鸟屎;打盹时 zzz 从鸟头往上飞(带描边)。**注意**:所有粒子层模型 `opacity` 必须 = 0,否则动画播完后图层回弹到初始位置闪现一下(鬼影 bug)。

两个**常驻**透明 click-through 覆盖层(30fps timer 读鸟窗口位置):
- `ShadowController`:屏幕底一条,按系统时间算太阳方位(右升左落)驱动一坨 `shadow.png` 柔和阴影;鸟飞高 → 影子变大变淡留地面。
- `BranchController`:鸟停到屏幕上 40% 区域且处于歇脚状态时,脚下出现 `branch.png` 树枝。

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

- 私有:github.com/hizml/KingfisherPet
- `gh` 已认证 `hizml`
