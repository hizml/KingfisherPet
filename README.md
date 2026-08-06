# 翡 · KingfisherPet

一只住在你 Mac 菜单栏的翠鸟桌面宠物。原生 **Swift + AppKit**,无边框透明置顶窗口,常驻后台、不占 Dock、点击穿透。

美术素材全部由脚本(`tools/gen_sprites.py`)生成,不依赖任何外部图片。

## 预览

素材位于 `Resources/Sprites/`,由 `tools/gen_sprites.py` 用 Pillow 生成(扁平卡通风翠鸟:橙腹 / 青背青头 / 白颊 / 长黑喙)。

## 它能做什么

**自主行为(全自动)**
- 待机:轻微呼吸 + 眨眼
- 每 3.5–7 秒随机抽取:走动 / 挪窝飞行 / **俯冲捕鱼** / 鸣唱 / 低空快飞掠过 / 栖枝守候探头 / 日光浴 / 打盹
- **俯冲捕鱼**:抛物线飞到屏幕顶 → 悬停瞄准 → 急速俯冲到屏幕底"水线" → 溅起水花 → 叼鱼飞回栖处 → 仰头吞掉;已在顶端则直线俯冲
- 吃完过会儿会拉一坨白色鸟屎;飞行途中偶尔空中排泄
- **太阳驱动的地面阴影**:按系统时间算太阳方位(右升左落),影子方向/长短随时间变;鸟飞高时影子变大变淡、留在地面,不跟着飞
- 停到屏幕高处歇脚时,脚下会出现一根树枝
- 打盹时头顶飘起带描边的 zzz
- 走和飞自动转向

**交互**
- 点击 → 啾一声 + 心眼害羞反应
- 拖拽 → 移动位置
- 透明区域点击穿透,不挡后面 App

**菜单栏控制(右上角翠鸟图标)**
- 召唤过来 / 去抓条鱼 / 唱一个 / 显示·隐藏 / 啾鸣声开关 / 开机自启 / 关于 / 退出
- 显示 = 破壳而出(整蛋→裂纹→探头);隐藏 = 死掉(✕眼翻肚)从天上掉出屏幕
- 记住上次位置与声音设置;可选开机自启

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
├── tools/gen_sprites.py           # 生成 sprite png / sprites.json / peep.wav
├── Resources/
│   ├── Sprites/*.png              # 各状态帧
│   ├── Sprites/sprites.json       # 序列与帧率
│   └── peep.wav                   # 啾鸣音效
└── Sources/KingfisherPet/
    ├── KingfisherPetApp.swift     # 入口 + AppDelegate + 菜单栏
    ├── PetWindowController.swift  # 透明置顶窗口
    ├── PetView.swift              # 逐帧动画 + alpha 命中穿透 + 拖拽
    ├── Behavior.swift             # 状态机:idle/walk/fly/sleep/happy
    └── SpriteLibrary.swift        # 加载 png/json + peep
```

## 技术要点

- **无边框透明置顶窗口**:`NSWindow` borderless + `isOpaque=false` + `backgroundColor=.clear` + `level=.floating`,并可加入所有 Space。
- **按像素点击穿透**:对每帧预计算 alpha 缓冲,重写 `hitTest(_:)`,透明像素返回 nil,事件落到后面的 App。
- **逐帧动画**:CALayer `contents` 按 `sprites.json` 的序列与帧率切换。
- **不占 Dock**:`LSUIElement=true` + `setActivationPolicy(.accessory)`,仅留菜单栏图标。

## License

MIT
