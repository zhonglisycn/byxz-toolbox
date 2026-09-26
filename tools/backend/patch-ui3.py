# -*- coding: utf-8 -*-
"""后端界面第三轮修正：卡片重叠 + 标题位置错乱。

两处根因：
  ① `align = lvgl.ALIGN.CENTER` 是**相对父容器重新定位**，会覆盖我写的 x/y ——
     标题因此跑到屏幕底部（真机照片里那半个「后」字）。居中要用 `text_align`
     （只影响文字在自己的框里怎么摆），绝对坐标才不会被顶掉。
  ② 卡片 y 靠手算 `bar + GAP + 0.26*SH + GAP …` —— 一处改了没跟着改就重叠。
     改成**用一个 y 游标顺序往下排**，相邻卡片之间必定留出间距，算不出重叠。

用法：python tools/backend/patch-ui3.py
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


# ① 标题：去掉 align，改用 text_align（否则 x/y 被顶掉、标题乱跑）
rep("""    local tl = lvgl.Label(parent, {
        x = 0, y = HEAD_TOP + math.floor(h * 0.22), w = SW, h = math.floor(h * 0.56),
        text = title, text_font = lvgl.Font('MiSans-Regular', FONT_TITLE),
        text_color = C_TEXT, align = lvgl.ALIGN.CENTER, text_align = lvgl.ALIGN.CENTER,
    })""",
    """    -- 注意：这里**不能**写 align = lvgl.ALIGN.CENTER —— 那是相对父容器重新定位，
    -- 会把 x/y 顶掉（真机上一次标题跑到屏幕底部，就是它）。居中只用 text_align。
    local tl = lvgl.Label(parent, {
        x = 0, y = HEAD_TOP + math.floor(h * 0.22), w = SW, h = math.floor(h * 0.56),
        text = title, text_font = lvgl.Font('MiSans-Regular', FONT_TITLE),
        text_color = C_TEXT, text_align = lvgl.ALIGN.CENTER,
    })""", '标题去掉 align')

# ② 主页：改成 y 游标顺序排卡片（间距固定，不可能重叠）
rep("""    local clockCard = lvgl.Object(home, { x = PAD, y = bar + GAP, w = SW - PAD * 2,
        h = math.floor(SH * 0.26), radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })""",
    """    -- 用游标顺序往下排：每张卡片都从 cur 开始，排完 cur 前进「高 + 间距」，
    -- 这样相邻卡片必定隔开，改尺寸也不会算错重叠（照片里叠在一起就是这么来的）。
    local cur = bar + GAP
    local CLOCK_H = math.floor(SH * 0.22)
    local clockCard = lvgl.Object(home, { x = PAD, y = cur, w = SW - PAD * 2,
        h = CLOCK_H, radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })
    cur = cur + CLOCK_H + GAP""", '主页用游标')

rep("""    clockLabel = label(clockCard, '--:--', FONT_BIG, C_TEXT, 0, math.floor(SH * 0.04),
        SW - PAD * 2, math.floor(SH * 0.13))
    dateLabel = label(clockCard, '', FONT_SUB, C_DIM, 0, math.floor(SH * 0.175), SW - PAD * 2,
        math.floor(SH * 0.05))
    statLabel = label(clockCard, '', FONT_SUB, C_DIM, 0, math.floor(SH * 0.215), SW - PAD * 2,
        math.floor(SH * 0.04))""",
    """    clockLabel = label(clockCard, '--:--', FONT_BIG, C_TEXT, 0, math.floor(CLOCK_H * 0.06),
        SW - PAD * 2, math.floor(CLOCK_H * 0.50))
    dateLabel = label(clockCard, '', FONT_SUB, C_DIM, PAD, math.floor(CLOCK_H * 0.58),
        SW - PAD * 3, math.floor(CLOCK_H * 0.18))
    statLabel = label(clockCard, '', FONT_SUB, C_DIM, PAD, math.floor(CLOCK_H * 0.78),
        SW - PAD * 3, math.floor(CLOCK_H * 0.18))""", '主页卡片内文案按卡高算')

s = s.replace("""    local y = bar + GAP + math.floor(SH * 0.26) + GAP
    local b1 = card(home, '监控', 'CPU 与内存', PAD, y, SW - PAD * 2, BTN_H, function()
        showPage('monitor'); uiRefresh() end)
    y = y + BTN_H + GAP
    local b2 = card(home, '日志', '后端最近干了什么', PAD, y, SW - PAD * 2, BTN_H, function()
        showPage('log'); uiRefresh() end)
    y = y + BTN_H + GAP
    local b3 = card(home, '关于', VERSION, PAD, y, SW - PAD * 2, BTN_H, function()
        showPage('about'); uiRefresh() end)""",
    """    local b1 = card(home, '监控', 'CPU 与内存', PAD, cur, SW - PAD * 2, BTN_H, function()
        showPage('monitor'); uiRefresh() end)
    cur = cur + BTN_H + GAP
    local b2 = card(home, '日志', '后端最近干了什么', PAD, cur, SW - PAD * 2, BTN_H, function()
        showPage('log'); uiRefresh() end)
    cur = cur + BTN_H + GAP
    local b3 = card(home, '关于', VERSION, PAD, cur, SW - PAD * 2, BTN_H, function()
        showPage('about'); uiRefresh() end)""", 1)
done.append('主页三卡用游标')

# ③ 监控页 / 日志页 / 关于页：同样用游标，并且把卡片高度限制在屏幕内（表盘不能滚动）
rep("""    local mc = lvgl.Object(mon, { x = PAD, y = mbar + GAP, w = SW - PAD * 2,
        h = CARD_H, radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })""",
    """    local mcur = mbar + GAP
    local mc = lvgl.Object(mon, { x = PAD, y = mcur, w = SW - PAD * 2,
        h = CARD_H, radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })
    mcur = mcur + CARD_H + GAP""", '监控页游标')
rep("""    local mm = lvgl.Object(mon, { x = PAD, y = mbar + GAP + CARD_H + GAP, w = SW - PAD * 2,
        h = CARD_H, radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })""",
    """    local mm = lvgl.Object(mon, { x = PAD, y = mcur, w = SW - PAD * 2,
        h = CARD_H, radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })
    mcur = mcur + CARD_H + GAP""", '监控页内存卡')
rep("""    card(mon, '返回主页', '点一下回去', PAD, mbar + GAP + (CARD_H + GAP) * 2, SW - PAD * 2, BTN_H,
        function() showPage('home'); uiRefresh() end)""",
    """    card(mon, '返回主页', '点一下回去', PAD, mcur, SW - PAD * 2, BTN_H,
        function() showPage('home'); uiRefresh() end)""", '监控页返回卡')

# 日志/关于页：卡片高度按「顶栏往下到屏幕底部留 40px（下方半圆）」来算，避免超出屏幕
rep("""    local lc = lvgl.Object(log, { x = PAD, y = lbar + GAP, w = SW - PAD * 2,
        h = math.floor(SH * 0.60), radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })""",
    """    -- 表盘不能滚动，卡片必须落在屏幕内：底部留 46px 给下方半圆
    local BOTTOM_SAFE = math.max(40, math.floor(SH * 0.09))
    local ltop = lbar + GAP
    local lc = lvgl.Object(log, { x = PAD, y = ltop, w = SW - PAD * 2,
        h = math.max(120, SH - ltop - BOTTOM_SAFE), radius = RADIUS,
        bg_color = C_CARD, border_width = 0, pad_all = 0 })""", '日志卡限高')
rep("""    logLabel = label(lc, '', FONT_SUB, '#d6d6d6', PAD, math.floor(SH * 0.02), SW - PAD * 3,
        math.floor(SH * 0.56))""",
    """    logLabel = label(lc, '', FONT_SUB, '#d6d6d6', PAD, math.floor(SH * 0.02), SW - PAD * 3,
        math.max(100, SH - ltop - BOTTOM_SAFE - math.floor(SH * 0.04)))""", '日志文本限高')
rep("""    local ac = lvgl.Object(about, { x = PAD, y = abar + GAP, w = SW - PAD * 2,
        h = math.floor(SH * 0.58), radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })""",
    """    local atop = abar + GAP
    local ac = lvgl.Object(about, { x = PAD, y = atop, w = SW - PAD * 2,
        h = math.max(120, SH - atop - BOTTOM_SAFE), radius = RADIUS,
        bg_color = C_CARD, border_width = 0, pad_all = 0 })""", '关于卡限高')
rep("""    aboutLabel = label(ac, '', FONT_SUB, '#d6d6d6', PAD, math.floor(SH * 0.03), SW - PAD * 3,
        math.floor(SH * 0.52))""",
    """    aboutLabel = label(ac, '', FONT_SUB, '#d6d6d6', PAD, math.floor(SH * 0.03), SW - PAD * 3,
        math.max(100, SH - atop - BOTTOM_SAFE - math.floor(SH * 0.05)))""", '关于文本限高')

# ④ 卡片按钮矮一点，保证主页三张 + 时钟卡都在屏幕内
rep("""local BTN_H = math.max(44, math.floor(SH * 0.098))""",
    """local BTN_H = math.max(40, math.floor(SH * 0.088))""", '按钮高度收一点')

io.open(P, 'w', encoding='utf-8', newline='\n').write(s)
print('已应用 %d 处修正：' % len(done))
for d in done:
    print('  · ' + d)
