#!/usr/bin/env bash
# Mac 自动化回归:KF_TEST 场景 + 日志断言 + 快照正立像素校验。
# 用法:./tools/run_tests.sh [场景...]  (默认全部:smoke sleepwake themecycle vis_toggle)
# 退出码 0=全过;非 0=有失败(CI/发版前跑)。
set -uo pipefail
cd "$(dirname "$0")/.."

BIN=".build/release/KingfisherPet"
APP_BIN="build/KingfisherPet.app/Contents/MacOS/KingfisherPet"
LOG="/tmp/kf_debug.log"
SNAP="/tmp/kf_snapshot.png"
PY=".venv/bin/python3"
TIMEOUT=40

# 断言 helper:在 [start行,end行) 日志段内 grep
seg_grep() { # $1=start_marker $2=end_marker $3=pattern
  awk -v s="$1" -v e="$2" '$0~s{f=1;next} $0~e{f=0} f' "$LOG" | grep -c "$3" || true
}

run_one() {
  local name="$1"
  local start_line="TEST-START $name"
  local before=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  echo "── 场景 $name"
  KF_TEST="$name" "$BIN" >/dev/null 2>&1 &
  local pid=$!
  local result=""
  for i in $(seq 1 $TIMEOUT); do
    sleep 1
    result=$(tail -n +"$((before+1))" "$LOG" | grep -E "TEST $name (PASS|FAIL)" | tail -1 || true)
    [ -n "$result" ] && break
    kill -0 $pid 2>/dev/null || { sleep 1; result=$(tail -n +"$((before+1))" "$LOG" | grep -E "TEST $name (PASS|FAIL)" | tail -1 || true); break; }
  done
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  if [ -z "$result" ]; then echo "  ❌ TIMEOUT(无 TEST 结果行)"; return 1; fi
  echo "  $result"
  local rc=0
  echo "$result" | grep -q " FAIL " && rc=1   # 结果行本身 FAIL 也计入
  case "$name" in
    sleepwake)
      # 唤醒段(didWake 之后)不应有屎重落(屎雨回归)——段内 refall 计数为 0
      local refalls=$(awk '/didWake effects=/{f=1} /TEST sleepwake/{f=0} f' "$LOG" | grep -c "POOP refall" || true)
      if [ "$refalls" -gt 0 ]; then echo "  ❌ 唤醒后屎重落 x$refalls(屎雨回归!)"; rc=1
      else echo "  ✅ 唤醒后 0 重落"; fi
      # 入睡段必须有 suspend(定时器全停)
      local susp=$(seg_grep "TEST-START sleepwake" "didWake effects=" "PetView suspend")
      [ "$susp" -ge 1 ] && echo "  ✅ 睡眠 suspend" || { echo "  ❌ 睡眠未 suspend"; rc=1; }
      ;;
    themecycle)
      # 每主题帧数都 ≥30(缺资源回归)
      local bad=$(grep "TEST theme=" "$LOG" | awk -F'frames=' '$2+0<30' | wc -l | tr -d ' ')
      [ "$bad" -eq 0 ] && echo "  ✅ 6 主题帧数齐全" || { echo "  ❌ $bad 个主题帧数不足"; rc=1; }
      ;;
  esac

  # 快照正立校验(鸟头窄在上;倒立则上宽下窄)——针对之前的倒鸟回归
  if [ -f "$SNAP" ] && [ -x "$PY" ]; then
    local orient=$("$PY" - "$SNAP" <<'EOF'
import sys, numpy as np
from PIL import Image
try:
    im = np.array(Image.open(sys.argv[1]).convert('RGBA'))[...,3]
    rows = (im > 16).sum(axis=1); ys = np.where(rows > 0)[0]
    if len(ys) < 10: print("EMPTY"); raise SystemExit
    band = rows[ys[0]:ys[-1]+1]; n = len(band)//3
    top, mid = band[:n].mean(), band[n:2*n].mean()
    print("UPRIGHT" if top < mid * 0.9 else "FLIPPED")
except Exception as e:
    print("ERR", e)
EOF
)
    case "$orient" in
      UPRIGHT) echo "  ✅ 快照正立" ;;
      FLIPPED) echo "  ❌ 快照倒立(倒鸟回归!)"; rc=1 ;;
      EMPTY)   echo "  ⚠️ 快照为空(状态无内容,人工看)" ;;
      *)       echo "  ⚠️ 快照校验异常: $orient" ;;
    esac
  fi
  return $rc
}

swift build -c release 2>&1 | grep -E "^error" && { echo "编译失败"; exit 1; }
# 打包(不启动):场景需要 bundle 资源(裸二进制帧数=0,快照会空)
KF_NO_LAUNCH=1 ./build.sh >/dev/null 2>&1
BIN="$APP_BIN"

SCENARIOS=("${@:-smoke sleepwake themecycle vis_toggle}")
FAILED=0
for s in $SCENARIOS; do
  run_one "$s" || FAILED=1
done
echo "════════"
[ $FAILED -eq 0 ] && echo "✅ 全部通过" || echo "❌ 有失败"
exit $FAILED
