# -*- coding: utf-8 -*-
"""产出三档后端，便于逐步验证（黑屏要能定位到是哪一步造成的）。

  后端_原版.bin      · 零改动（回包自检与原文件字节一致）——已知能用的那版
  后端_只改目录.bin   · 只改通信目录发现（互通必需，不碰渲染）——先验这一档
  后端_目录+界面.bin  · 再加上界面缩放（只为让它的 LVGL 界面在 212 宽上好看，非必需）

用法：python tools/backend-port/build-variants.py
"""
import io, os, re, subprocess, sys

SRC_BIN = r'F:\xiazai\resource.bin'
LUA = 'backend/backend.lua'
OUT = 'release'

def dir_edits(s):
    """只改通信目录：候选表扩容 + 非 Pro 机型用实际目录。

    ⚠ 不能新增任何文件级 local —— 这个后端已经贴着 Lua 的 200 个 local 上限，
    多一个 `local` 整个 chunk 就编译不过（真机上表现为黑屏）。
    所以候选目录写成表里的元素、路标扫描内联进函数体。
    """
    old_dir = """local BAND9_PRO_DIR = '/data/quickapp/files/com.shell.liangyi/'
local BAND10_PRO_DIR = '/data/data/com.shell.liangyi/'
local BAND10_PRO_FILES_DIR = '/data/files/com.shell.liangyi/'"""
    new_dir = """local BAND9_PRO_DIR = '/data/quickapp/files/com.shell.liangyi/'
local BAND10_PRO_DIR = '/data/data/com.shell.liangyi/'
local BAND10_PRO_FILES_DIR = '/data/files/com.shell.liangyi/'
-- 手环 10（VelaOS 4.0）目录布局可能与 10 Pro 不同：下面的候选表里多列几个，
-- 用"快应用写得进哪个目录"作为最终依据（它只能写自己包名下的目录）。
-- 注意：这里不能新增文件级 local（本文件已贴着 Lua 的 200 个 local 上限）。"""
    assert old_dir in s, '目录常量没找到'
    s = s.replace(old_dir, new_dir, 1)

    old_cand = """    local candidates = {
        BAND9_PRO_DIR,         -- Band 9 Pro / Watch S4 / Watch S4 41mm
        BAND10_PRO_DIR,        -- Band 10 Pro
        BAND10_PRO_FILES_DIR,  -- Band 10 Pro fallback
    }"""
    new_cand = """    local candidates = {
        BAND9_PRO_DIR,         -- Band 9 Pro / Watch S4 / Watch S4 41mm
        BAND10_PRO_DIR,        -- Band 10 Pro
        BAND10_PRO_FILES_DIR,  -- Band 10 Pro fallback
        -- 手环 10 可能的布局（不新增 local，直接列在表里）
        '/data/quickapp/com.shell.liangyi/',
        '/data/data/quickapp/com.shell.liangyi/',
        '/userdata/data/com.shell.liangyi/',
        '/data/data/com.byxz.toolbox/',
        '/data/files/com.byxz.toolbox/',
        '/data/quickapp/files/com.byxz.toolbox/',
        '/userdata/data/com.byxz.toolbox/',
    }
    -- 路标文件优先：快应用启动会写 tool_hello.json，写在哪个目录就用哪个
    -- （内联扫描，不新增函数，避免碰到 local 上限）
    for i = 1, #candidates do
        if fileExists(candidates[i] .. 'tool_hello.json') then
            local probe = candidates[i]
            candidates = { probe }
            break
        end
    end"""
    assert old_cand in s, '候选表没找到'
    s = s.replace(old_cand, new_cand, 1)

    old_pick = """    elseif product == 'Xiaomi Smart Band 10 Pro' then
        if chosenDir ~= BAND10_PRO_FILES_DIR then
            chosenDir = BAND10_PRO_DIR
        end
    end"""
    new_pick = """    elseif product == 'Xiaomi Smart Band 10 Pro' then
        if chosenDir ~= BAND10_PRO_FILES_DIR then
            chosenDir = BAND10_PRO_DIR
        end
    else
        -- 手环 10 等非 Pro 机型：用读到 device_info.json 的那个目录，
        -- 不按 Pro 的布局硬拽（否则两个组件永远看不见对方）
        chosenDir = selected._sourceDir or chosenDir
    end"""
    assert old_pick in s, '设备分支没找到'
    s = s.replace(old_pick, new_pick, 1)
    return s

