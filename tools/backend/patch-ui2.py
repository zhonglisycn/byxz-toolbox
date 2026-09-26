# -*- coding: utf-8 -*-
"""修正后端界面：顶栏重叠 + 起点落在胶囊屏半圆里。

两条规矩（在本工程的快应用里早就定过，写 Lua 界面时漏了）：
  1. 胶囊屏上下是半圆：全宽内容要 y ≥ 47（212 宽的屏），所以顶栏起点不能贴顶；
  2. 返回按钮在左、标题要居中（各自独立的框），不能放同一个 x —— 那样必然重叠。

用法：python tools/backend/patch-ui2.py
"""
import io

P = 'backend/toolbox-backend.lua'
s = io.open(P, encoding='utf-8').read()
done = []


def rep(old, new, tag):
    global s
    assert old in s, '没匹配上：' + tag
    s = s.replace(old, new, 1)
    done.append(tag)


# ① 顶栏：下移到平直区；按钮在左、标题单独一个整宽框并居中
rep("""-- 顶部栏：左边圆形返回、中间标题（照参考实现的 makeRoundBack 那种）""",
    """-- 顶部栏。两条硬规矩：
--   ① 胶囊屏上方是半圆，全宽内容要 y ≥ 47（212 屏），所以不能贴顶；
--   ② 返回按钮在左、标题放在**单独的整宽框里居中**，不能和按钮共用 x（共用必然重叠）。
local HEAD_TOP = math.max(46, math.floor(SH * 0.09))""", '顶栏常量')

rep("""local function topBar(parent, title, onBack)
    local h = math.max(34, math.floor(SH * 0.075))
    if onBack then
        local b = lvgl.Object(parent, {
            x = PAD, y = GAP, w = h, h = h, radius = math.floor(h / 2),
            bg_color = C_CARD, border_width = 0, pad_all = 0,
        })
        label(b, '<', math.floor(h * 0.55), C_TEXT, 0, math.floor(h * 0.22), h, math.floor(h * 0.5))
        b:onevent(lvgl.EVENT.CLICKED, onBack)
    end
    label(parent, title, FONT_TITLE, C_TEXT, PAD, GAP + math.floor(h * 0.26), SW - PAD * 2, math.floor(h * 0.5))
    return h
end""",
    """local function topBar(parent, title, onBack)
    local h = math.max(34, math.floor(SH * 0.075))
    if onBack then
        local b = lvgl.Object(parent, {
            x = PAD, y = HEAD_TOP, w = h, h = h, radius = math.floor(h / 2),
            bg_color = C_CARD, border_width = 0, pad_all = 0,
        })
        local bl = label(b, '<', math.floor(h * 0.55), C_TEXT, 0, math.floor(h * 0.22), h, math.floor(h * 0.5))
        bl:add_flag(lvgl.FLAG.EVENT_BUBBLE)
        b:onevent(lvgl.EVENT.CLICKED, onBack)
    end
    -- 标题：整屏宽的框 + 居中对齐 → 与左侧按钮天然错开
    local tl = lvgl.Label(parent, {
        x = 0, y = HEAD_TOP + math.floor(h * 0.22), w = SW, h = math.floor(h * 0.56),
        text = title, text_font = lvgl.Font('MiSans-Regular', FONT_TITLE),
        text_color = C_TEXT, align = lvgl.ALIGN.CENTER, text_align = lvgl.ALIGN.CENTER,
    })
    tl:add_flag(lvgl.FLAG.EVENT_BUBBLE)
    return HEAD_TOP + h
end""", '顶栏：居中标题 + 下移')

# ② 各页内容跟着新顶栏下移（主页时钟卡、监控、日志、关于）
rep("""    local clockCard = lvgl.Object(home, { x = PAD, y = bar + GAP * 2, w = SW - PAD * 2,""",
    """    local clockCard = lvgl.Object(home, { x = PAD, y = bar + GAP, w = SW - PAD * 2,""", '主页卡片下移')
rep("""    local y = bar + GAP * 2 + math.floor(SH * 0.26) + GAP""",
    """    local y = bar + GAP + math.floor(SH * 0.26) + GAP""", '主页按钮起点')
rep("""    local mc = lvgl.Object(mon, { x = PAD, y = mbar + GAP * 2, w = SW - PAD * 2,""",
    """    local mc = lvgl.Object(mon, { x = PAD, y = mbar + GAP, w = SW - PAD * 2,""", '监控卡下移')
rep("""    local mm = lvgl.Object(mon, { x = PAD, y = mbar + GAP * 2 + CARD_H + GAP, w = SW - PAD * 2,""",
    """    local mm = lvgl.Object(mon, { x = PAD, y = mbar + GAP + CARD_H + GAP, w = SW - PAD * 2,""", '内存卡下移')
rep("""    card(mon, '返回主页', '点一下回去', PAD, mbar + GAP * 2 + (CARD_H + GAP) * 2, SW - PAD * 2, BTN_H,""",
    """    card(mon, '返回主页', '点一下回去', PAD, mbar + GAP + (CARD_H + GAP) * 2, SW - PAD * 2, BTN_H,""", '返回卡下移')
rep("""    local lc = lvgl.Object(log, { x = PAD, y = lbar + GAP * 2, w = SW - PAD * 2,""",
    """    local lc = lvgl.Object(log, { x = PAD, y = lbar + GAP, w = SW - PAD * 2,""", '日志卡下移')
rep("""    local ac = lvgl.Object(about, { x = PAD, y = abar + GAP * 2, w = SW - PAD * 2,""",
    """    local ac = lvgl.Object(about, { x = PAD, y = abar + GAP, w = SW - PAD * 2,""", '关于卡下移')

# ③ 悬浮监控条：从 93%（落在下方半圆里）挪到 86%
rep("""    floatLayer = lvgl.Object(root, { x = 0, y = math.floor(SH * 0.93), w = math.floor(SW * 0.62), h = fh,""",
    """    -- 悬浮条也要让开下方半圆（下沿 y≈SH-47 才开始收），放到 86% 处
    floatLayer = lvgl.Object(root, { x = 0, y = math.floor(SH * 0.86), w = math.floor(SW * 0.62), h = fh,""", '悬浮条上移')

io.open(P, 'w', encoding='utf-8', newline='\n').write(s)
print('已应用 %d 处修正：' % len(done))
for d in done:
    print('  · ' + d)
