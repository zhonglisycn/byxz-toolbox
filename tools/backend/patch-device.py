# -*- coding: utf-8 -*-
"""按真机证据（NuttX）修正后端：行切分助手 / CPU 读 /proc/cpuload / 内存解析 free 的 Umem
   / 进程走 ps / 应用可隐藏删除 / 系统属性 getprop-setprop。

用法：python tools/backend/patch-device.py
（用脚本而不是 shell heredoc：heredoc 的转义把整段代码吃掉过两次。）"""
import io

P = 'backend/toolbox-backend.lua'
s = io.open(P, encoding='utf-8').read()
done = []


def rep(old, new, tag):
    global s
    assert old in s, '没匹配上：' + tag
    s = s.replace(old, new, 1)
    done.append(tag)


# ---------- ① 行切分助手（用 %c 类，模式串里不写转义换行）----------
rep("""local function addLog(line)""",
    """-- 按行切分。用 %c（控制字符）类，而不是在模式串里写转义换行——
-- 那样会把 Lua 字符串截断，报 unfinished string，真机上是黑屏（踩过两次）。
local function splitLines(text)
    local out = {}
    for line in (text or ''):gmatch('[^%c]+') do out[#out + 1] = line end
    return out
end

local function addLog(line)""", 'splitLines 助手')

# ---------- ② CPU：NuttX 的负载在 /proc/cpuload ----------
rep("""    local l1, l5, l15, busy, src = 0, 0, 0, 0, '读不到（loadavg/uptime/top 都没取到）'
    local load = readAll('/proc/loadavg', 256) or ''""",
    """    local l1, l5, l15, busy, src = 0, 0, 0, 0, '读不到（cpuload/loadavg/uptime/top 都没取到）'
    -- 这台是 NuttX：负载在 /proc/cpuload（它没有 Linux 的 /proc/loadavg）
    local cpload = readAll('/proc/cpuload', 512) or ''
    if cpload ~= '' then
        local nums = {}
        for v in cpload:gmatch('([%d%.]+)') do nums[#nums + 1] = tonumber(v) end
        if #nums >= 1 then
            l1 = nums[1]
            l5 = nums[2] or nums[1]
            l15 = nums[3] or nums[1]
            if #nums >= 4 then busy = math.floor(nums[4]) end
            return l1, l5, l15, busy, '/proc/cpuload', cpload
        end
    end
    local load = readAll('/proc/loadavg', 256) or ''""", 'CPU 读 /proc/cpuload')

# ---------- ③ 内存：解析 NuttX free 的 Umem ----------
rep("""    local out = runShell('free')
    local total, used, free = out:match('Mem:%s*(%d+)%s+(%d+)%s+(%d+)')
    if not total then
        local k, u, f = out:match('(%d+)%s+(%d+)%s+(%d+)')
        total, used, free = k, u, f
    end
    if total then
        total, used = tonumber(total), tonumber(used)
        return total, used, tonumber(free) or 0, 'free', out
    end""",
    """    local out = runShell('free')
    -- NuttX 的 free 分池打印（GImageCache / heaps / Kmem / Umem），要的是 Umem（用户内存）：
    -- 形如 "Umem: <total> <used> <free> <largest>"，数字常被终端折行，所以往下多看两行再收。
    local lines = splitLines(out)
    local total, used, free
    for i = 1, #lines do
        if lines[i]:match('^%s*Umem:') or lines[i]:match('^%s*Mem:') then
            local nums = {}
            local j = i
            while #nums < 4 and j <= math.min(i + 2, #lines) do
                for v in lines[j]:gmatch('(%d+)') do nums[#nums + 1] = tonumber(v) end
                j = j + 1
            end
            if #nums >= 2 then total, used, free = nums[1], nums[2], nums[3] or 0 end
            break
        end
    end
    if total then
        return total, used, free, 'free(Umem)', out
    end""", '内存解析 Umem')

# ---------- ④ 进程列表：优先 ps（NuttX 的 /proc/<pid> 没有 VmRSS）----------
rep("""    local limit = tonumber(req.limit) or 24
    local pids = runLines('ls -1 /proc')""",
    """    local limit = tonumber(req.limit) or 24
    -- 优先 ps：NuttX 的 /proc/<pid>/ 里没有 Linux 的 VmRSS，逐目录解析拿不到内存占用
    local ps = runLines('ps')
    if #ps > 1 then
        local rows = {}
        for i = 1, #ps do
            local pid, name, mem = ps[i]:match('^%s*(%d+)%s+(%S+)%s+(%d+)')
            if pid then rows[#rows + 1] = { pid = tonumber(pid), name = name, rssKb = tonumber(mem) or 0 } end
        end
        if #rows > 0 then
            table.sort(rows, function(a, b) return a.rssKb > b.rssKb end)
            while #rows > limit do table.remove(rows) end
            note('进程列表(ps)')
            return { status = 'ok', items = rows, count = #rows, source = 'ps' }
        end
    end
    local pids = runLines('ls -1 /proc')""", '进程走 ps')