def ui_edits(s):
    """界面缩放：只为让它自己的 LVGL 界面适配 212 宽（可能与黑屏有关，单独一档）"""
    old_ui = """-- 版面尺寸（针对 336x480 调校）
local UI_GAP = 12               -- 统一外边距/间距
local UI_CARD_RADIUS = 24       -- 卡片圆角
local UI_BTN_H = 48             -- 按钮高度（缩小按钮，释放终端空间）
local UI_BTN_RADIUS = math.floor(UI_BTN_H / 2)  -- 胶囊按钮
local UI_TOPBAR_H = 56          -- 顶部返回/标题栏高度（紧凑）
local HOME_PAD = 20             -- 表盘数据左边距"""
    new_ui = """-- 版面尺寸：原作者按 336x480 写死；这里按实际屏宽缩放（基准 336x480）。
-- 手环 10 是 212x520，纵向更高，所以取宽高比例中较小的那个，避免横向溢出。
local UI_GAP = math.max(6, math.floor(12 * math.min(SCREEN_W / 336, SCREEN_H / 480) + 0.5))
local UI_CARD_RADIUS = math.max(12, math.floor(24 * math.min(SCREEN_W / 336, SCREEN_H / 480) + 0.5))
local UI_BTN_H = math.max(34, math.floor(48 * math.min(SCREEN_W / 336, SCREEN_H / 480) + 0.5))
local UI_BTN_RADIUS = math.floor(UI_BTN_H / 2)
local UI_TOPBAR_H = math.max(40, math.floor(56 * math.min(SCREEN_W / 336, SCREEN_H / 480) + 0.5))
local HOME_PAD = math.max(10, math.floor(20 * math.min(SCREEN_W / 336, SCREEN_H / 480) + 0.5))"""
    assert old_ui in s, '版面常量没找到'
    s = s.replace(old_ui, new_ui, 1)

    old_sprite = """local SPRITE_COLS = 14          -- 网格列数（横向，左右各比原来宽一格）
local SPRITE_ROWS = 12          -- 网格行数（纵向）
local SPRITE_CELL = 20          -- 每格方块尺寸（px，实体无间隙）"""
    new_sprite = """local SPRITE_COLS = 14
local SPRITE_ROWS = 12
-- 原来 14 格 ×20px = 280px（336 屏放得下），212 屏要缩到 13px 才不溢出
local SPRITE_CELL = math.max(8, math.floor((SCREEN_W - 40) / SPRITE_COLS))"""
    assert old_sprite in s, '精灵常量没找到'
    s = s.replace(old_sprite, new_sprite, 1)
    return s

def safety_edits(s):
    """闪存写入闸门：窄屏不提供（用它自己的 supported=false 分支挡住）"""
    m = re.search(r"\n(\s*)local profiles = \{\n(?:.*\n)*?\1\}\n", s)
    if not m:
        print('⚠ 没找到 profiles 表，跳过安全闸门')
        return s
    ind = m.group(1)
    block = ("\n" + ind + "-- 闪存 profile：原作者按 10 Pro 固件版本号写死偏移；\n" +
             ind + "-- 手环 10 上偏移对不上会写坏设备，窄屏一律置空（走它自带的 supported=false 分支）\n" +
             ind + "local profiles = (SCREEN_W < 300) and {} or {\n" +
             ind + "    ['3.101.036'] = { offset = 11169676, window = 11169648, length = 96, a1offset = 9, a1 = 'ro.build.version\0', a2offset = 29, a3offset = 45, block = 11165696 },\n" +
             ind + "    ['3.101.043'] = { offset = 11304860, window = 11304836, length = 68, a1offset = 1, a1 = 'persist.ble_static_addr\0', a2offset = 25, a3offset = 41, block = 11300864 }\n" +
             ind + "}\n")
    return s[:m.start()] + block + s[m.end():]

base = io.open(LUA, encoding='utf-8').read()
variants = [
    ('后端_原版.bin', base, '零改动'),
    ('后端_只改目录.bin', dir_edits(base), '只改通信目录发现'),
]
s_all = safety_edits(ui_edits(dir_edits(base)))
variants.append(('后端_目录+界面.bin', s_all, '目录 + 界面缩放 + 闪存闸门'))

os.makedirs(OUT, exist_ok=True)
for name, body, desc in variants:
    tmp = 'backend/_variant.lua'
    io.open(tmp, 'w', encoding='utf-8', newline='\n').write(body)
    subprocess.check_call([sys.executable, 'tools/backend-port/pack-luavgl.py', SRC_BIN, tmp,
                           os.path.join(OUT, name)], stdout=subprocess.DEVNULL)
    print('%-22s %-28s %8d 字节  Lua %d 字节' % (name, desc, os.path.getsize(os.path.join(OUT, name)), len(body.encode('utf-8'))))
os.remove('backend/_variant.lua')

# 自检：原版回包必须与原文件字节一致
a = io.open(SRC_BIN, 'rb').read()
b = io.open(os.path.join(OUT, '后端_原版.bin'), 'rb').read()
print('\n原版回包与原文件字节一致:', a == b)

# ---- 出厂前必须过 Lua 语法体检 ----
# 这个后端的 Lua 贴着 200 个文件级 local 的上限，多一个 local 就整个 chunk 编译不过
# （真机上表现为黑屏、看不到任何报错）。所以每次打包都跑一遍 fengari 编译检查。
print()
bad = subprocess.call([sys.executable, '-c', 'pass'])  # 占位，保持退出码语义清晰
rc = subprocess.call(['node', 'tools/backend-port/check-lua.mjs'] +
                     [os.path.join(OUT, n) for n, _, _ in variants])
if rc != 0:
    print('❌ 有变体没过 Lua 语法检查，别拿去装——先修语法')
    sys.exit(1)
print('✅ 三个变体 Lua 语法全部通过（fengari / Lua 5.3）')
