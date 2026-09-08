# v1.5.0 batch1 计划 · 天气批（昼夜节律 + 天气联动 + 性能背书）

> 2026-09-08 落盘。规划方向 2026-08-27 已定（四梯队），细节一直只在会话里，
> 本文件为既定的"开工首动作"。前置批（review 修复）已由双会话清零，v1.4.62 停 draft 等发布。

## 定位与前置

- 本批 = 四梯队「2 活气」首批，目标：鸟对时间 和 天气 有反应，并给出性能数据背书。
- **前置**：v1.4.62 发版（老板确认 + Win 打包版点一次「检查更新」实测 CSP/set-size）。
  建议发完再开工，保持版本边界干净；若并行，注意 tag 纪律（tag 推过即固定）。
- ⚠️ 开工首日先核对基线：AppDelegate 拆分重构（DndMonitor/UpdateService/WatchdogService
  拆出）如在途，先等其收口再动 `Behavior.swift` / `Settings.swift`，避免冲突。

## A · 昼夜节律（纯本地，零网络零权限，先做）

本地小时 → 分段系数，注入双端 think() 的动作桶。

**分段（初版参数，可调）**：

| 时段 | 系数 |
|---|---|
| 深夜 0–6 | 活跃整体 ×0.35，sleep 桶放大，sing/fish/dart ≈ 0 |
| 清晨 6–9 | sing ×1.5（晨鸣） |
| 白天 9–17 | 基准 ×1.0 |
| 黄昏 17–22 | ×0.85，sun 略升 |
| 夜 22–24 | ×0.5 |

**实现要点**：
- 双端 think() 都已归一化成「idleBand + walk + 九动作带」结构（Mac `Behavior.swift`
  bounds 累积数组 / Win `behavior.ts` 带链）。昼夜因子直接**乘在各桶宽上再累积**，
  与现有 k 公式相乘（k = (100−walk−6)/62 一支），不重写权重架构。
- sleep 目前是固定兜底桶（6），深夜版改为显式桶并放大——注意别破坏
  "超 walk+62 进 sleep" 的兜底语义。

**涉及文件**：`Sources/KingfisherPet/Behavior.swift`、`windows/src/behavior.ts`

**验证**：加注入钩子（Mac 环境变量 `KF_HOUR_OVERRIDE` / Win dev 参数），扫 24 小时
分段断言权重带单调性；双端各场景过一遍（深夜活跃度降、清晨有晨鸣）。

## B · 天气联动（网络 + 设置 UI，需老板过目文案）

**数据链（双数据源，老板 2026-09-08 拍板要留和风口子）**：
- **源 1（默认）Open-Meteo**：免 key。current：
  `api.open-meteo.com/v1/forecast?...&current=weather_code`；城市解析走自家 geocoding
  （`geocoding-api.open-meteo.com/v1/search?name=`）。
- **源 2 和风天气**：用户在设置里填 API Key（必填）+ API Host（选填，默认
  `devapi.qweather.com`，**以和风控制台分配的专属 Host 为准**——新账号多为
  `xxx.re.qweather.com` 形式）。城市解析走和风 GeoAPI lookup
  （`geoapi.qweather.com/v2/city/lookup`，中文城市名友好）。
- 定位：默认 ipapi.co IP 粗定位拿 lat/lon；手填城市则按当前源走各自 geocoding 覆盖。
- **归一化层**：两个 provider 对外只吐统一枚举 `{sunny, overcast, rain, snow}`——
  Open-Meteo WMO 码 0–3→晴/阴、51–67→雨、71–77→雪；和风码 100–103→晴、
  104/雾霾类→阴、300–399→雨、400–499→雪。权重逻辑只认枚举，与源无关。
- 刷新：30 分钟一次；**失败静默降级 = 无系数**，不弹窗、不重试轰炸，等下个周期
  自然重试。key 无效（和风 401/402）同样静默降级，只在设置界面标注状态
  （「天气源不可用」，状态可见纪律），不弹窗。
- key 存 UserDefaults（Mac）/ Tauri store（Win）本地明文——用户自己的免费 key，
  风险可接受；后续如需再迁 Keychain，不在本批。

**权重映射（初版，只认归一化枚举）**：
- sunny：sun ×1.6、watch ×1.2
- rain / snow：外出类（fly/walk/dart/fish）×0.5，栖窗 perch ×1.5（躲雨语义）
- overcast：×1.0 不干预
- 复用现有序列，无新动画。

**明示纪律（硬约束）**：设置默认**关**；开启后才发首个网络请求；设置项文案写明
「会请求所选天气源查询天气（约 30 分钟一次，Open-Meteo 源含 IP 粗略定位）」。
设置 UI：开关 + 城市框（留空 = IP 定位）+ 数据源选择（Open-Meteo / 和风天气），
选和风时展开 Key + Host 两个输入框。

**涉及文件**：
- Mac：新增 `Sources/KingfisherPet/WeatherService.swift`（双 provider + 归一化 +
  缓存 + 通知），`Behavior.swift` 订阅；`Settings.swift` / 设置窗加开关 + 城市框 +
  数据源选择（选和风展开 Key/Host 框；注意设置窗滚动高度联动）
- Win：新增 `windows/src/weather.ts`（前端 fetch 即可，Rust 不动；双 provider 对称），
  `behavior.ts` 订阅；`settings.ts` 加同款三件套 UI

**验证**：weather_code 注入单测（晴/雨/雪/无效四态 × 双源映射表）；和风 key
无效（401/402）静默降级 + 设置界面状态标注；真实城市双源各实测一次；断网场景
验证零弹窗零重试轰炸；勿扰模式下天气请求照常静默（与放音/全屏互不影响）。

## C · 性能背书（测量收尾）

- Win：看门狗（`windows/src-tauri/src/lib.rs`）加周期采样：进程 CPU%（GetProcessTimes
  差分）+ RSS（GetProcessMemoryInfo），每 30s 一行入 kflog。
- Mac：Activity Monitor + `sample` 采样；如空闲 CPU 持续偏高，评估 idle 时降帧（60→30）。
- 产出 `docs/PERFORMANCE.md`：双端 空闲/活跃/勿扰 三态的 CPU / RSS / 网络表。
  顺手勾掉 TODO.md「耗电 / 性能 profiling」条目。

## 明确不做（本批排除）

成长系统、更多随机事件（batch2 候选）；设置云同步、Windows 干净卸载（梯队 3）；
局域网互动 / 皮肤工作台 / 移动端伙伴（远期）。

## 顺序与版本

A（纯本地）→ B（网络+UI，设置文案请老板过目）→ C（测量收尾）→ **v1.5.0**。
行为语义有可见变化（昼夜+天气），够 minor 一位；双端同批发。
