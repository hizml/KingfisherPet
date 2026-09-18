#!/usr/bin/env bash
# html 渲染冒烟(v1.7.27 测试补全批):headless 真渲染 dist 页面断言按钮/控件存在。
# 背景:v1.7.4~24 关于窗无按钮潜伏 8 版——`new URL(x, BASE_URL)` 运行时抛错静默杀脚本,
# build/grep 全绿但页面半死。grep/build 只证"代码在",本脚本证"页面活"。
# 跨平台 Chrome 探测(mac/linux/Windows git-bash);CI(lint.yml)与本地通用。
# 用法:bash tools/render_smoke.sh   (须先 npm run build 出 windows/dist)
set -uo pipefail
cd "$(dirname "$0")/.."

DIST="windows/dist"
[ -f "$DIST/update.html" ] || { echo "::error::缺 $DIST/update.html,先 npm run build"; exit 1; }

CHROME="${CHROME_BIN:-}"
if [ -z "$CHROME" ]; then
  for p in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
           "/c/Program Files/Google/Chrome/Application/chrome.exe" \
           "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
           "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
           "google-chrome" "chromium"; do
    if command -v "$p" >/dev/null 2>&1 || [ -f "$p" ]; then CHROME="$p"; break; fi
  done
fi
[ -n "$CHROME" ] || { echo "::error::未找到 Chrome/Edge(可 export CHROME_BIN 指定),渲染冒烟无法执行"; exit 1; }
echo "chrome: $CHROME"

PORT=8137
cd "$DIST"
PY=python3; command -v python3 >/dev/null 2>&1 || PY=python   # Windows runner 只有 python
"$PY" -m http.server $PORT >/dev/null 2>&1 &
SRV=$!
sleep 2
trap 'kill $SRV 2>/dev/null' EXIT

dump() { "$CHROME" --headless --disable-gpu --virtual-time-budget=4000 --dump-dom "http://127.0.0.1:$PORT/$1" 2>/dev/null; }
nbtn() { dump "$1" | grep -o '<button' | wc -l | tr -d ' '; }

fail=0
chk() { # $1=描述 $2=实际 $3=期望
  if [ "$2" != "$3" ]; then echo "::error::渲染冒烟:$1 按钮 $2 个,期望 $3"; fail=1; else echo "OK $1($2)"; fi
}

# update.html 六状态:按钮数(v1.7.25 实测口径;checking=瞬态无按钮但标题必须渲染)
chk "update found"  "$(nbtn 'update.html?t=found&cur=1.0.0&latest=9.9.9')" 2
chk "update latest" "$(nbtn 'update.html?t=latest&cur=1.0.0')" 1
chk "update error"  "$(nbtn 'update.html?t=error')" 2
chk "update guide"  "$(nbtn 'update.html?t=guide')" 2
chk "update about"  "$(nbtn 'update.html?t=about&cur=1.0.0')" 3
dump 'update.html?t=checking' | grep -q 'id="t">[^<]' || { echo "::error::渲染冒烟:checking 状态未渲染(脚本死了?)"; fail=1; }
dump 'update.html?t=about&cur=1.7.27' | grep -q '1\.7\.27' || { echo "::error::渲染冒烟:关于窗无版本行(老板令:关于类 UI 必带版本号)"; fail=1; }

# settings.html 关键控件存在(TDZ/脚本死=全失踪)
sdom=$(dump 'settings.html')
for id in lanOn lanDuet wxKeyTest themes langs; do
  echo "$sdom" | grep -q "id=\"$id\"" || { echo "::error::渲染冒烟:settings.html 缺 #$id"; fail=1; }
done
[ $fail -eq 0 ] && echo "渲染冒烟全过(update 六状态 + settings 五控件)"
exit $fail
