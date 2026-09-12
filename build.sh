#!/usr/bin/env bash
# 构建 翡(KingfisherPet)桌面宠物为 .app 并启动
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_NAME="KingfisherPet"
BUNDLE_ID="com.hizml.kingfisher-pet"
EXEC="$APP_NAME"
APP="build/${APP_NAME}.app"

echo "==> 1/6 swift build (release)"
swift build -c release --product KingfisherPet   # 只编应用(测试壳 kf-tests 另走 swift run)
BIN=".build/release/${EXEC}"
if [[ ! -f "$BIN" ]]; then
  echo "找不到编译产物 $BIN"; exit 1
fi

echo "==> 2/6 组装 .app 包"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${EXEC}"

# 资源:按主题子目录放到 Resources/Sprites/<theme>/(SpriteLibrary 按子目录加载)
#   每个主题各含 *.png + sprites.json + contact.png(检查图,不进包)
SPRITES_SRC="Resources/Sprites"
mkdir -p "$APP/Contents/Resources/Sprites"
for theme_dir in "$SPRITES_SRC"/*/; do
  theme_name="$(basename "$theme_dir")"
  mkdir -p "$APP/Contents/Resources/Sprites/$theme_name"
  cp "$theme_dir"*.png "$APP/Contents/Resources/Sprites/$theme_name/" 2>/dev/null || true
  cp "$theme_dir"sprites.json "$APP/Contents/Resources/Sprites/$theme_name/" 2>/dev/null || true
  cp "$theme_dir"colors.json "$APP/Contents/Resources/Sprites/$theme_name/" 2>/dev/null || true
  # 检查图不进包
  rm -f "$APP/Contents/Resources/Sprites/$theme_name/contact.png"
done
# 叫声(多种,不随主题)
cp Resources/peep_*.wav "$APP/Contents/Resources/" 2>/dev/null || true

echo "==> 3/6 生成图标"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC="Resources/Sprites/flat/idle_0.png"
if [[ -f "$SRC" ]]; then
  for spec in "16" "32 16@2x" "32" "64 32@2x" "128" "256 128@2x" "256" "512 256@2x" "512" "1024 512@2x" "1024"; do
    set -- $spec
    if [[ $# -eq 1 ]]; then
      sips -z "$1" "$1" "$SRC" --out "$ICONSET/icon_${1}x${1}.png" >/dev/null
    else
      sips -z "$1" "$1" "$SRC" --out "$ICONSET/icon_${2}.png" >/dev/null
    fi
  done
  if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1; then
    ICON_NAME="AppIcon"
  else
    ICON_NAME=""
  fi
else
  ICON_NAME=""
fi

echo "==> 4/6 写 Info.plist"
ICON_LINE=""
[[ -n "$ICON_NAME" ]] && ICON_LINE="<key>CFBundleIconFile</key><string>${ICON_NAME}</string>"
APP_VER=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
[[ -z "$APP_VER" ]] && APP_VER="dev"   # 无 tag 环境(检查更新对 dev 恒提示新版)

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>翡 · KingfisherPet</string>
  <key>CFBundleDisplayName</key><string>翡</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>${APP_VER}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleSignature</key><string>????</string>
  <key>CFBundleExecutable</key><string>${EXEC}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>zh-Hans</string>
    <string>en</string>
  </array>
  ${ICON_LINE}
</dict>
</plist>
PLIST

echo "==> 5/6 签名(v1.6.0:优先 Developer ID 正式签名→退回自签→ad-hoc)"
DEV_ID="Developer ID Application: MengLong Zhao (5CTLSL2C9X)"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEV_ID"; then
    # 正式分发签名:hardened runtime(公证硬性要求)+ 安全时间戳(离线可验)
    if codesign -s "$DEV_ID" --force --deep --options runtime --timestamp "$APP"; then
        echo "    Developer ID 签名 ✓"
    else
        echo "    (Developer ID 签名失败,退回自签)"
        codesign -s "KingfisherPet Dev" --force --deep "$APP" >/dev/null 2>&1 || \
            codesign -s - --force --deep "$APP" >/dev/null 2>&1 || echo "    (codesign 跳过)"
    fi
elif codesign -s "KingfisherPet Dev" --force --deep "$APP" >/dev/null 2>&1; then
    echo "    自签 KingfisherPet Dev(本地开发用;正式分发走 CI 公证)"
else
    codesign -s - --force --deep "$APP" >/dev/null 2>&1 || echo "    (codesign 跳过)"
fi

# 可选公证(本地开发默认不做;设置 KF_NOTARIZE=1 且三凭证在环境时走 CI 同款流程)
if [ -n "${KF_NOTARIZE:-}" ] && [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    echo "==> 5.5/6 公证(notarytool)"
    ZIP="$(dirname "$APP")/$(basename "$APP" .app)-notarize.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    if xcrun notarytool submit "$ZIP" --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" \
         --team-id "$APPLE_TEAM_ID" --wait; then
        xcrun stapler staple "$APP" && echo "    公证+staple ✓"
        rm -f "$ZIP"
    else
        echo "    (公证失败,产物仍可用但未公证)"
    fi
fi

echo "==> 6/6 启动"
# 若已在运行先关掉
pkill -x "$EXEC" 2>/dev/null || true
sleep 0.2
if [ -z "${KF_NO_LAUNCH:-}" ]; then
  open "$APP"
fi
echo "完成: $APP"
