#!/usr/bin/env bash
# 渲染全部页面并截图（需要本机有 Edge/Chrome）
# 用法：bash tools/preview.sh [页面名...]
set -e
cd "$(dirname "$0")/.."

EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
[ -x "$EDGE" ] || EDGE="/c/Program Files/Google/Chrome/Application/chrome.exe"
if [ ! -x "$EDGE" ]; then echo "找不到 Edge/Chrome，无法截图"; exit 1; fi

node tools/preview.mjs "$@"

OUT="$(pwd)/tools/preview/out"
WINOUT='C:\Users\39830\Documents\zcode\shellpp\tools\preview\out'
PROFBASE="/c/Users/39830/AppData/Local/Temp/lrprev"

shoot() {
  local name="$1"
  local prof="${PROFBASE}-${name}"
  rm -rf "$prof"
  rm -f "$OUT/$name.png"
  "$EDGE" --headless=new --disable-gpu --no-first-run --hide-scrollbars \
    --user-data-dir="$(cygpath -w "$prof" 2>/dev/null || echo "$prof")" \
    --force-device-scale-factor=2 --window-size=212,520 \
    --screenshot="$WINOUT\\$name.png" \
    "file:///C:/Users/39830/Documents/zcode/shellpp\tools\preview\out/$name.html" \
    > /dev/null 2>&1 || true
  for i in $(seq 1 120); do
    [ -f "$OUT/$name.png" ] && { echo "截图 $name.png"; return 0; }
    sleep 0.5
  done
  echo "截图失败 $name"
  return 1
}

for f in "$OUT"/*.html; do
  name=$(basename "$f" .html)
  if [ $# -gt 0 ] && [ "$1" != "all" ]; then
    hit=0
    for w in "$@"; do [ "$w" = "$name" ] && hit=1; done
    [ "$hit" = "0" ] && continue
  fi
  shoot "$name" || true
done

rm -rf "${PROFBASE}"-* 2>/dev/null || true
echo "产物目录：tools/preview/out/"
