-- toolbox-backend.lua —— 手环工具箱的「表盘位 Lua 后端」（我们自己的完整重构）
--
-- 定位：界面与操作在快应用那边，这里负责**该在表盘位干的活**——
-- 用设备自带 NSH 跑命令、读 /proc 看负载与内存、dd 读 /dev/fb0 截图、浏览文件，
-- 并且自己就是一块表盘（时钟 + 多页状态界面 + 悬浮监控）。
--
-- 与快应用之间用请求/结果 JSON 文件通信（协议见 docs/backend-protocol.md）：
-- 每个请求带 guard 令牌与自增 seq，结果回带同一个 seq 配对。
--
-- 致谢：协议与原始实现来自 Shell++（com.shell.liangyi）的作者；本文件是照其行为重写的完整版。
--
-- 两条自己定的红线：
--   ① 不碰设备闪存（原版按固件偏移改系统版本字符串那套，换机型就是砖）；
--   ② 会伤到系统的动作（重启、隐藏/删除快应用、写系统文件）默认拒绝，
--      必须请求里额外带 confirm = true 才执行，并且结果里如实标注。
--   界面尺寸全部按 lvgl.HOR_RES()/VER_RES() 算，不写死机型。

local SW = lvgl.HOR_RES()
local SH = lvgl.VER_RES()

local VERSION = 'byxz-toolbox-backend 0.2.0'
local OUT_LIMIT = 32768
local LOG_KEEP = 12                          -- 终端页保留最近几条

-- ======================================================================
-- 0. 常量
-- ======================================================================
local DIRS = {
    -- 快应用写的是 internal://files/xxx，对应的真实目录随系统版本不同，多列几种
    '/data/data/com.byxz.toolbox/files/',
    '/data/files/com.byxz.toolbox/files/',
    '/data/quickapp/files/com.byxz.toolbox/files/',
    '/data/data/com.byxz.toolbox/',
    '/data/files/com.byxz.toolbox/',
    '/data/quickapp/files/com.byxz.toolbox/',
    '/data/quickapp/com.byxz.toolbox/',
    '/data/data/com.shell.liangyi/',         -- 与原版包名并存时也能用
    '/data/files/com.shell.liangyi/',
    '/data/quickapp/files/com.shell.liangyi/',
}
local TARGET = ''
local guardToken = ''
local guardSeq = 0

-- 运行状态
local stat = {
    served = 0, lastAction = '等待快应用', startedAt = os.time(),
    cpu = { on = false, load1 = 0, busy = 0, text = 'CPU —' },
    mem = { on = false, percent = 0, text = 'MEM —' },
    shot = { bytes = 0, path = '' },
}
local logLines = {}

