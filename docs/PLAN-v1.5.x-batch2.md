# v1.5.x batch2 计划 · 素材+成长批(炸毛/寒颤/觅食/访客鸟 + 成长系统轻量版)

> 2026-09-11 落盘即开工(老板命令"继续进行下一阶段的开发");同日实装完成
> (素材 1437cd0 / Mac 9a87b26 / Win 2bfdbb2,CI 绿,Mac 7 场景全过含孵化整链)。
> 设计决策(孵化=下蛋+小鸟绕飞告别非常驻/亲密度不进权重带只驱动来访概率/访客为
> 短命 overlay 非第二行为机)按【可调】标注落在正文,老板可随时改。
> 批次内容为 2026-09-08 老板拍板("1 和 2 都进吧…先做素材加成长"),本文补实现设计;
> 标注【可调】的决策是我做的保守选择,老板随时可改。

## 范围

1. **四个新序列**(六主题):炸毛 puff / 寒颤 shiver / 觅食回巢 forage / 访客鸟 visitor
2. **成长系统轻量版**:喂鱼 / 亲密度(影响互动频率) / 满级孵化彩蛋

## A · 素材(gen_sprites.py)

| 序列 | 帧设计 | fps | 触发(行为侧) |
|---|---|---|---|
| puff 炸毛 | puff_0 蓬毛+瞪眼+小跳(body_dy-3)、puff_1 蓬毛回落;复用 fluff/alert 参数 | 6 | 拖拽松手落地后 8%;啄裂屏幕后 25%(被自己啄裂的屏吓到)【可调】 |
| shiver 寒颤 | shiver_0/1 蓬毛缩脖左右交替(head_tilt ±3 + tail_wag ±4);无新调色键 | 10 | 天气 cold 副档生效时 think() 15% 概率插播;配寒气粒子(白雾)后补 |
| forage 觅食 | forage_0 低头深啄(复用 head_jab)、forage_1 叼虫抬头(**新道具:小虫 WORM,粉色小线团**)、forage_2 仰头吞咽;行为链=飞落地→连啄→叼虫→飞回树枝→吞→满足 | 6 | startFish 25% 变体(地面觅食代替俯冲)【可调】 |
| visitor 访客鸟 | 复用 idle/fly/sing 姿态,TEAL/ORANGE 换成紫罗兰/玫瑰调色板(**调色板派生,不新增绘制路径**);命名 visitor_idle_0…/visitor_fly_1…/visitor_sing_0… | - | 稀有随机(每 think 0.6%,2h 冷却):一只鸟飞入→在本鸟旁停留对唱(本鸟应答 sing)→飞离;满级孵化彩蛋复用同一套(见 B) |

调色板纪律:WORM 新键进 ink 断言键集 + neon/watercolor 补键;visitor 派生自各主题解析后调色板(墨色主题访客=另一只灰鸟,成立);montage 补格目检;Win 镜像自动(gen_sprites mirror_to_windows)。

## B · 成长系统轻量版

**存储**:`kingfisher.growth.intimacy`(UserDefaults)/ `kf_intimacy`(localStorage),0–100,不衰减【可调】。

**加分**【数值可调】:点击 +1;喂鱼 +8(冷却 10 分钟);召唤 +2;鸟自发捕鱼成功 +1;天气彩蛋触发 +3。

**档位**(托盘菜单状态行「❤ 相识 · 37/100」,状态可见纪律):
0–19 陌生 / 20–39 相识 / 40–59 熟悉 / 60–79 亲近 / 80–99 亲密 / 100 缘定一生。

**亲密度影响互动频率**(不动 thinkBands 权重,双端公式不改——直接概率插播):
- think() 按档位 0.4%/0.8%/1.2%/1.8%/2.5% 概率**主动飞来屏幕中段看一眼**(affection visit,复用 callOver 航线);
- 档位 ≥熟悉(40)时 sing 概率隐性上升由彩蛋与主动来访共同体现(不另调权重,保持可测)。

**喂鱼**:托盘菜单「喂条鱼」→ 播 eat_0–2(自带叼鱼帧)+ happy + 啾 + 亲密度 +8;冷却 10 分钟内点击只播吃不给分。

**满级孵化彩蛋【可调——设计我拍,老板可推翻】**:亲密度到 100 一次性触发:本鸟下蛋(egg 帧)→ 蛋原地摇摆(egg_1/2)→ 孵出**小鸟跟班**(visitor 素材缩放 0.6×)绕本鸟飞两圈 → 挥翅告别飞走;标记 `hatched` 持久化,菜单档位显示「缘定一生(已孵化)」。不常驻第二只鸟(常驻=行为机复杂度×2,留给远期)。

## C · 不做(本批排除)

- 成长系统不碰 thinkBands 权重带(昼夜/天气双层公式已冻结进双端单测);
- 亲密度不衰减、不做每日任务/签到;
- 访客鸟不栖窗不拉屎(短命 overlay,复用特效窗基建);
- 小鸟跟班不常驻。

## 涉及文件

- 素材:`tools/gen_sprites.py`(puff/shiver/forage+worm/visitor)→ 重生成六主题 + 自动镜像 Win
- Mac:新增 `Sources/KingfisherPetCore/Growth.swift`(亲密度+档位+冷却+孵化事件)、`VisitorService.swift`(访客/小鸟 overlay 窗);Behavior 接线(puff/shiver/forage/affection/visitor 触发);AppDelegate 菜单(❤ 状态行+喂条鱼);Effects 寒气粒子(若时间允许)
- Win:新增 `windows/src/growth.ts`、visitor 走 poop 舞台窗 fx 事件(kind=visitor,路径动画);behavior.ts 接线;Rust 菜单(状态行+feed 菜单项)
- 文档:TODO 勾账、PLAN 状态、memory

## 验证

- 素材:六主题 montage 目检 + ink/neon 程序化色检(同 B1 轮做法)
- 成长:档位换算/冷却/满级一次性 单测进 kf-tests + node --test(同口径)
- 行为:KF_TEST=weather_acts 同款思路加 growth_acts 场景(喂鱼→eat 状态;亲密度注入→affection/孵化事件可控触发)
- 双端构建 + CI 绿;实机 Mac 场景跑,Win 打包版待 N5105(v1.5.0 的也一并补)

## 顺序与版本

A 素材 → B 成长(Mac) → C Win 镜像 → D 单测+场景+构建 → 收尾。
版本 v1.5.1(素材+成长,语义化小版本;不打 1.6——那留给分发批)。
