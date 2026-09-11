# v1.5.0 batch1 计划 · 天气批（昼夜节律 + 天气联动 + 性能背书）

> 2026-09-08 落盘；同日老板拍板扩订：①细分档 ②迁移彩蛋 ③和风预警 + 躲雨/抖水
> 两新序列全部入批，路线定为「素材+成长批优先，分发批列 TODO」。
> ✅ **2026-09-11 实装完成**（A→B→C 全部落地,等老板发版命令打 v1.5.0 tag）。
> 实装 vs 计划的三处修正（均有依据）:
> 1. 和风码表按官方逐码核对修正:302–304 才是雷阵雨(计划初版写 313–318 系记忆偏差),
>    313 是冻雨、314–318 是跨级雨量;400s 补跨级雪 408–410 与夜间镜像码 350/456/457、
>    399/499 未知强度保守轻档(计划原文要求"以官方码表逐项核对"的执行结果)。
> 2. 和风 500–515 雾霾沙尘类归 fog 档(计划初版归"阴"):能见度类天气鸟少飞多看,
>    比不干预的阴天更有表现力。
> 3. 计划外:Win 资产镜像机制(gen_sprites 渲染完自动同步 windows/public,修复手动
>    拷贝导致的 Win 侧资产漂移——hide/shake 缺帧实际踩到);Mac 设置窗改高度自适应。
> 遗留待办:和风真 Key 全链实测待老板;Win 打包版 UI/彩蛋实测待 N5105;
> 预警/彩蛋的真实天气等待自然触发验证。

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

**归一化枚举扩档（①②③ 老板 2026-09-08 拍板全进）**：
`{sunny, overcast, rain_light, rain_heavy, thunder, snow_light, snow_heavy, fog, wind, hot, cold}`
- 两源码表映射原则（实现时以官方码表逐项核对补全，映射表进单测断言）：
  Open-Meteo WMO 0–2 晴 / 3 阴 / 45–48 雾 / 51–61,80 毛雨小雨 / 63–67,81–82 大雨冻雨 /
  95–99 雷暴 / 71,77,85 小雪 / 73,75,86 大雪；wind_speed>10.8m/s→wind；
  temperature>32→hot、<5→cold。和风 100–103,150–153 晴 / 104,500–508 阴霾沙 /
  305–306 小雨 / 307–312 大雨 / 313–318 雷阵雨 / 400–401,406+ 小雪 / 402–403+ 大雪 /
  900→hot、901→cold（和风自带冷热码）/ windScale≥6→wind。
- 叠加规则：主档互斥取最恶劣（thunder > rain_heavy > wind > …），hot/cold 为
  温度副档可与主档叠乘。

**权重映射（初版，主档系数；全部乘现有桶宽，机制不变）**：

| 档 | 系数 |
|---|---|
| sunny | sun ×1.6、watch ×1.2 |
| overcast | 不干预 |
| rain_light | 外出 ×0.7、栖窗 ×1.3 |
| rain_heavy | 外出 ×0.3、栖窗 ×1.6 |
| thunder | 整体活跃 ×0.3、外出≈0、sleep↑、保留少量 watch（雷惊探头） |
| snow_light | walk ×0.8、watch ×1.5（看雪） |
| snow_heavy | 外出 ×0.4、栖窗 ×1.5、watch ×1.5 |
| fog | fly ×0.5、watch ×1.5 |
| wind | fly ×0.3、栖枝 ×1.5（抓牢） |
| hot（副档） | sun ×0.5、fish ×1.2（戏水降温） |
| cold（副档） | sun ×1.6（取暖）、fly ×0.8 |

**状态迁移彩蛋（②）**：检测档位变化（对比上次缓存），只触发一次：
- 雨停转晴（rain\*→sunny/overcast）：播 happy + 抖水（新序列）
- 初雪（非雪→snow\*）：播 watch（初见雪的好奇）
- 雷暴来袭：飞往栖窗/屏边 + 播躲雨（新序列）
- 同档 2h 冷却，防边界天气在 30min 刷新间来回跳导致连发；事件过代际取消（gen），
  与拖拽/新动作不打架。

**预警事件层（③，和风源专属）**：和风 `/v7/warning/now`（中国气象局台风/暴雨/
寒潮/高温等预警），随 30min 周期同查；Open-Meteo 无预警数据——这是和风口子的
专属福利。
- 首次出现（按预警 ID 去重）：中断当前动作（bump gen）→ 飞栖窗/屏角 → 播躲雨 →
  低活跃（整体 ×0.3）直至解除；托盘菜单标注「⚠ {类型} · 鸟躲起来了」（状态可见纪律）。
