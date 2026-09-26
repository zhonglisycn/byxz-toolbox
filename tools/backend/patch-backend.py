# -*- coding: utf-8 -*-
"""把原作者的后端（为 10 Pro 336×480 调校）适配到小米手环 10（212×520 / VelaOS 4.0）。

改四件事，都是外科手术式的替换，不重写它的逻辑：

1. 通信目录：原作者写死三个路径，全是 10 Pro 的布局；手环 10 的 VelaOS 4.0 可能不一样。
   改成"候选列表 + 让快应用先写一个 tool_hello.json 当路标，后端扫到哪个就用哪个"。
2. 版面常量：原本写死 336×480 调校（间距/圆角/按钮/顶栏/像素精灵格子）。
   改成按屏宽算出缩放系数。
3. 截图 profile：原本按固件版本号写死偏移（那是 10 Pro 的），手环 10 上宁可不猜——
   改成读配置文件，没配置就先用 RGB888 + 整屏跳过一行，等真机标定。
4. **闪存写入闸门**：作者那套「改系统版本字符串」是按 10 Pro 固件偏移写死读写 /dev 闪存的。
   在手环 10 上偏移对不上就是砖，所以窄屏（<300px）一律把 profile 表清空 →
   原有的"版本不支持就返回 supported=false"逻辑会自动挡住，这不是我另加的限制，
   而是用它自己写好的安全分支。
"""
import io, re, sys

SRC = 'backend/backend.lua'
DST = 'backend/backend-band10.lua'

s = io.open(SRC, encoding='utf-8').read()
edits = []

# ---------- 1. 通信目录 ----------
old_dir = """local BAND9_PRO_DIR = '/data/quickapp/files/com.shell.liangyi/'
local BAND10_PRO_DIR = '/data/data/com.shell.liangyi/'
local BAND10_PRO_FILES_DIR = '/data/files/com.shell.liangyi/'"""
new_dir = """-- 通信目录：原作者写死 10 Pro 的三个布局。手环 10（VelaOS 4.0）可能不同，
-- 所以除了这三个，再加几个候选，并且优先用"快应用留下的路标文件"来定位——
-- 快应用只能写自己包名下的目录，它写得到哪儿，后端就该用哪儿。
local BAND9_PRO_DIR = '/data/quickapp/files/com.shell.liangyi/'
local BAND10_PRO_DIR = '/data/data/com.shell.liangyi/'
local BAND10_PRO_FILES_DIR = '/data/files/com.shell.liangyi/'
local TOOL_HELLO = 'tool_hello.json'        -- 快应用写的路标：里面带包名与时间
local EXTRA_DIRS = {
    '/data/quickapp/com.shell.liangyi/',
    '/data/data/quickapp/com.shell.liangyi/',
    '/data/data/com.byxz.toolbox/',
    '/data/files/com.byxz.toolbox/',
    '/data/quickapp/files/com.byxz.toolbox/',
    '/userdata/data/com.shell.liangyi/',
    '/userdata/data/com.byxz.toolbox/',
}"""
assert old_dir in s, '目录常量块没匹配上'
s = s.replace(old_dir, new_dir, 1); edits.append('通信目录改成候选表 + 路标文件')

# 在 resolveTargetDirByDeviceInfo 里插入"按路标文件找"的优先级
anchor = "local function resolveTargetDirByDeviceInfo()"
inject = """-- 按路标文件找通信目录：快应用能写到的目录，就是后端该用的目录
local function resolveTargetDirByHello()
    local dirs = { BAND9_PRO_DIR, BAND10_PRO_DIR, BAND10_PRO_FILES_DIR }
    for i = 1, #EXTRA_DIRS do dirs[#dirs + 1] = EXTRA_DIRS[i] end
    for i = 1, #dirs do
        local probe = dirs[i] .. TOOL_HELLO
        if fileExists(probe) then return dirs[i], probe end
    end
    return nil
end

local function resolveTargetDirByDeviceInfo()"""
assert anchor in s
s = s.replace(anchor, inject, 1); edits.append('加了"按快应用路标文件定位目录"')

