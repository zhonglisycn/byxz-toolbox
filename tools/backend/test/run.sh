#!/usr/bin/env bash
# 后端出厂检查：语法体检 + 协议冒烟测试。改完后端必须先跑这个。
set -e
cd "$(dirname "$0")/../../.."
echo "=== 1/2 Lua 语法体检（fengari / Lua 5.3）==="
node tools/backend/check-lua.mjs backend/toolbox-backend.lua
echo ""
echo "=== 2/2 协议冒烟测试（桩 lvgl + 假 FS + 假 NSH）==="
node tools/backend/test/smoke.mjs
