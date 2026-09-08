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

**数据链**：
- 天气：Open-Meteo current（免 key）：`api.open-meteo.com/v1/forecast?...&current=weather_code`
- 定位：默认 ipapi.co IP 粗定位拿 lat/lon；设置窗手填城市则走 Open-Meteo
  geocoding（`geocoding-api.open-meteo.com/v1/search?name=`）覆盖。
- 刷新：30 分钟一次；**失败静默降级 = 无系数**，不弹窗、不重试轰炸，等下个周期自然重试。

**权重映射（初版）**：
- weather_code 0–1（晴）：sun ×1.6、watch ×1.2
- 雨 51–67 / 雪 71–77：外出类（fly/walk/dart/fish）×0.5，栖窗 perch ×1.5（躲雨语义）
- 阴/雾等其余：×1.0 不干预
- 复用现有序列，无新动画。

**明示纪律（硬约束）**：设置默认**关**；开启后才发首个网络请求；设置项文案写明
「会请求 Open-Meteo 查询天气（约 30 分钟一次，含 IP 粗略定位）」。城市框留空 = IP 定位。

**涉及文件**：
- Mac：新增 `Sources/KingfisherPet/WeatherService.swift`（拉取+缓存+通知），
  `Behavior.swift` 订阅；`Settings.swift` / 设置窗加开关+城市框（注意设置窗滚动高度联动）
- Win：新增 `windows/src/weather.ts`（前端 fetch 即可，Rust 不动），
  `behavior.ts` 订阅；`settings.ts` 加开关+城市框

**验证**：weather_code 注入单测（晴/雨/雪/无效四态）；真实城市实测一次；
断网场景验证零弹窗零重试轰炸；勿扰模式下天气请求照常静默（与放音/全屏互不影响）。

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
