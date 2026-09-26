#!/usr/bin/env bash
# 切换包名。
#
# 为什么需要：后端（表盘位的 Lua 应用）按**包名**找通信目录 /data/data/<包名>/，
# 而快应用沙箱只能读写自己包名下的目录。所以：
#   - 想和现成的 resource.bin 后端互通 → 必须用 com.shell.liangyi
#   - 想保留自己的身份 / 独立发布      → 用 com.byxz.toolbox，后端也得换成我们自己的
#
# 用法：bash tools/set-pkg.sh com.shell.liangyi [应用名]
set -e
cd "$(dirname "$0")/.."
PKG="$1"
NAME="${2:-工具箱}"
[ -z "$PKG" ] && { echo "用法：bash tools/set-pkg.sh <包名> [应用名]"; exit 1; }

python - "$PKG" "$NAME" <<'PY'
import io, json, sys
pkg, name = sys.argv[1], sys.argv[2]
p = 'src/manifest.json'
d = json.load(io.open(p, encoding='utf-8'))
d['package'] = pkg
d['name'] = name
io.open(p, 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False, indent=2) + '\n')
# 通信层里的包名同步
b = 'src/common/core/bridge.js'
s = io.open(b, encoding='utf-8').read()
import re
s = re.sub(r"let PKG = '[^']*'", "let PKG = '" + pkg + "'", s)
io.open(b, 'w', encoding='utf-8', newline='').write(s)
print('包名 → %s，应用名 → %s' % (pkg, name))
PY
