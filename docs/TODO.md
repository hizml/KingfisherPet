# TODO · 翡 KingfisherPet

## 皮肤方案
- [x] **主题系统**:重构 `tools/gen_sprites.py` 为「调色板 + 后处理器」架构,
      几何绘制对所有主题一致,只换色 + 风格化后处理
- [x] **扁平卡通**(默认,原版)
- [x] **粘土软陶**:柔和内高光 + 右下投影 + 边缘减淡
- [x] **像素风**:降采样硬边 + 限定色板量化
- [x] **霓虹**:深底 + 青橙发光描边 + 外发光
- [x] **水墨国风**:灰度阈值黑墨 + 喙/腹一抹橙保留
- [x] **水彩手绘**:轻渗色 + 纸纹 + 水痕
- [x] 主题切换:运行时从设置面板切换,预生成资源按主题子目录打包(`Resources/Sprites/<theme>/`),
      切换瞬时(只换 bundle 内预制资源,无重新生成)

## 成品化
- [x] LICENSE 文件
- [x] 记住上次位置 + 声音开关(UserDefaults)
- [x] 开机自启(SMAppService,菜单可切换)
- [x] **设置面板**:活跃度(行为触发频率)、动画速度、声音、主题——独立窗口
      (`Settings.swift` + `SettingsWindowController`)
- [ ] **签名 + 公证**:现在是 ad-hoc 签名,只能本机跑;发给别人需 Developer ID + notarize,
      或当源码发(需外部证书,代码侧已就绪)

## 健壮性
- [x] **动作抢占/并发触发安全**:`Behavior.gen` 代际机制 + `hold`/timer 守卫,
      拖动/新动作 bump 代际,进行中的动画链自动作废
- [x] **多屏 / 外接屏**:`WindowTracker`/`Poop`/`Crack` 跟随鸟所在屏(`bird.screen`),
      `didChangeScreenParametersNotification` 监听插拔屏 → 裂纹重定位 + 鸟钳回当前屏
- [x] **全屏 App / Stage Manager**:`collectionBehavior` 加 `.ignoresCycle`,
      保留 `.canJoinAllSpaces` / `.stationary` / `.fullScreenAuxiliary`
- [ ] **耗电 / 性能 profiling**:常驻 3 个 30/60fps 定时器 + 特效窗口,需测持续占用
- [ ] 动作中拖拽的冲突处理(代际机制已覆盖大部分,边缘 case 待验)

## 内容扩展
- [x] 多种叫声(4 种:短啾 / 长颤 / 低咕 / 兴奋,`playPeep()` 随机选)
- [ ] 更多栖息姿态/随机事件(下雨躲雨、觅食回巢等)
- [ ] 与系统联动(如接电源/日历/天气,影响行为)

## 体验
- [x] 无障碍(AX)标签:菜单栏 button、PetView、设置控件均有 accessibilityLabel
- [x] 本地化(中/英):`zh-Hans` / `en` Localizable.strings,菜单/设置/关于文案走
      `NSLocalizedString`
