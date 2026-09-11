# 性能档案(PERFORMANCE)

> v1.5.0 天气批 C 部分产出。双端常驻资源占用的背书数据 + 采样机制说明。
> 数据口径:CPU 为进程占用(ps %cpu 同口径,多核可 >100%),RSS 为驻留内存。

## 采样机制(产品内建,长期可查)

| 平台 | 采样器 | 节拍 | 日志位置 | 行样例 |
|---|---|---|---|---|
| macOS | WatchdogService(15s,自带熔断职能) | 15s | `/tmp/kf_debug.log` | `WATCHDOG cpu=0.7% rss=111MB effects=0 windows=3 state=idle` |
| Windows | rust 看门狗 perf_sample(GetProcessTimes 差分 + GetProcessMemoryInfo) | 30s | `%APPDATA%/KingfisherPet/kf.log` | `PERF cpu=1.2% rss=180MB` |

两行都随日常运行自动落盘,发版后用户报"卡/费电"时直接要日志文件即可,无需复现。

## macOS(实测:Apple Silicon arm64,2026-09-11,常驻 2.5 分钟采样)

| 状态 | CPU | RSS | 备注 |
|---|---|---|---|
| 常驻活动(空闲+动作混合) | **均值 0.9%,峰值 2.1%** | **≈111 MB** | 10 个采样点,状态含 idle/sun |
| 隐藏(显示/隐藏→隐藏) | ≈0(机制值) | 同上 | 全部 timer 挂起(suspendAnimation/branch/poop/think 同停),仅剩看门狗 15s 一次 `ps` fork;挂起路径由 `tools/run_tests.sh` sleepwake 场景的 "PetView suspend" 断言保障 |
| 勿扰(全屏应用) | ≈0(机制值) | 同上 | 与隐藏同一挂起路径(enterDnd → suspend 全家桶),结构同隐藏态 |

## Windows(机制说明 + 待实测)

- 采样器已随 v1.5.0 进包(30s 一行 PERF),数据自来。
- 参考量级(同架构 Tauri WebView2 桌宠):空闲 CPU ≈0.5–2%,RSS ≈150–250 MB(WebView2 运行时常驻比 AppKit 重,属正常)。
- **首份实测数据待 N5105 装包采集**(跑 10 分钟,取 kf.log 的 PERF 行均值即可,欢迎回填本表)。

## 网络(v1.5.0 天气联动开启后)

- 请求节奏:开启时 1 次 + 每 30 分钟 1 次(天气 [+ 预警,和风源]),每次 2–5 KB JSON;
  IP 定位仅在"城市留空"时发生,同节奏。理论流量 ≈ **0.3 MB/天**(按 5KB×60 次)。
- 天气关闭(默认):零网络行为(检查更新仍是既有的启动+24h 一次 GitHub 查询)。
- 失败不重试轰炸:静默降级,等下个 30 分钟周期。

## 资源构成(静态事实)

- 常驻窗口:鸟(160×160)/ 阴影 / 树枝(按需)/ 屎舞台 / 裂纹(按需);macOS 另有池化 zzz 窗。
- 常驻定时器:60fps 渲染 tick(睡眠/勿扰挂起)、20fps 栖窗跟随(栖窗时)、15/30s 看门狗、行为 think(1.5–7s 随活跃度)。
- v1.5.0 新增常驻开销:天气 30min 定时器(一次 fetch,无轮询);昼夜节律零开销(纯函数,think 时计算)。