# ---------- ⑤ 隐藏 / 删除应用：照原版改 apps.json ----------
rep("""        return { status = 'error', supported = false,
                 message = '为避免搞坏系统，本后端不执行应用改动；这一项请在系统设置里做' }
    end""",
    """        if req.package == nil or req.package == '' then return { status = 'error', message = '缺少 package' } end
        -- 照原版的做法：改系统的 apps.json，在「已装」与「已隐藏」两个列表之间搬；删除就是移出列表。
        -- 动手前先备份 .bak，出问题能还原。
        local roots = { '/data/quickapp/apps.json', '/data/apps.json', '/data/files/quickapp/apps.json' }
        for i = 1, #roots do
            local path = roots[i]
            local data = readJson(path)
            if type(data) == 'table' and type(data.InstalledApps) == 'table' then
                if type(data.HiddenApps) ~= 'table' then data.HiddenApps = {} end
                local moved = nil
                local keep = {}
                for j = 1, #data.InstalledApps do
                    local item = data.InstalledApps[j]
                    if type(item) == 'table' and tostring(item.package) == req.package then moved = item
                    else keep[#keep + 1] = item end
                end
                if action == 'delete' then
                    if not moved then return { status = 'error', message = '在列表里没找到这个应用' } end
                    data.InstalledApps = keep
                    runShell('rm -rf "/data/quickapp/' .. tostring(req.package) .. '"')
                    note('删除应用 ' .. tostring(req.package))
                elseif moved then
                    data.InstalledApps = keep
                    data.HiddenApps[#data.HiddenApps + 1] = moved
                    note('隐藏应用 ' .. tostring(req.package))
                else
                    local back = nil
                    local hk = {}
                    for j = 1, #data.HiddenApps do
                        local item = data.HiddenApps[j]
                        if type(item) == 'table' and tostring(item.package) == req.package then back = item
                        else hk[#hk + 1] = item end
                    end
                    if not back then return { status = 'error', message = '在隐藏列表里也没找到' } end
                    data.HiddenApps = hk
                    data.InstalledApps[#data.InstalledApps + 1] = back
                    note('恢复应用 ' .. tostring(req.package))
                end
                runShell('cp "' .. path .. '" "' .. path .. '.bak"')
                if writeAll(path, jsonEncode(data)) then
                    return { status = 'ok', file = path, package = req.package, action = action,
                             backup = path .. '.bak', message = '已改系统应用列表（备份在同目录 .bak）' }
                end
                return { status = 'error', message = '写不进 ' .. path .. '（没权限）' }
            end
        end
        return { status = 'error', message = '读不到系统的 apps.json（位置不确定，需要真机确认）' }
    end""", '应用隐藏/删除')

# ---------- ⑥ 系统属性：getprop / setprop（"侵入官方设置"）----------
rep("""    if action == 'get' then
        local key = req.property or ''""",
    """    if action == 'props' then
        -- 列出系统属性（NSH 有 getprop）。这是"看官方设置"的那一半，只读。
        local items = runLines('getprop')
        while #items > 80 do table.remove(items) end
        note('读系统属性')
        return { status = 'ok', items = items, count = #items }
    end
    if action == 'getprop' then
        local key = req.property or ''
        if key == '' then return { status = 'error', message = '缺少 property' } end
        local v = runShell('getprop "' .. key .. '"')
        note('读属性 ' .. key)
        return { status = 'ok', property = key, value = (v:gsub('%s+$', '')) }
    end
    if action == 'setprop' then
        local key = req.property or ''
        if key == '' then return { status = 'error', message = '缺少 property' } end
        if req.confirm ~= true then
            return { status = 'error', needConfirm = true, message = '改系统属性要带 confirm=true' }
        end
        local before = (runShell('getprop "' .. key .. '"')):gsub('%s+$', '')
        runShell('setprop "' .. key .. '" "' .. tostring(req.value or '') .. '"')
        local after = (runShell('getprop "' .. key .. '"')):gsub('%s+$', '')
        note('改属性 ' .. key)
        return { status = 'ok', property = key, before = before, after = after,
                 changed = before ~= after,
                 message = before == after and '值没变（可能被系统拒绝，或本来就是它）' or '已改' }
    end
    if action == 'get' then
        local key = req.property or ''""", '系统属性 getprop/setprop')

io.open(P, 'w', encoding='utf-8', newline='\n').write(s)
print('已应用 %d 处改动：' % len(done))
for d in done:
    print('  · ' + d)
