#!/usr/bin/env bash
# 一键构建：内核测试 → 页面静态检查 → 编译 → 输出 .bin
set -e
cd "$(dirname "$0")/.."

NAME="工具箱_byxz"

echo "=== 1/4 内核测试（表达式 / 方程 / 绘图）==="
bash tools/run-tests.sh

echo ""
echo "=== 2/4 页面静态检查 ==="
node tools/check-ux.mjs
node tools/fix-text-style.mjs

echo ""
echo "=== 3/4 编译（--enable-jsc 生成字节码）==="
npx aiot build --enable-jsc

echo ""
echo "=== 4/4 输出 .bin ==="
RPK=$(ls dist/*.rpk | head -1)
cp "$RPK" "dist/$NAME.bin"
ls -la "dist/$NAME.bin"
echo ""
echo "完成：dist/$NAME.bin"
