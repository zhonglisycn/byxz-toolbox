# -*- coding: utf-8 -*-
"""把改好的 Lua 装回 Luavgl .bin 容器（resource.bin 的结构）。

容器结构（实测）：
  0x000 .. 0x90E  头部：魔数 5a a5 34 12、24 条索引表（0x150 起）、序列号、应用名等
                  索引表每条 = u32 数据偏移, u32 条目总长, u32 编号, u32 保留
  0x90E .. EOF    条目区，只有两个条目：
                    [0] 16 字节小条目（0x168）
                    [1] 大条目 = 4 字节标志 + 16 字节 0 + 21 字节文件名 + Lua 载荷（到文件尾）
  条目总长 = 20 + 文件名长度 + 载荷长度（索引表里记的就是这个数）

只替换 Lua 载荷，头部原样保留；条目 1 是最后一个条目，变长不影响别人。

用法：python tools/backend-port/pack-luavgl.py <原 bin> <新 lua> <输出 bin>
"""
import io, struct, sys, os

HEAD_END = 0x90E
TOC_OFF, TOC_COUNT = 0x150, 24
NAME_LEN = 21          # '_lua/Lua/Terminal.lua' + NUL

def repack(src, lua_path, dst):
    d = bytearray(io.open(src, 'rb').read())
    lua = io.open(lua_path, 'rb').read()
    if d[:4] != b'\x5a\xa5\x34\x12':
        raise SystemExit('不是 Luavgl 容器（魔数不对）')
    # 条目 1 的原信息
    off, size, ident, flag = struct.unpack('<4I', d[TOC_OFF + 16:TOC_OFF + 32])
    if off != HEAD_END:
        raise SystemExit('条目区起点不是 0x%X（实际 0x%X）' % (HEAD_END, off))
    old_total = 20 + NAME_LEN + len(d) - HEAD_END - (20 + NAME_LEN)   # = 文件尾 - 起点
    new_total = 20 + NAME_LEN + len(lua)
    head = bytes(d[:HEAD_END])
    blob = bytes(d[HEAD_END:HEAD_END + 20 + NAME_LEN]) + lua
    out = bytearray(head) + bytearray(blob)
    # 回填索引表
    struct.pack_into('<4I', out, TOC_OFF + 16, HEAD_END, new_total, ident, flag)
    io.open(dst, 'wb').write(bytes(out))
    return off, old_total, new_total

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print(__doc__); sys.exit(1)
    src, lua_path, dst = sys.argv[1], sys.argv[2], sys.argv[3]
    off, old_total, new_total = repack(src, lua_path, dst)
    print('条目 1：偏移 0x%X，长度 %d → %d（%+d）' % (off, old_total, new_total, new_total - old_total))
    print('输出 %s（%d 字节）' % (dst, os.path.getsize(dst)))
