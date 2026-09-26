# -*- coding: utf-8 -*-
"""按参考实现重写后端界面。

参考对象是**原版 Shell++ 后端源码里实际写过的做法**（不是猜的）：
  · 卡片 = Object + 标题 Label(MiSans 26) + 副标题 Label(MiSans 18)，圆角大、深灰底
  · 顶部栏 = 左侧圆形返回按钮（makeRoundBack 那种「‹」）+ 居中标题
  · 配色 UI_BG #000000 / UI_CARD #262626 / UI_PRIMARY #0D6EFF / UI_DANGER #D93A2F
    / UI_TEXT #ffffff / UI_TERM_TEXT #d6d6d6 / UI_DIM #888888
  · 改文字一律 obj:set { text = ... }；对齐用 align = lvgl.ALIGN.XXX；字体 lvgl.Font('MiSans-Regular', n)
（米环管理 3.0 的容器头和 resource.bin 不一样，暂时解不出它的源码，所以这次照更近的参考来。）

用法：python tools/backend/patch-ui.py
"""
import io
import re

P = 'backend/toolbox-backend.lua'
s = io.open(P, encoding='utf-8').read()

start = s.index('-- ======================================================================\n-- 5. 界面')
end = s.index('-- ======================================================================\n-- 6. 目录定位与主循环')
old = s[start:end]

