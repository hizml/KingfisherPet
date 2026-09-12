# v1.6.0 分发批计划 · 公证签名 + 双端应用内自动更新

> 2026-09-11 落盘即开工(老板令"跟代码相关的都把它做完");非代码项(30s 宣传视频)延后。
> 弹药已备齐:Developer ID 证书 + 公证凭证据在 GitHub Secrets( APPLE_DEV_ID_P12_B64/
> APPLE_DEV_ID_P12_PASS/APPLE_ID/APPLE_PASSWORD/APPLE_TEAM_ID),本地密钥在 ~/Developer/kf-certs/。

## A · Mac Developer ID 签名 + notarytool 公证

- **build.sh**:签名身份自动选择——钥匙串里有 "Developer ID Application: MengLong Zhao
  (5CTLSL2C9X)" 就用它(codesign --deep --force --options runtime --timestamp),
  没有退回自签 "KingfisherPet Dev"(本地开发不受影响);公证仅在 CI 做(本地不强依赖凭证)。
- **release.yml native-mac job**:导入 p12(Secrets)→ 签名 → ditto zip →
  `notarytool submit --wait` → 解包 staple → 重打 zip 上传。
  产物 = 已签名+已公证+已 staple 的 mac-native.zip,用户解压双击即开(免右键)。

## B · Windows Tauri updater(应用内下载→验签→安装→重启)

- 密钥对:`tauri signer generate`(空密码,私钥进 Secrets TAURI_SIGNING_PRIVATE_KEY)。
- tauri.conf:`bundle.createUpdaterArtifacts=true` + `plugins.updater`(pubkey+endpoint
  指向 GitHub Releases latest.json);capabilities 补 `updater:default`;
  Cargo 加 tauri-plugin-updater + tauri-plugin-process;lib.rs 注册插件。
- 前端:检查更新发现新版 → 自绘弹窗加「立即更新」→ update.downloadAndInstall()(进度)→
  relaunch;失败/无 updater 产物时回退旧的"前往 Releases 页"路径(不断更)。
- CI:构建步注入 TAURI_SIGNING_PRIVATE_KEY;tauri-action 自动产 latest.json+签名产物。

## C · Mac 应用内自动更新【与计划的偏差,已定案】

- 计划原文写 Sparkle;实装改**自研轻量更新器**(UpdateService 扩展):检查更新复用现有
  GitHub latest 查询 → 发现新版后台下载 mac-native.zip → 解压校验(签名一致性)→
  替换运行中 .app(旧包挪 ~/.Trash,失败回退打开下载页)→ relaunch。
- 理由:零新依赖(不加 SPM 包)、零 CI 新基建(不需要 appcast/ed25519 双密钥体系)、
  复用既有检查更新链路;效果与 Sparkle 等价(应用内下载→安装→重启),砍掉的只有
  增量更新(本应用 zip ≈10MB 级,全量无所谓)。老板认可"尽快做完",取工程最短路径。

## 顺序与版本

A(公证)→ B(Win updater)→ C(Mac updater)→ 双端实测 → **v1.6.0**。
先决条件:v1.5.1 已发(同日 tag)。

## 验证

- Mac:本地 build.sh 出签名包(spctl -a -vv 验证 Developer ID);CI 公证绿 + 产物
  xcrun stapler validate;更新器:本地旧版 + 手动构造假 latest 触发 UI 流(真跨版本
  更新验证等下个版本自然发生)。
- Win:tauri-action 产 latest.json + .sig;本地 `npm run tauri build` 出 updater 产物;
  N5105 实测下载安装重启(打包版必测——dev 不出 updater 产物)。