- 解除：播一次 happy 出关，菜单恢复。多条并存取级别最高一条展示。
- 勿扰优先：勿扰中不表演（反正隐身），只标菜单。

**新序列两个（老板拍板进本批；其余新动画仍留 v1.5.x）**：
- 「躲雨」hide：收拢站姿、头埋、偶尔探头（2–3 帧），栖窗/地面两用；大雨/雷暴/预警用。
- 「抖水」shake：雨停/预警解除的 happy 变体，身体快速抖动 2–3 帧 + 粒子水珠
  （复用双端粒子系统：Effects.swift / effects.ts）。
- 素材纪律：六主题调色板补键、进 ink 断言键集、colors.json 单源、montage 目检。

**明示纪律（硬约束）**：设置默认**关**；开启后才发首个网络请求；设置项文案写明
「会请求所选天气源查询天气（约 30 分钟一次，Open-Meteo 源含 IP 粗略定位）」。
设置 UI：开关 + 城市框（留空 = IP 定位）+ 数据源选择（Open-Meteo / 和风天气），
选和风时展开 Key + Host 两个输入框。

**涉及文件**：
- Mac：新增 `Sources/KingfisherPet/WeatherService.swift`（双 provider + 归一化 +
  缓存 + 通知），`Behavior.swift` 订阅；`Settings.swift` / 设置窗加开关 + 城市框 +
  数据源选择（选和风展开 Key/Host 框；注意设置窗滚动高度联动）；`Effects.swift`
  水珠粒子；托盘菜单天气/预警状态行。
- Win：新增 `windows/src/weather.ts`（前端 fetch 即可，Rust 不动；双 provider 对称），
  `behavior.ts` 订阅；`settings.ts` 加同款三件套 UI；`effects.ts` 水珠粒子。
- 素材：`tools/gen_sprites.py` 新增 hide / shake 两序列 + 资产重生成（六主题）。

**验证**：weather_code 注入单测（十一档 × 双源映射表）；和风 key 无效（401/402）
静默降级 + 设置界面状态标注；真实城市双源各实测一次；断网场景验证零弹窗零重试
轰炸；勿扰模式下天气请求照常静默（与放音/全屏互不影响）；彩蛋档位迁移触发一次 +
2h 冷却（边界天气来回跳不连发）；预警按 ID 去重、首次/解除各触发一次、勿扰中只标
菜单不表演；hide/shake 六主题 montage 目检 + colors/sprites 断言过。

## C · 性能背书（测量收尾）

- Win：看门狗（`windows/src-tauri/src/lib.rs`）加周期采样：进程 CPU%（GetProcessTimes
  差分）+ RSS（GetProcessMemoryInfo），每 30s 一行入 kflog。
- Mac：Activity Monitor + `sample` 采样；如空闲 CPU 持续偏高，评估 idle 时降帧（60→30）。
- 产出 `docs/PERFORMANCE.md`：双端 空闲/活跃/勿扰 三态的 CPU / RSS / 网络表。
  顺手勾掉 TODO.md「耗电 / 性能 profiling」条目。

## 明确不做（本批排除）

炸毛 / 寒颤等其余新序列、觅食回巢 / 访客鸟、成长系统 → **v1.5.x 素材+成长批**；
设置云同步、Windows 干净卸载（梯队 3）；
局域网互动 / 皮肤工作台 / 移动端伙伴（远期）。

## 顺序与版本

A（纯本地）→ B（网络 + UI + 彩蛋 + 预警 + 躲雨/抖水，设置文案请老板过目）→
C（测量收尾）→ **v1.5.0**。双端同批发。

## 批次路线（2026-09-08 老板拍板；⏸ 等老板命令才开工）

| 批次 | 内容 | 状态 |
|---|---|---|
| v1.4.62 | review 修复批 | draft 停等发布；发版前装 Win 包点一次「检查更新」实测 CSP/set-size |
| v1.5.0 | 本计划：昼夜 + 天气（细分档/彩蛋/预警）+ 躲雨/抖水 + 性能背书 | ⏸ 计划已定，**等开工命令** |
| v1.5.x | 素材+成长批：炸毛/寒颤等序列补全、觅食回巢/访客鸟、成长系统轻量版（喂鱼→eat+happy、亲密度影响互动频率、egg 升级真孵化） | 排天气批后 |
| v1.6.0 | 分发批：Developer ID+公证、自动更新、30 秒宣传视频 | 已列 TODO.md，随公众号发文的引流节奏提级 |
