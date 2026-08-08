# 翡 · KingfisherPet

一只住在你 Mac 菜单栏的翠鸟桌面宠物。原生 **Swift + AppKit**,无边框透明置顶窗口,常驻后台、不占 Dock、点击穿透。

美术素材全部由脚本(`tools/gen_sprites.py`)生成,不依赖任何外部图片。

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

**交互**
- 点击 → 啾一声 + 心眼害羞反应
- 拖拽 → 移动位置;半空松手会自己飞走落下
- 透明区域点击穿透,不挡后面 App
- 支持多屏 / 外接屏:鸟跨屏移动,屎/裂纹/阴影跟随鸟所在屏

**菜单栏控制(右上角翠鸟图标)**
- 召唤过来 / 去抓条鱼 / 唱一个 / 停到窗口上 / 啄一下 / 显示·隐藏 / 啾鸣声开关 / 开机自启 / 修复屏幕 / **设置…** / 关于 / 退出
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

产物:`build/KingfisherPet.app`,直接双击或 `open` 即可。已 ad-hoc 签名。

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

## License

MIT
