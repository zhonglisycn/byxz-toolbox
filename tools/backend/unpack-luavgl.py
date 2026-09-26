# -*- coding: utf-8 -*-
"""通用 Luavgl 容器解包：不假设布局，直接在整文件里找条目头。

条目结构（与 resource.bin 相同）：
    20 字节头：u16 载荷长度 | u8 标志 | u8 文件名长度 | 16 字节保留
    文件名（长度含结尾 0）
    载荷

用法：python tools/backend/unpack-luavgl.py <容器.bin> <输出目录>
"""
import io
import os
import re
import struct
import sys

src = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\39830\Downloads\米环管理 3.0 (1).bin'
out = sys.argv[2] if len(sys.argv) > 2 else 'backend/ref-mihuan3'
d = io.open(src, 'rb').read()
os.makedirs(out, exist_ok=True)
print('容器 %d 字节，魔数 %s' % (len(d), d[:4].hex(' ')))

# 名字一律是可打印路径，以此定位每个条目头
pat = re.compile(rb'[\w\-./]{4,80}\.(lua|json|txt|png|ttf)')
found = []
for m in pat.finditer(d):
    name = m.group().decode('utf-8', 'replace')
    hdr = m.start() - 20
    if hdr < 0:
        continue
    plen = struct.unpack('<H', d[hdr:hdr + 2])[0]
    flag = d[hdr + 2]
    nlen = d[hdr + 3]
    if nlen != len(m.group()) + 1:
        continue
    if plen == 0 or hdr + 20 + nlen + plen > len(d):
        continue
    found.append((hdr, name, plen, flag))

print('找到 %d 个条目：' % len(found))
saved = []
for hdr, name, plen, flag in found:
    payload = d[hdr + 20 + len(name) + 1: hdr + 20 + len(name) + 1 + plen]
    kind = '← Lua' if name.endswith('.lua') else ''
    print('  0x%06X %-46s %7d 字节  flag=%d %s' % (hdr, name, plen, flag, kind))
    if name.endswith('.lua') or name.endswith('.json') or name.endswith('.txt'):
        fp = os.path.join(out, name.replace('/', '_'))
        io.open(fp, 'wb').write(payload)
        saved.append((name, fp, plen))

print('\n导出文本条目 %d 个到 %s/' % (len(saved), out))
for n, fp, pl in saved:
    print('  %-46s %7d 字节' % (n, pl))