-- ======================================================================
-- 1. JSON（自带：运行时不保证有 json 库）
-- ======================================================================
local function jsonEncode(v)
    local t = type(v)
    if v == nil then return 'null' end
    if t == 'boolean' then return v and 'true' or 'false' end
    if t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return 'null' end
        if math.floor(v) == v and math.abs(v) < 1e15 then return string.format('%d', v) end
        return string.format('%.6g', v)
    end
    if t == 'string' then
        local out = v:gsub('[%z\1-\31\\"]', function(c)
            local map = { ['\\'] = '\\\\', ['"'] = '\\"', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
            return map[c] or string.format('\\u%04x', c:byte())
        end)
        return '"' .. out .. '"'
    end
    if t == 'table' then
        local n = #v
        if n > 0 then
            local parts = {}
            for i = 1, n do parts[i] = jsonEncode(v[i]) end
            return '[' .. table.concat(parts, ',') .. ']'
        end
        local parts = {}
        for k, val in pairs(v) do
            if type(k) == 'string' or type(k) == 'number' then
                parts[#parts + 1] = jsonEncode(tostring(k)) .. ':' .. jsonEncode(val)
            end
        end
        if #parts == 0 then return '{}' end
        return '{' .. table.concat(parts, ',') .. '}'
    end
    return 'null'
end

local function jsonDecode(text)
    local pos, len = 1, #text
    local parseValue
    local function skipWS()
        while pos <= len do
            local c = text:sub(pos, pos)
            if c == ' ' or c == '\t' or c == '\n' or c == '\r' then pos = pos + 1 else break end
        end
    end
    local function parseString()
        pos = pos + 1
        local buf = {}
        while pos <= len do
            local c = text:sub(pos, pos)
            if c == '"' then pos = pos + 1; return table.concat(buf) end
            if c == '\\' then
                local e = text:sub(pos + 1, pos + 1)
                local map = { n = '\n', t = '\t', r = '\r', b = '\b', f = '\f', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }
                if map[e] then buf[#buf + 1] = map[e]; pos = pos + 2
                elseif e == 'u' then
                    local code = tonumber(text:sub(pos + 2, pos + 5), 16) or 63
                    buf[#buf + 1] = string.char(code % 256); pos = pos + 6
                else pos = pos + 2 end
            else buf[#buf + 1] = c; pos = pos + 1 end
        end
        return table.concat(buf)
    end
    local function parseNumber()
        local s = pos
        while pos <= len and text:sub(pos, pos):match('[%d%.eE%+%-]') do pos = pos + 1 end
        return tonumber(text:sub(s, pos - 1)) or 0
    end
    local function parseArray()
        pos = pos + 1
        local arr = {}
        skipWS()
        if text:sub(pos, pos) == ']' then pos = pos + 1; return arr end
        while pos <= len do
            arr[#arr + 1] = parseValue()
            skipWS()
            local c = text:sub(pos, pos)
            if c == ',' then pos = pos + 1; skipWS()
            elseif c == ']' then pos = pos + 1; return arr
            else return arr end
        end
        return arr
    end
    local function parseObject()
        pos = pos + 1
        local obj = {}
        skipWS()
        if text:sub(pos, pos) == '}' then pos = pos + 1; return obj end
        while pos <= len do
            skipWS()
            if text:sub(pos, pos) ~= '"' then return obj end
            local k = parseString()
            skipWS()
            if text:sub(pos, pos) == ':' then pos = pos + 1 end
            obj[k] = parseValue()
            skipWS()
            local c = text:sub(pos, pos)
            if c == ',' then pos = pos + 1
            elseif c == '}' then pos = pos + 1; return obj
            else return obj end
        end
        return obj
    end
    parseValue = function()
        skipWS()
        local c = text:sub(pos, pos)
        if c == '{' then return parseObject() end
        if c == '[' then return parseArray() end
        if c == '"' then return parseString() end
        if c == 't' then pos = pos + 4; return true end
        if c == 'f' then pos = pos + 5; return false end
        if c == 'n' then pos = pos + 4; return nil end
        return parseNumber()
    end
    local ok, res = pcall(parseValue)
    if not ok then return nil end
    return res
end

-- ======================================================================
-- 2. 文件与命令
-- ======================================================================
local function readAll(path, limit)
    local f = io.open(path, 'r')
    if not f then return nil end
    local data = f:read(limit or 65536)
    f:close()
    return data
end

local function writeAll(path, text)
    local f = io.open(path, 'w')
    if not f then return false end
    f:write(text)
    f:close()
    return true
end

local function fileSize(path)
    local f = io.open(path, 'r')
    if not f then return -1 end
    local n = f:seek('end') or 0
    f:close()
    return n
end

local function exists(path)
    local f = io.open(path, 'r')
    if f then f:close(); return true end
    return false
end

local function isDir(path)
    return exists(path .. '/.')
end

local function readJson(path)
    local s = readAll(path, 262144)
    if not s or s == '' then return nil end
    return jsonDecode(s)
end

local function writeJsonAtomic(name, data)
    if TARGET == '' then return false end
    local tmp = TARGET .. '.' .. name .. '.tmp'
    local dst = TARGET .. name
    if not writeAll(tmp, jsonEncode(data)) then return false end
    os.remove(dst)
    pcall(os.execute, 'mv "' .. tmp .. '" "' .. dst .. '"')
    return true
end

-- NSH 只支持 '>' 重定向 stdout（写 2> 会让整行解析失败、命令根本不执行）
local function runShell(cmd)
    local outFile = '/tmp/toolbox_cmd_out.txt'
    os.remove(outFile)
    pcall(os.execute, cmd .. ' > "' .. outFile .. '"')
    local out = readAll(outFile, OUT_LIMIT + 4096) or ''
    os.remove(outFile)
    local truncated = #out > OUT_LIMIT
    if truncated then out = out:sub(1, OUT_LIMIT) end
    return out, truncated
end

local function runLines(cmd)
    local out = runShell(cmd)
    local list = {}
    for line in out:gmatch('[^\r\n]+') do
        line = line:gsub('^%s+', ''):gsub('%s+$', '')
        if line ~= '' then list[#list + 1] = line end
    end
    return list
end

-- 按行切分。用 %c（控制字符）类，而不是在模式串里写转义换行——
-- 那样会把 Lua 字符串截断，报 unfinished string，真机上是黑屏（踩过两次）。
local function splitLines(text)
    local out = {}
    for line in (text or ''):gmatch('[^%c]+') do out[#out + 1] = line end
    return out
end

local function addLog(line)
    logLines[#logLines + 1] = os.date('%H:%M') .. ' ' .. line
    while #logLines > LOG_KEEP do table.remove(logLines, 1) end
end

local function note(action)
    stat.served = stat.served + 1
    stat.lastAction = action
    addLog(action)
end

-- ======================================================================
-- 3. 安全令牌
-- ======================================================================
local function rotateGuard()
    guardSeq = guardSeq + 1
    local rnd = ''
    for _ = 1, 8 do rnd = rnd .. string.format('%x', math.random(0, 15)) end
    guardToken = tostring(os.time()) .. '-' .. rnd
    writeJsonAtomic('ipc_guard.json', {
        type = 'ipc_guard', seq = guardSeq, token = guardToken,
        backend = VERSION, timestamp = os.date('%H:%M:%S'),
    })
end

-- ======================================================================
-- 4. 功能：命令 / 文件 / 监控 / 截图 / 应用 / 缓存 / 跑分
-- ======================================================================
local function doCmd(req)
    if not req.cmd or req.cmd == '' then return { status = 'error', message = '命令为空' } end
    local out, truncated = runShell(req.cmd)
    note('命令 ' .. req.cmd:sub(1, 16))
    return { status = 'ok', stdout = out, truncated = truncated, cmd = req.cmd }
end

local FILE_GUARD = { delete = true, write = true, copy = true, move = true }

local function doFile(req)
    local path = req.path or ''
    if path == '' then return { status = 'error', message = '路径为空' } end

    -- 会改文件系统的动作：默认只读，必须 confirm = true
    if FILE_GUARD[req.action] and req.confirm ~= true then
        return { status = 'error', needConfirm = true,
                 message = '这个动作会改文件（' .. tostring(req.action) .. '），请带 confirm=true 再试' }
    end

    if req.action == 'text' then
        local s = readAll(path, 131072)
        if not s then return { status = 'error', message = '读不到（不存在或没权限）' } end
        return { status = 'ok', path = path, text = s, bytes = #s }
    end

    if req.action == 'info' then
        if not exists(path) then return { status = 'error', message = '不存在' } end
        return { status = 'ok', path = path, bytes = fileSize(path), isDir = isDir(path) }
    end

    if req.action == 'hex' then
        local s = readAll(path, 4096)
        if not s then return { status = 'error', message = '读不到' } end
        local hex, asc = {}, {}
        for i = 1, math.min(#s, tonumber(req.length) or 256) do
            local b = s:byte(i)
            hex[#hex + 1] = string.format('%02X', b)
            asc[#asc + 1] = (b >= 32 and b < 127) and string.char(b) or '.'
        end
        note('十六进制 ' .. path:sub(-12))
        return { status = 'ok', path = path, hex = table.concat(hex, ' '), ascii = table.concat(asc), bytes = #s }
    end

    if req.action == 'delete' then
        local out = runShell('rm -rf "' .. path .. '"')
        note('删除 ' .. path:sub(-14))
        return { status = exists(path) and 'error' or 'ok', path = path, stdout = out }
    end

    if req.action == 'copy' or req.action == 'move' then
        local dest = req.dest or ''
        if dest == '' then return { status = 'error', message = '缺少 dest' } end
        runShell((req.action == 'copy' and 'cp -r "' or 'mv "') .. path .. '" "' .. dest .. '"')
        note((req.action == 'copy' and '复制 ' or '移动 ') .. path:sub(-12))
        return { status = exists(dest) and 'ok' or 'error', path = path, dest = dest }
    end

    if req.action == 'search' then
        -- 递归找“哪个文件里有这个字串”。限深度/文件数/单文件读取量，避免把设备拖死。
        local needle = tostring(req.needle or '')
        if needle == '' then return { status = 'error', message = '要搜的内容为空' } end
        local root = req.path or '/data'
        local maxDepth = tonumber(req.depth) or 4
        local maxFiles = tonumber(req.limit) or 200
        local maxRead = 8192
        local hits, scanned = {}, 0
        -- 后端没有 listDir 助手，列目录走 shell（NSH 只认 >，不能写 2>）
        local function namesOf(dir)
            local raw = runShell('ls -1 "' .. dir .. '"')
            if not raw or raw == '' then return nil end
            return splitLines(raw)
        end
        local visit
        visit = function(dir, depth)
            if depth > maxDepth or scanned >= maxFiles or #hits >= 50 then return end
            local names = namesOf(dir)
            if not names then return end
            for _, nm in ipairs(names) do
                if scanned >= maxFiles or #hits >= 50 then return end
                local full = (dir == '/' and '/' or (dir .. '/')) .. nm
                if isDir(full) then
                    if nm ~= '.' and nm ~= '..' then visit(full, depth + 1) end
                else
                    scanned = scanned + 1
                    local body = readAll(full, maxRead)
                    if body and body:find(needle, 1, true) then
                        local line = 1
                        for seg in body:gmatch('[^%c]+') do
                            if seg:find(needle, 1, true) then
                                hits[#hits + 1] = { path = full, line = line, text = seg:sub(1, 80) }
                                break
                            end
                            line = line + 1
                        end
                    end
                end
            end
        end
        visit(root, 1)
        note('搜索 ' .. needle:sub(1, 12))
        return { status = 'ok', needle = needle, root = root, scanned = scanned, items = hits }
    end

    if req.action == 'write' then
        if not writeAll(path, req.content or '') then
            return { status = 'error', message = '写不进去（目录不存在或没权限）' }
        end
        note('写入 ' .. path:sub(-12))
        return { status = 'ok', path = path, bytes = fileSize(path) }
    end

    -- 默认 list
    local items = runLines('ls -1 "' .. path .. '"')
    local raw = ''
    if #items == 0 then
        raw = runShell('ls "' .. path .. '"')
        for line in raw:gmatch('[^\r\n]+') do
            for name in line:gmatch('%S+') do items[#items + 1] = name end
        end
    end
    local out = {}
    for i = 1, #items do out[i] = items[i] end
    note('列目录 ' .. path:sub(-12))
    local res = { status = 'ok', action = 'list', path = path, items = out, count = #out }
    if #out == 0 then res.raw = raw end
    return res
end

local function readCpu()
    local l1, l5, l15, busy, src = 0, 0, 0, 0, '读不到（cpuload/loadavg/uptime/top 都没取到）'
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
    local load = readAll('/proc/loadavg', 256) or ''
    local a, b, c = load:match('([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)')
    if a then
        l1, l5, l15, src = tonumber(a), tonumber(b), tonumber(c), '/proc/loadavg'
    else
        local up = runShell('uptime')
        local m = up:match('load average[s]?:%s*([%d%.]+),?%s*([%d%.]+),?%s*([%d%.]+)')
        if m then l1, l5, l15, src = tonumber(m), tonumber(m), tonumber(m), 'uptime'
            l1 = tonumber(m) end
        if not m then
            local top = runShell('top -n 1')
            local pct = top:match('(%d+)%%')
            if pct then busy = tonumber(pct); src = 'top' end
        end
    end
    local stat_line = (readAll('/proc/stat', 4096) or ''):match('cpu%s+([^\r\n]+)')
    if stat_line then
        local idle, total = 0, 0
        local i = 0
        for v in stat_line:gmatch('%d+') do
            i = i + 1
            total = total + tonumber(v)
            if i == 4 then idle = tonumber(v) end
        end
        if total > 0 then busy = math.floor((total - idle) * 100 / total) end
    end
    return l1 or 0, l5 or 0, l15 or 0, busy, src, (l1 or 0) == 0 and busy == 0 and runShell('top -n 1') or ''
end

local function readMem()
    -- 这台设备是 NuttX，procfs 里不一定有 meminfo，所以先试 NSH 的 free（原版也是这么取的）
    local out = runShell('free')
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
    end
    local s2 = readAll('/proc/meminfo', 8192) or ''
    local function kb(key) return tonumber(s2:match(key .. ':%s*(%d+)')) or 0 end
    local t2 = kb('MemTotal')
    if t2 > 0 then
        local avail = kb('MemAvailable')
        if avail == 0 then avail = kb('MemFree') end
        return t2, t2 - avail, avail, '/proc/meminfo', s2
    end
    return 0, 0, 0, '读不到（free 与 /proc 都没有）', out
end

-- 进程列表：/proc 下的数字目录 + cmdline（自解析，不依赖 ps/top 是否存在）
local function doProcList(req)
    local limit = tonumber(req.limit) or 24
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
    local pids = runLines('ls -1 /proc')
    local rows = {}
    for i = 1, #pids do
        local pid = pids[i]
        if pid:match('^%d+$') then
            local cmd = (readAll('/proc/' .. pid .. '/cmdline', 256) or ''):gsub('%z', ' ')
            local state = readAll('/proc/' .. pid .. '/stat', 512) or ''
            local name = state:match('^%d+ %((.-)%)')
            local rss = 0
            local status = readAll('/proc/' .. pid .. '/status', 2048) or ''
            rss = tonumber(status:match('VmRSS:%s*(%d+)')) or 0
            if cmd == '' then cmd = name or '' end
            cmd = cmd:gsub('^%s+', '')
            if cmd ~= '' then
                rows[#rows + 1] = { pid = tonumber(pid), name = cmd:sub(1, 40), rssKb = rss }
            end
        end
    end
    table.sort(rows, function(a, b) return a.rssKb > b.rssKb end)
    while #rows > limit do table.remove(rows) end
    note('进程列表')
    return { status = 'ok', items = rows, count = #rows }
end

local function doMonitor(kind, req)
    local action = req.action or 'status'
    local slot = (kind == 'cpu') and stat.cpu or stat.mem
    if action == 'monitor_start' then
        slot.on = true
        if kind == 'cpu' then
            local l1, l5, l15, busy, csrc, craw = readCpu()
            stat.cpu.load1, stat.cpu.busy = l1, busy
            stat.cpu.text = string.format('CPU %.2f / %d%%', l1, busy)
        else
            local total, used, avail, msrc, mraw = readMem()
            stat.mem.percent = total > 0 and math.floor(used * 100 / total) or 0
            stat.mem.text = string.format('MEM %d%%', stat.mem.percent)
        end
        note(kind .. ' 监控开始')
        if uiRefreshFloat then pcall(uiRefreshFloat) end
        return { status = 'ok', running = true, text = slot.text }
    end
    if action == 'monitor_stop' then
        slot.on = false
        note(kind .. ' 监控停止')
        if uiRefreshFloat then pcall(uiRefreshFloat) end
        return { status = 'ok', running = false }
    end
    if action == 'clear' then
        logLines = {}
        return { status = 'ok', message = '日志已清空' }
    end
    if action == 'log' then
        return { status = 'ok', lines = logLines, served = stat.served, backend = VERSION }
    end
    -- status（默认）
    if kind == 'cpu' then
        local l1, l5, l15, busy, csrc, craw = readCpu()
        stat.cpu.load1, stat.cpu.busy = l1, busy
        stat.cpu.text = string.format('CPU %.2f / %d%%', l1, busy)
        return { status = 'ok', running = stat.cpu.on, load1 = l1, load5 = l5, load15 = l15,
                 busyPercent = busy, text = stat.cpu.text, source = csrc or '',
                 raw = ((l1 or 0) == 0 and busy == 0) and string.sub(craw or '', 1, 400) or '' }
    end
    local total, used, avail, msrc, mraw = readMem()
    stat.mem.percent = total > 0 and math.floor(used * 100 / total) or 0
    stat.mem.text = string.format('MEM %d%%', stat.mem.percent)
    return { status = 'ok', running = stat.mem.on, totalKb = total, usedKb = used, freeKb = avail,
             usedPercent = stat.mem.percent, text = stat.mem.text, source = msrc or '',
             raw = (total == 0) and string.sub(mraw or '', 1, 400) or '' }
end

local function shotConfig()
    local cfg = readJson(TARGET .. 'screenshot.conf.json') or {}
    local bpp = tonumber(cfg.bpp) or 3
    local skip = cfg.skipRows
    if skip == nil then skip = SH end
    return { bpp = bpp, skip = tonumber(skip) or 0 }
end

local function doScreenshot(req)
    local cfg = shotConfig()
    local dir = TARGET .. 'screenshots/'
    pcall(os.execute, 'mkdir -p "' .. dir .. '"')
    local name = (req.dest ~= nil and req.dest ~= '') and req.dest or ('shot_' .. tostring(os.time()) .. '.raw')
    local path = dir .. name
    local stride = SW * cfg.bpp
    os.remove(path)
    runShell('dd if=/dev/fb0 of="' .. path .. '" bs=' .. stride .. ' skip=' .. cfg.skip .. ' count=' .. SH)
    local sz = fileSize(path)
    stat.shot.bytes = sz > 0 and sz or 0
    stat.shot.path = path
    note(sz > 0 and ('截图 ' .. name) or '截图失败')
    return {
        status = sz > 0 and 'ok' or 'error', path = path, bytes = sz > 0 and sz or 0,
        expectBytes = stride * SH, strideBytes = stride, skipRows = cfg.skip, bpp = cfg.bpp,
        message = sz > 0 and '' or '抓不到帧缓冲（参数需要标定：screenshot.conf.json 里改 bpp/skipRows）',
    }
end

-- 已装快应用列表：读系统的 apps.json（原本也用这个文件）
local function doAppManager(req)
    local action = req.action or 'apps'
    if action == 'apps' then
        -- 真实 apps.json 是 {InstalledApps = {...}, HiddenApps = {...}}；也兼容"包名 -> 应用"的扁平写法。
        -- 路径按候选表找；都不行就扫一遍 /data 的下一层，并把目录摊开返回，便于定位真实位置。
        local cands = { '/data/quickapp/apps.json', '/data/apps.json', '/data/files/quickapp/apps.json',
                        '/data/quickapp/files/apps.json', '/data/data/quickapp/apps.json' }
        local tried = {}
        local keys = {}
        local function listOf(data)
            local items = {}
            if type(data) ~= 'table' then return nil end
            -- 字段名兼容：不同固件/版本的 apps.json 用过 package / pkg / name / bundleName / id …
            local function firstOf(t, keys)
                for i = 1, #keys do
                    local x = t[keys[i]]
                    if type(x) == 'string' and x ~= '' then return x end
                end
                return nil
            end
            local function addOne(v, forced)
                if type(v) ~= 'table' then return end
                local pkg = firstOf(v, { 'package', 'pkg', 'bundleName', 'bundle', 'id', 'name' })
                if pkg == nil then return end
                local nm = firstOf(v, { 'label', 'name', 'title', 'appName', 'displayName' }) or pkg
                items[#items + 1] = { pkg = pkg, name = nm,
                                      visible = (forced ~= nil) and forced or (v.visible ~= false) }
            end
            local function keyList(v)
                local ks = {}
                if type(v) ~= 'table' then return ks end
                for k, x in pairs(v) do
                    if type(x) ~= 'table' then ks[#ks + 1] = tostring(k) end
                end
                return ks
            end
            if type(data.InstalledApps) == 'table' then
                keys = keyList(data.InstalledApps[1])
                for i = 1, #data.InstalledApps do addOne(data.InstalledApps[i], true) end
                if type(data.HiddenApps) == 'table' then
                    for i = 1, #data.HiddenApps do addOne(data.HiddenApps[i], false) end
                end
                return items
            end
            for k, v in pairs(data) do
                if type(v) == 'table' then
                    if #keys == 0 then keys = keyList(v) end
                    addOne(v)
                else
                    items[#items + 1] = { pkg = tostring(k), name = tostring(v), visible = true }
                end
            end
            return items
        end
        -- 先按候选表
        for i = 1, #cands do
            tried[#tried + 1] = cands[i]
            local data = readJson(cands[i])
            local items = listOf(data)
            if items and #items > 0 then
                note('应用列表 ' .. #items)
                return { status = 'ok', source = cands[i], items = items, count = #items,
                         root = cands[i]:match('^(.*)/[^/]+$') or '', keys = keys }
            end
        end
        -- 再扫 /data 下一层（有界：只列一层目录 + 试几个固定组合）
        local seen = {}
        local dirs = { '/data', '/data/quickapp', '/data/files' }
        for d = 1, #dirs do
            local names = runShell('ls -1 "' .. dirs[d] .. '"')
            if names and names ~= '' then
                local nm = splitLines(names)
                for j = 1, #nm do
                    seen[#seen + 1] = dirs[d] .. '/' .. nm[j]
                    local w1 = dirs[d] .. '/' .. nm[j] .. '/apps.json'
                    local items1 = listOf(readJson(w1))
                    if items1 and #items1 > 0 then
                        note('应用列表 ' .. #items1 .. '（扫描找到）')
                        return { status = 'ok', source = w1, items = items1, count = #items1,
                                 root = w1:match('^(.*)/[^/]+$') or '', keys = keys }
                    end
                    local w2 = dirs[d] .. '/' .. nm[j] .. '/quickapp/apps.json'
                    local items2 = listOf(readJson(w2))
                    if items2 and #items2 > 0 then
                        note('应用列表 ' .. #items2 .. '（扫描找到）')
                        return { status = 'ok', source = w2, items = items2, count = #items2,
                                 root = w2:match('^(.*)/[^/]+$') or '', keys = keys }
                    end
                end
            end
        end
        return { status = 'error', needPath = true,
                 message = '找不到 apps.json。已试：' .. table.concat(tried, ' , '),
                 seen = seen }
    end
    if action == 'app_size' then
        if req.package == nil or req.package == '' then return { status = 'error', message = '缺少 package' } end
        -- 安装目录不一定是 /data/quickapp：优先用前端带过来的 root（apps 动作会一并返回），再退回常见位置
        local roots = { req.root, '/data/quickapp', '/data/files/quickapp', '/data/data/quickapp' }
        local kb, used = 0, ''
        for i = 1, #roots do
            if type(roots[i]) == 'string' and roots[i] ~= '' then
                local out = runShell('du -sk "' .. roots[i] .. '/' .. req.package .. '"')
                local n = tonumber(out:match('(%d+)'))
                if n and n > 0 then kb = n; used = roots[i]; break end
            end
        end
        return { status = 'ok', package = req.package, kb = kb, root = used }
    end
    if action == 'set_visible' or action == 'delete' then
        if req.confirm ~= true then
            return { status = 'error', needConfirm = true,
                     message = '这个动作会改动已装应用（' .. action .. '），请带 confirm=true 再试' }
        end
        if req.package == nil or req.package == '' then return { status = 'error', message = '缺少 package' } end
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
    end
    return { status = 'error', message = '不支持的 action：' .. tostring(action) }
end

-- 缓存：只报告与清理"缓存目录"，不动用户数据
local function doProperty(req)
    local action = req.action or 'get'
    if action == 'cache_status' then
        local total, used, avail, msrc, mraw = readMem()
        local dirs = { '/tmp', '/data/quickapp/cache', TARGET .. 'cache' }
        local rows = {}
        for i = 1, #dirs do
            local out = runShell('du -sk "' .. dirs[i] .. '"')
            local kb = tonumber(out:match('(%d+)')) or 0
            rows[#rows + 1] = { path = dirs[i], kb = kb }
        end
        note('缓存查询')
        return { status = 'ok', items = rows, memTotalKb = total, memUsedKb = used, memFreeKb = avail }
    end
    if action == 'cache_clear' then
        local dirs = { '/tmp', '/data/quickapp/cache', TARGET .. 'cache' }
        for i = 1, #dirs do
            runShell('rm -rf "' .. dirs[i] .. '/*"')
        end
        note('缓存清理')
        return { status = 'ok', message = '已清理缓存目录' }
    end
    if action == 'props' then
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
        local key = req.property or ''
        if key == 'brightness' then
            local v = readAll('/sys/class/leds/lcd-backlight/brightness', 32)
            return { status = 'ok', property = key, value = v and v:gsub('%s', '') or '' }
        end
        if key == 'screen' then
            return { status = 'ok', property = key, value = SW .. 'x' .. SH, shape = 'rect' }
        end
        return { status = 'error', message = '不支持的 property：' .. key }
    end
    return { status = 'error', message = '不支持的 action：' .. action }
end

-- 跑分：纯 Lua 浮点循环（快应用侧的 JS 跑分与这个互补）
local function doBench(req)
    local n = math.min(tonumber(req.rounds) or 400000, 4000000)
    local t0 = os.clock and os.clock() or 0
    local x, y = 0.5, 1.0
    for i = 1, n do
        x = x * 1.000001 + 0.000001
        if x > 1 then x = x - 1 end
        y = y + x * x
    end
    local secs = (os.clock and os.clock() or 0) - t0
    note('Lua 跑分')
    return { status = 'ok', rounds = n, seconds = secs,
             kops = secs > 0 and math.floor(n / secs / 1000) or -1, checksum = y }
end

-- 极端项：重启设备。必须显式 confirm
local function doSystem(req)
    local action = req.action or ''
    if action == 'reboot' then
        if req.confirm ~= true then
            return { status = 'error', needConfirm = true, message = '重启设备请带 confirm=true' }
        end
        note('重启设备')
        pcall(os.execute, 'reboot')
        return { status = 'ok', message = '已发出重启命令' }
    end
    if action == 'uptime' then
        local up = (readAll('/proc/uptime', 64) or ''):match('([%d%.]+)') or ''
        return { status = 'ok', uptimeSeconds = tonumber(up) or 0, backend = VERSION }
    end
    if action == 'mounts' then
        local items = runLines('cat /proc/mounts')
        while #items > 60 do table.remove(items) end
        return { status = 'ok', items = items, count = #items }
    end
    return { status = 'error', message = '不支持的 action：' .. action }
end

-- ======================================================================
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
local BTN_H = math.max(40, math.floor(SH * 0.088))

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

-- 顶部栏。两条硬规矩：
--   ① 胶囊屏上方是半圆，全宽内容要 y ≥ 47（212 屏），所以不能贴顶；
--   ② 返回按钮在左、标题放在**单独的整宽框里居中**，不能和按钮共用 x（共用必然重叠）。
local HEAD_TOP = math.max(46, math.floor(SH * 0.09))
local function topBar(parent, title, onBack)
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
    -- 注意：这里**不能**写 align = lvgl.ALIGN.CENTER —— 那是相对父容器重新定位，
    -- 会把 x/y 顶掉（真机上一次标题跑到屏幕底部，就是它）。居中只用 text_align。
    local tl = lvgl.Label(parent, {
        x = 0, y = HEAD_TOP + math.floor(h * 0.22), w = SW, h = math.floor(h * 0.56),
        text = title, text_font = lvgl.Font('MiSans-Regular', FONT_TITLE),
        text_color = C_TEXT, text_align = lvgl.ALIGN.CENTER,
    })
    tl:add_flag(lvgl.FLAG.EVENT_BUBBLE)
    return HEAD_TOP + h
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
    -- 用游标顺序往下排：每张卡片都从 cur 开始，排完 cur 前进「高 + 间距」，
    -- 这样相邻卡片必定隔开，改尺寸也不会算错重叠（照片里叠在一起就是这么来的）。
    local cur = bar + GAP
    local CLOCK_H = math.floor(SH * 0.22)
    local clockCard = lvgl.Object(home, { x = PAD, y = cur, w = SW - PAD * 2,
        h = CLOCK_H, radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })
    cur = cur + CLOCK_H + GAP
    clockLabel = label(clockCard, '--:--', FONT_BIG, C_TEXT, 0, math.floor(CLOCK_H * 0.06),
        SW - PAD * 2, math.floor(CLOCK_H * 0.50))
    dateLabel = label(clockCard, '', FONT_SUB, C_DIM, PAD, math.floor(CLOCK_H * 0.58),
        SW - PAD * 3, math.floor(CLOCK_H * 0.18))
    statLabel = label(clockCard, '', FONT_SUB, C_DIM, PAD, math.floor(CLOCK_H * 0.78),
        SW - PAD * 3, math.floor(CLOCK_H * 0.18))

    local b1 = card(home, '监控', 'CPU 与内存', PAD, cur, SW - PAD * 2, BTN_H, function()
        showPage('monitor'); uiRefresh() end)
    cur = cur + BTN_H + GAP
    local b2 = card(home, '日志', '后端最近干了什么', PAD, cur, SW - PAD * 2, BTN_H, function()
        showPage('log'); uiRefresh() end)
    cur = cur + BTN_H + GAP
    local b3 = card(home, '关于', VERSION, PAD, cur, SW - PAD * 2, BTN_H, function()
        showPage('about'); uiRefresh() end)

    -- 监控页
    local mon = makePage('monitor')
    local mbar = topBar(mon, '监控', function() showPage('home'); uiRefresh() end)
    local mcur = mbar + GAP
    local mc = lvgl.Object(mon, { x = PAD, y = mcur, w = SW - PAD * 2,
        h = CARD_H, radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })
    mcur = mcur + CARD_H + GAP
    monCpu = label(mc, 'CPU —', FONT_TITLE, C_TEXT, PAD, math.floor(CARD_H * 0.12), SW - PAD * 2, math.floor(CARD_H * 0.45))
    label(mc, '负载 1/5/15 分钟', FONT_SUB, C_DIM, PAD, math.floor(CARD_H * 0.62), SW - PAD * 2, math.floor(CARD_H * 0.3))
    local mm = lvgl.Object(mon, { x = PAD, y = mcur, w = SW - PAD * 2,
        h = CARD_H, radius = RADIUS, bg_color = C_CARD, border_width = 0, pad_all = 0 })
    mcur = mcur + CARD_H + GAP
    monMem = label(mm, 'MEM —', FONT_TITLE, C_TEXT, PAD, math.floor(CARD_H * 0.12), SW - PAD * 2, math.floor(CARD_H * 0.45))
    label(mm, '取自 free 的 Umem', FONT_SUB, C_DIM, PAD, math.floor(CARD_H * 0.62), SW - PAD * 2, math.floor(CARD_H * 0.3))
    card(mon, '返回主页', '点一下回去', PAD, mcur, SW - PAD * 2, BTN_H,
        function() showPage('home'); uiRefresh() end)

    -- 日志页
    local log = makePage('log')
    local lbar = topBar(log, '后端日志', function() showPage('home'); uiRefresh() end)
    -- 表盘不能滚动，卡片必须落在屏幕内：底部留 46px 给下方半圆
    local BOTTOM_SAFE = math.max(40, math.floor(SH * 0.09))
    local ltop = lbar + GAP
    local lc = lvgl.Object(log, { x = PAD, y = ltop, w = SW - PAD * 2,
        h = math.max(120, SH - ltop - BOTTOM_SAFE), radius = RADIUS,
        bg_color = C_CARD, border_width = 0, pad_all = 0 })
    logLabel = label(lc, '', FONT_SUB, '#d6d6d6', PAD, math.floor(SH * 0.02), SW - PAD * 3,
        math.max(100, SH - ltop - BOTTOM_SAFE - math.floor(SH * 0.04)))

    -- 关于页
    local about = makePage('about')
    local abar = topBar(about, '关于', function() showPage('home'); uiRefresh() end)
    local atop = abar + GAP
    local ac = lvgl.Object(about, { x = PAD, y = atop, w = SW - PAD * 2,
        h = math.max(120, SH - atop - BOTTOM_SAFE), radius = RADIUS,
        bg_color = C_CARD, border_width = 0, pad_all = 0 })
    aboutLabel = label(ac, '', FONT_SUB, '#d6d6d6', PAD, math.floor(SH * 0.03), SW - PAD * 3,
        math.max(100, SH - atop - BOTTOM_SAFE - math.floor(SH * 0.05)))

    -- 悬浮监控条：开了持续监控就浮在上面
    local fh = math.max(24, math.floor(SH * 0.05))
    -- 悬浮条也要让开下方半圆（下沿 y≈SH-47 才开始收），放到 86% 处
    floatLayer = lvgl.Object(root, { x = 0, y = math.floor(SH * 0.86), w = math.floor(SW * 0.62), h = fh,
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
    if logLabel then logLabel:set { text = table.concat(logLines, '\n') } end
    if aboutLabel then
        aboutLabel:set { text = '版本 ' .. VERSION .. '\n屏幕 ' .. SW .. 'x' .. SH
            .. '\n目录 ' .. (TARGET ~= '' and TARGET or '未定位')
            .. '\n\n功能：命令 / 文件 / 监控 / 截图 / 应用 / 属性 / 进程 / 跑分 / 日志'
            .. '\n\n会改系统的动作需要 confirm，且不碰闪存。'
            .. '\n\n界面与协议参考原作者实现，在此致谢。' }
    end
    uiRefreshFloat()
end

-- ======================================================================
-- 6. 目录定位与主循环
-- ======================================================================
local function pickTarget()
    for i = 1, #DIRS do
        if exists(DIRS[i] .. 'device_info.json') or exists(DIRS[i] .. 'tool_hello.json') then
            TARGET = DIRS[i]
            return true
        end
    end
    for i = 1, #DIRS do
        if exists(DIRS[i]) then TARGET = DIRS[i]; return true end
    end
    return false
end

local FEATURES = {
    { file = 'cmd_request.json', handler = function(req) return doCmd(req) end },
    { file = 'file_request.json', handler = function(req) return doFile(req) end },
    { file = 'cpu_monitor_request.json', handler = function(req) return doMonitor('cpu', req) end },
    { file = 'memory_monitor_request.json', handler = function(req) return doMonitor('mem', req) end },
    { file = 'screenshot_request.json', handler = function(req) return doScreenshot(req) end },
    { file = 'screenshot_float_request.json', handler = function(req)
        local a = req.action or 'status'
        if a == 'float_on' then stat.cpu.on = stat.cpu.on end
        return { status = 'ok', action = a, note = '截图悬浮由监控悬浮代管' }
    end },
    { file = 'app_manager_request.json', handler = function(req) return doAppManager(req) end },
    { file = 'property_request.json', handler = function(req) return doProperty(req) end },
    { file = 'proc_request.json', handler = function(req) return doProcList(req) end },
    { file = 'bench_request.json', handler = function(req) return doBench(req) end },
    { file = 'system_request.json', handler = function(req) return doSystem(req) end },
}

local function handleRequest(feature)
    local reqPath = TARGET .. feature.file
    local req = readJson(reqPath)
    if not req then return false end
    os.remove(reqPath)

    local resName = feature.file:gsub('_request%.json$', '_result.json')
    local function reply(res)
        res.type = 'result'
        res.seq = req.seq
        res.timestamp = os.date('%H:%M:%S')
        res.backend = VERSION
        writeJsonAtomic(resName, res)
    end

    if req.guard ~= guardToken then
        reply({ status = 'error', message = '令牌不正确（后端已轮换，请重读 ipc_guard.json）' })
        return true
    end

    local ok, res = pcall(feature.handler, req)
    if not ok then res = { status = 'error', message = '后端处理出错：' .. tostring(res) } end
    reply(res)
    return true
end

local function statusFile()
    writeJsonAtomic('backend_status.json', {
        status = 'ok', backend = VERSION, dir = TARGET, sw = SW, sh = SH,
        features = { 'cmd', 'file', 'cpu_monitor', 'memory_monitor', 'screenshot',
                     'app_manager', 'property', 'proc', 'bench', 'system' },
        note = '会改系统/文件的动作需要 confirm=true；本后端不碰闪存',
        timestamp = os.date('%H:%M:%S'),
    })
end

local function poll()
    if TARGET == '' then
        pickTarget()
        if TARGET == '' then return end
        rotateGuard()
        statusFile()
    end
    for i = 1, #FEATURES do handleRequest(FEATURES[i]) end
end

-- ======================================================================
-- 启动
-- ======================================================================
math.randomseed(os.time())
buildUI()
uiRefresh()
pickTarget()
if TARGET ~= '' then rotateGuard(); statusFile() end
uiRefresh()

local timer = lvgl.Timer({ period = 500, repeat_count = -1, cb = function()
    poll()
    if curPage == 'home' or curPage == 'monitor' then uiRefresh() end
end })
timer:resume()