new = '''-- ======================================================================
-- 5. 界面：主页 / 监控 / 日志 / 关于（卡片式，照参考实现的版式）
--   配色与字号见文件头；所有文字用 MiSans（内置 Montserrat 没有汉字）
-- ======================================================================
local PAD = math.max(8, math.floor(SW * 0.055))
local GAP = math.max(6, math.floor(SW * 0.035))
local RADIUS = math.max(12, math.floor(SW * 0.075))
local FONT_BIG = math.max(34, math.floor(SW * 0.22))
local FONT_TITLE = math.max(15, math.floor(SW * 0.082))
local FONT_SUB = math.max(11, math.floor(SW * 0.055))
local CARD_H = math.max(58, math.floor(SH * 0.125))
local BTN_H = math.max(44, math.floor(SH * 0.098))

local C_BG = '#000000'
local C_CARD = '#262626'
local C_PRIMARY = '#0D6EFF'
local C_DANGER = '#D93A2F'
local C_TEXT = '#ffffff'
local C_DIM = '#a8a8a8'
local C_OK = '#54cc58'

local root, pages = nil, {}
local clockLabel, dateLabel, statLabel, monCpu, monMem, logLabel, aboutLabel, floatLayer, floatLabel
local curPage = 'home'
-- 前向声明：这两个在后面赋值，但上面的按钮回调要用（不声明的话调用会变成 nil 全局，真机报错）
local uiRefresh, uiRefreshFloat

local function label(parent, txt, size, color, x, y, w, h)
    local l = lvgl.Label(parent, {
        x = x, y = y, w = w, h = h, text = txt,
        text_font = lvgl.Font('MiSans-Regular', size), text_color = color,
    })
    l:add_flag(lvgl.FLAG.EVENT_BUBBLE)
    return l
end

-- 卡片：深灰底 + 圆角，第一行标题、第二行副标题（照参考实现的 makeCard）
local function card(parent, title, sub, x, y, w, h, onTap)
    local c = lvgl.Object(parent, {
        x = x, y = y, w = w, h = h, radius = RADIUS,
        bg_color = C_CARD, border_width = 0, pad_all = 0,
    })
    local t = label(c, title, FONT_TITLE, C_TEXT, PAD, math.floor(h * 0.16), w - PAD * 2, math.floor(h * 0.42))
    if sub and sub ~= '' then
        label(c, sub, FONT_SUB, C_DIM, PAD, math.floor(h * 0.60), w - PAD * 2, math.floor(h * 0.32))
    end
    if onTap then c:onevent(lvgl.EVENT.CLICKED, onTap) end
    return c, t
end

-- 顶部栏：左边圆形返回、中间标题（照参考实现的 makeRoundBack 那种）
local function topBar(parent, title, onBack)
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
end

local function makePage(name)
    local p = lvgl.Object(root, {
        x = 0, y = 0, w = SW, h = SH, bg_color = C_BG, border_width = 0, pad_all = 0,
    })
    p:add_flag(lvgl.FLAG.HIDDEN)
    pages[name] = p
    return p
end

local function showPage(name)
    for k, p in pairs(pages) do
        if k == name then p:clear_flag(lvgl.FLAG.HIDDEN) else p:add_flag(lvgl.FLAG.HIDDEN) end
    end
    curPage = name
end

local buildUI = function()
    root = lvgl.Object(nil, { x = 0, y = 0, w = SW, h = SH, bg_color = C_BG,
        border_width = 0, pad_all = 0 })
    root:clear_flag(lvgl.FLAG.SCROLLABLE)

    -- 主页
    local home = makePage('home')
    local bar = topBar(home, '工具箱', nil)
    local clockCard = lvgl.Object(home, { x = PAD, y = bar + GAP * 2, w = SW - PAD * 2,
        h = math.floor(SH * 0.26), radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })
    clockLabel = label(clockCard, '--:--', FONT_BIG, C_TEXT, 0, math.floor(SH * 0.04),
        SW - PAD * 2, math.floor(SH * 0.13))
    dateLabel = label(clockCard, '', FONT_SUB, C_DIM, 0, math.floor(SH * 0.175), SW - PAD * 2,
        math.floor(SH * 0.05))
    statLabel = label(clockCard, '', FONT_SUB, C_DIM, 0, math.floor(SH * 0.215), SW - PAD * 2,
        math.floor(SH * 0.04))

    local y = bar + GAP * 2 + math.floor(SH * 0.26) + GAP
    local b1 = card(home, '监控', 'CPU 与内存', PAD, y, SW - PAD * 2, BTN_H, function()
        showPage('monitor'); uiRefresh() end)
    y = y + BTN_H + GAP
    local b2 = card(home, '日志', '后端最近干了什么', PAD, y, SW - PAD * 2, BTN_H, function()
        showPage('log'); uiRefresh() end)
    y = y + BTN_H + GAP
    local b3 = card(home, '关于', VERSION, PAD, y, SW - PAD * 2, BTN_H, function()
        showPage('about'); uiRefresh() end)

    -- 监控页
    local mon = makePage('monitor')
    local mbar = topBar(mon, '监控', function() showPage('home'); uiRefresh() end)
    local mc = lvgl.Object(mon, { x = PAD, y = mbar + GAP * 2, w = SW - PAD * 2,
        h = CARD_H, radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })
    monCpu = label(mc, 'CPU —', FONT_TITLE, C_TEXT, PAD, math.floor(CARD_H * 0.12), SW - PAD * 2, math.floor(CARD_H * 0.45))
    label(mc, '负载 1/5/15 分钟', FONT_SUB, C_DIM, PAD, math.floor(CARD_H * 0.62), SW - PAD * 2, math.floor(CARD_H * 0.3))
    local mm = lvgl.Object(mon, { x = PAD, y = mbar + GAP * 2 + CARD_H + GAP, w = SW - PAD * 2,
        h = CARD_H, radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })
    monMem = label(mm, 'MEM —', FONT_TITLE, C_TEXT, PAD, math.floor(CARD_H * 0.12), SW - PAD * 2, math.floor(CARD_H * 0.45))
    label(mm, '取自 free 的 Umem', FONT_SUB, C_DIM, PAD, math.floor(CARD_H * 0.62), SW - PAD * 2, math.floor(CARD_H * 0.3))
    card(mon, '返回主页', '点一下回去', PAD, mbar + GAP * 2 + (CARD_H + GAP) * 2, SW - PAD * 2, BTN_H,
        function() showPage('home'); uiRefresh() end)

    -- 日志页
    local log = makePage('log')
    local lbar = topBar(log, '后端日志', function() showPage('home'); uiRefresh() end)
    local lc = lvgl.Object(log, { x = PAD, y = lbar + GAP * 2, w = SW - PAD * 2,
        h = math.floor(SH * 0.60), radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })
    logLabel = label(lc, '', FONT_SUB, '#d6d6d6', PAD, math.floor(SH * 0.02), SW - PAD * 3,
        math.floor(SH * 0.56))

    -- 关于页
    local about = makePage('about')
    local abar = topBar(about, '关于', function() showPage('home'); uiRefresh() end)
    local ac = lvgl.Object(about, { x = PAD, y = abar + GAP * 2, w = SW - PAD * 2,
        h = math.floor(SH * 0.58), radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })
    aboutLabel = label(ac, '', FONT_SUB, '#d6d6d6', PAD, math.floor(SH * 0.03), SW - PAD * 3,
        math.floor(SH * 0.52))

    -- 悬浮监控条：开了持续监控就浮在上面
    local fh = math.max(24, math.floor(SH * 0.05))
    floatLayer = lvgl.Object(root, { x = 0, y = math.floor(SH * 0.93), w = math.floor(SW * 0.62), h = fh,
        radius = math.floor(fh / 2), bg_color = C_CARD, border_width = 0, pad_all = 0 })
    floatLabel = label(floatLayer, '', FONT_SUB, C_OK, 4, math.floor(fh * 0.18),
        math.floor(SW * 0.62) - 8, math.floor(fh * 0.6))
    floatLayer:clear_flag(lvgl.FLAG.CLICKABLE)
    floatLayer:add_flag(lvgl.FLAG.HIDDEN)

    -- 建完必须把首页显示出来：每页默认 HIDDEN，忘了清就是"跑得好好的、屏幕全黑"
    showPage('home')
end

uiRefreshFloat = function()
    if not floatLayer then return end
    local txt = ''
    if stat.cpu.on then txt = stat.cpu.text end
    if stat.mem.on then txt = (txt == '' and stat.mem.text) or (txt .. '  ' .. stat.mem.text) end
    if txt == '' then
        floatLayer:add_flag(lvgl.FLAG.HIDDEN)
    else
        floatLayer:clear_flag(lvgl.FLAG.HIDDEN)
        floatLabel:set { text = txt }
    end
end

uiRefresh = function()
    local now = os.date('*t')
    if clockLabel then clockLabel:set { text = string.format('%02d:%02d', now.hour, now.min) } end
    if dateLabel then
        dateLabel:set { text = string.format('%d-%02d-%02d  %s', now.year, now.month, now.day,
            ({ '周日', '周一', '周二', '周三', '周四', '周五', '周六' })[now.wday] or '') }
    end
    if statLabel then
        statLabel:set { text = '已服务 ' .. stat.served .. ' 次 · ' .. stat.lastAction }
    end
    if monCpu or monMem then
        local l1, l5, l15, busy, csrc = readCpu()
        local total, used, avail, msrc = readMem()
        local pct = total > 0 and math.floor(used * 100 / total) or 0
        stat.cpu.load1, stat.cpu.busy = l1, busy
        stat.cpu.text = string.format('CPU %.2f / %d%%', l1, busy)
        stat.mem.percent = pct
        stat.mem.text = string.format('MEM %d%%', pct)
        if monCpu then monCpu:set { text = stat.cpu.text } end
        if monMem then
            monMem:set { text = string.format('MEM %d%%  %d/%d MB', pct,
                math.floor(used / 1048576), math.floor(total / 1048576)) }
        end
    end
    if logLabel then logLabel:set { text = table.concat(logLines, '\\n') } end
    if aboutLabel then
        aboutLabel:set { text = '版本 ' .. VERSION .. '\\n屏幕 ' .. SW .. 'x' .. SH
            .. '\\n目录 ' .. (TARGET ~= '' and TARGET or '未定位')
            .. '\\n\\n功能：命令 / 文件 / 监控 / 截图 / 应用 / 属性 / 进程 / 跑分 / 日志'
            .. '\\n\\n会改系统的动作需要 confirm，且不碰闪存。'
            .. '\\n\\n界面与协议参考原作者实现，在此致谢。' }
    end
    uiRefreshFloat()
end

'''

s = s[:start] + new + s[end:]
io.open(P, 'w', encoding='utf-8', newline='\n').write(s)
print('界面已重写：卡片式 + 顶部栏圆形返回 + 参考实现的配色与字号')
print('替换前 %d 行 → 替换后 %d 行' % (old.count('\n'), new.count('\n')))
