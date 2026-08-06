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
swift build -c release
BIN=".build/release/${EXEC}"
if [[ ! -f "$BIN" ]]; then
  echo "找不到编译产物 $BIN"; exit 1
fi

echo "==> 2/6 组装 .app 包"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${EXEC}"

# 资源:png / sprites.json / peep.wav 全部铺平放到 Resources
cp Resources/Sprites/*.png   "$APP/Contents/Resources/" 2>/dev/null || true
cp Resources/Sprites/sprites.json "$APP/Contents/Resources/" 2>/dev/null || true
cp Resources/peep.wav        "$APP/Contents/Resources/" 2>/dev/null || true
# 去掉生成器自检用的检查图,不进包
rm -f "$APP/Contents/Resources/contact.png" "$APP/Contents/Resources/eggs_check.png"

echo "==> 3/6 生成图标"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC="Resources/Sprites/idle_0.png"
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
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>翡 · KingfisherPet</string>
  <key>CFBundleDisplayName</key><string>翡</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleSignature</key><string>????</string>
  <key>CFBundleExecutable</key><string>${EXEC}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  ${ICON_LINE}
</dict>
</plist>
PLIST

echo "==> 5/6 ad-hoc 签名"
codesign -s - --force --deep "$APP" >/dev/null 2>&1 || echo "    (codesign 跳过)"

echo "==> 6/6 启动"
# 若已在运行先关掉
pkill -x "$EXEC" 2>/dev/null || true
sleep 0.2
open "$APP"
echo "完成: $APP"
