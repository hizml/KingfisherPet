# 修复分工方案(2026-09)——两评审会话协同

> 给 sess_ce3bb42e(Windows 侧会话)的协商函。本文件由 sess_a2c37744(Mac 侧会话)起草。
> 双方已互评对方 review 文档(docs/CODE_REVIEW-2026-09.md ↔ docs/CODE_REVIEW-2026-09-07.md),
> 结论:两报告互补,零冲突发现,合并修复。以下按**文件边界**分工,避免 git 冲突。

## 一、分工边界(硬边界,勿越界改文件)

| 区域 | 负责 | 说明 |
|---|---|---|
| `Sources/KingfisherPet/*.swift` | **a2c37744(本会话)** | Mac 全部 |
| `tools/gen_sprites.py` + 资产重生成 | a2c37744 | 素材三🔴 |
| `build.sh`、`Package.swift` | a2c37744 | |
| `.github/workflows/release.yml` | a2c37744 | 签名链由本会话建,含 E2(warning+verify) |
| `README.md`、`docs/`(评审/TODO/TESTING/DEV_NOTES 文档对齐) | a2c37744 | |
| `windows/src/*.ts`、`windows/*.html` | **ce3bb42e(贵会话)** | Windows 前端 |
| `windows/src-tauri/`(rs/Cargo/tauri.conf/capabilities) | ce3bb42e | |
| `.github/workflows/lint.yml` | ce3bb42e | 含 E5(any 收紧)、E4(PR+Swift job 可协商:Swift job 若加,由 a2c37744 提供命令 `swift build -c release`,贵方只加 yaml) |

**共享只读文件**(谁都不改,如需改动在本文档评论区留言):`docs/FIX-DIVISION-2026-09.md` 自身、两份评审报告原文。

## 二、修复清单(合并两报告,勾选进度)

### A 组:a2c37744(Mac + 素材 + CI 签名 + 文档)
- [ ] R3/P0-3 前置:AX 弹窗路径 Bundle.main.bundleURL(KingfisherPetApp:302)
- [ ] R4/P0-3:勿扰死锁——dndCheck 对 offscreen/sleeping 也累计 fsOffStreak(:179-205)
- [ ] A5:探针判据 txt=="1" → 数值 >0(SpriteLibrary:212)
- [ ] A8:enterDnd 补 dragging=false(Behavior:703-721)
- [ ] B1:purgeLayers 后 setVisible 重建裂纹(CrackController:39-63,注释与实现对齐)
- [ ] C5:Language.didChangeNotification——接入观察者或删除(Language:13-17)
- [ ] A6:Behavior:605 / Poop:201 屏高换算统一 screens[0]
- [ ] Mac 死代码:axWarnOnce/headOffset/mouseDownTime/fsDiagSnapshot 门控/launchPath/feetOffset 三处统一
- [ ] B2:updateAlert 文案入 Language 字典(双语)
- [ ] R6:gen_sprites neon 补 13 色键 + 启动断言(键集⊆检查)
- [ ] R7:post_ink 橙检测二选一(补 MOUTH/TONGUE/BLUSH/SWEAT 墨色)
- [ ] R8:colors.json 单源化(_effect_palette 生成,删 gen_colors 手写)
- [ ] 资产重生成 + 六主题 contact 逐张检查(重点 neon 蛋/水墨嘴舌)
- [ ] R9:README 中英补检查更新+啄屏开关;3.5-7s/放音机制/跨屏表述;中英整节对齐
- [ ] TODO 签名条目/TESTING 断言 2-8/DEV_NOTES 过时段落
- [ ] E2:release.yml 签名回退 ::warning + codesign --verify;E1 dispatch 守卫;npm ci;资源 cp 分条;plist sed 校验(release.yml 归 a2c37744,一并做)

### B 组:ce3bb42e(Windows 前端 + Rust + lint)
- [ ] P0-1:CSP 补 connect-src 'self' https://api.github.com(tauri.conf:31)
- [ ] P0-2:capabilities 补 core:window:allow-set-size(+grep 复核删冗余)
- [ ] R5/B4:doCheckUpdate 补 r.ok/typeof 校验(main.ts:114)
- [ ] A1:空中拉屎 X 乘 _scale(behavior.ts:286,对照 :360)
- [ ] A2:wake !onScreen 分支补 setSleepMuted(false)(behavior.ts:556)
- [ ] A3:sleepForUserAbsence 补 stopPerchCheck(behavior.ts:534)
- [ ] A4:延迟 wake 前复查 is_locked_here(system.rs:30-41)
- [ ] A7:dndSet(true) 清 thinkTimer(behavior.ts:737)
- [ ] setMainVisible:hide 路径验证+重试;返回值消费或删除
- [ ] B5:settings.ts NaN 防护(Number.isFinite)
- [ ] B6:语言链——kf_lang 回写 + settings-sync 带 lang(main.ts/settings.html)
- [ ] B7:stage-origin 挪 childReady 后(poop.ts:57)
- [ ] B8:build 改 tsc --noEmit && vite build + 删 src/*.js 存量
- [ ] B2 半条:update.html 默认分支 error;open 失败不关窗
- [ ] C1-C4/D1/D3/D7:死代码(show_window_bottom_right/recall emit/login/act_/spd_/lang_/白建 menu/Box::leak→String/GetWindowRect→visible_rect/poop-drop scale 死字段/win 死变量)
- [ ] C6 半条:behavior.ts:200 注释删/:654 废弃方案注释改写/hittest 注释
- [ ] D6:tauri.conf version → 1.4.60
- [ ] D8:kflog 本地时区(GetTimeZoneInformation)
- [ ] E5:lint as any 收紧为 `as any|: any`;E4:加 pull_request 触发(+可选 macos job)
- [ ] lib.rs:is_zh() 缓存、Cargo 死 features(Power/Memory)

### C 组:协调项(先动者定参数,后者对齐,写回本文档)
- [ ] think 权重未归一(sleep 桶 37%):**a2c37744 先改 Mac 并把最终权重表贴到下方评论区** → ce3bb42e 对齐 Win
- 行为细节 5 项对齐(zzz 高度/sun 侧选/walk 语义/poop 时序/onGround 容差):**本批不做**,两报告一致列为下批

## 三、协同纪律
1. 只改自己区域文件;发现对方区域问题 → 写本文档"评论区",不动手
2. 每完成一项勾一个 `- [x]`;commit message 前缀 `[mac]` / `[win]`
3. **不要打 tag**:全部完成、双方在评论区确认后,由 a2c37744 统一 tag v1.4.60(发版纪律:CI 绿→draft→老板确认)
4. 基线:以读到本文档时的 origin/main 最新为准;开工前先 pull

## 四、评论区
(双方留言区,格式:`— [会话/时间] 内容`)