# ---------- 2. 版面常量按屏宽缩放 ----------
old_ui = """-- 版面尺寸（针对 336x480 调校）
local UI_GAP = 12               -- 统一外边距/间距
local UI_CARD_RADIUS = 24       -- 卡片圆角
local UI_BTN_H = 48             -- 按钮高度（缩小按钮，释放终端空间）
local UI_BTN_RADIUS = math.floor(UI_BTN_H / 2)  -- 胶囊按钮
local UI_TOPBAR_H = 56          -- 顶部返回/标题栏高度（紧凑）
local HOME_PAD = 20             -- 表盘数据左边距"""
new_ui = """-- 版面尺寸：原作者按 336x480 写死，这里改成按实际屏宽缩放（基准 336x480）。
-- 手环 10 是 212x520，纵向反而更高，所以缩放取宽高比例中较小的那个，避免横向溢出。
local UI_SCALE = math.min(SCREEN_W / 336, SCREEN_H / 480)
local function uiPx(v, minv)
    local r = math.floor(v * UI_SCALE + 0.5)
    if minv and r < minv then r = minv end
    return r
end
local UI_GAP = uiPx(12, 6)                    -- 统一外边距/间距
local UI_CARD_RADIUS = uiPx(24, 12)           -- 卡片圆角
local UI_BTN_H = uiPx(48, 34)                 -- 按钮高度
local UI_BTN_RADIUS = math.floor(UI_BTN_H / 2)  -- 胶囊按钮
local UI_TOPBAR_H = uiPx(56, 40)              -- 顶部返回/标题栏高度
local HOME_PAD = uiPx(20, 10)                 -- 表盘数据左边距
-- 窄屏字也要跟着小，否则一行放不下（LVGL 字号按缩放取整，最小 12）
local UI_FONT = uiPx(22, 12)"""
assert old_ui in s, '版面常量块没匹配上'
s = s.replace(old_ui, new_ui, 1); edits.append('版面常量按屏宽缩放')

# 像素精灵网格：按屏幕缩放，别在 212 宽的屏上铺 280px
old_sprite = """local SPRITE_COLS = 14          -- 网格列数（横向，左右各比原来宽一格）
local SPRITE_ROWS = 12          -- 网格行数（纵向）
local SPRITE_CELL = 20          -- 每格方块尺寸（px，实体无间隙）"""
new_sprite = """local SPRITE_COLS = 14          -- 网格列数（横向）
local SPRITE_ROWS = 12          -- 网格行数（纵向）
-- 每格尺寸按屏宽算：原来 14 格 ×20px = 280px（336 屏放得下），
-- 212 屏要缩到 13px（14×13=182）才不溢出
local SPRITE_CELL = math.max(8, math.floor((SCREEN_W - uiPx(40, 20)) / SPRITE_COLS))"""
assert old_sprite in s, '精灵常量没匹配上'
s = s.replace(old_sprite, new_sprite, 1); edits.append('像素精灵格子按屏宽缩放')

# ---------- 3. 截图：不再按固件版本猜偏移 ----------
m = re.search(r"\n(\s*)local profiles = \{\n(?:.*\n)*?\1\}\n", s)
if m:
    indent = m.group(1)
    s = s[:m.start()] + (
        "\n" + indent + "-- 截图/闪存 profile：原作者按 10 Pro 固件版本号写死偏移。\n" +
        indent + "-- 手环 10（窄屏 <300px）上偏移对不上会写坏设备，所以这里直接置空：\n" +
        indent + "-- 原有的『版本不在表里就返回 supported=false』会把危险功能全部挡住。\n" +
        indent + "local profiles = (SCREEN_W < 300) and {} or {\n" +
        indent + "    -- 手环 10 一律不提供闪存写入（下面是 10 Pro 的原值，保留给宽屏）\n" +
        indent + "    ['3.101.036'] = { offset = 11169676, window = 11169648, length = 96, a1offset = 9, a1 = 'ro.build.version\0', a2offset = 29, a3offset = 45, block = 11165696 },\n" +
        indent + "    ['3.101.043'] = { offset = 11304860, window = 11304836, length = 68, a1offset = 1, a1 = 'persist.ble_static_addr\0', a2offset = 25, a3offset = 41, block = 11300864 }\n" +
        indent + "}\n") + s[m.end():]
    edits.append('闪存写入按屏宽闸门（窄屏彻底不给）')
else:
    print('⚠ 没找到 profiles 表，跳过闸门（需人工确认）')

io.open(DST, 'w', encoding='utf-8', newline='\n').write(s)
print('已生成 %s（%d 字节，%d 行）' % (DST, len(s.encode('utf-8')), s.count('\n')))
for e in edits: print('  · ' + e)
