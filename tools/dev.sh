#!/usr/bin/env bash
# 开发测试模式启动:带 🧪 测试菜单(演出/昼夜模拟/亲密度/勿扰链路/弹窗样例)。
# 仅开发用——发布包由 Finder/浏览器启动,永远没有 KF_DEV_MENU 环境变量,菜单不会出现。
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -d build/KingfisherPet.app ]; then
  echo "未找到 build/KingfisherPet.app,先跑 ./build.sh" >&2
  exit 1
fi
if pgrep -x KingfisherPet >/dev/null; then
  echo "先停掉在跑的实例…" >&2
  pkill -x KingfisherPet || true
  sleep 1
fi
nohup env KF_DEV_MENU=1 build/KingfisherPet.app/Contents/MacOS/KingfisherPet >/dev/null 2>&1 & disown
echo "翡 已带 🧪 测试菜单启动(托盘最底部的「测试」子菜单)"
