-- 测试桩：假 lvgl、假文件系统、假 NSH。只用于离线冒烟测试，不参与打包。
FS = {}
HIDDEN_CLEARED = 0      -- 清掉 HIDDEN 的次数：界面到底有没有显示出来，靠它测
local function dirOf(p) return p:match('^(.*/)[^/]*$') or '' end

io = {}
function io.open(path, mode)
    if mode == nil or mode:find('r') then          -- 含 rb / r+ 都当读模式
        local v = FS[path]
        if v == nil then return nil end
        local pos = 1
        return {
            read = function(self, n)
                if n == nil or n == '*a' then local s = v:sub(pos); pos = #v + 1; return s end
                if type(n) == 'number' then local s = v:sub(pos, pos + n - 1); pos = pos + #s; return s end
                return v:sub(pos)
            end,
            seek = function(self, whence)
                if whence == 'end' then local n = #v; pos = #v + 1; return n end
                return 0
            end,
            close = function(self) end,
        }
    end
    local buf = {}
    return {
        write = function(self, s) buf[#buf + 1] = s end,
        close = function(self) FS[path] = table.concat(buf) end,
    }
end

os.time = function() return 1769000000 end
os.date = function(fmt, t)
    if fmt == '*t' then return { year = 2026, month = 9, day = 26, hour = 14, min = 5, wday = 6 } end
    if fmt == '%H:%M:%S' then return '14:05:00' end
    return '2026-09-26'
end
os.remove = function(p) FS[p] = nil end
os.getenv = function() return nil end
-- 假 NSH：识别重定向（cmd > file）与几种常用命令（mv / mkdir / ls / dd / uname）
os.execute = function(cmd)
    local inner, outFile = cmd:match('^(.*)%s*>%s*"(.-)"%s*$')
    local out = ''
    local run = inner or cmd
    if run:match('^ls %-1 ') then
        local dir = run:match('"(.-)"') or ''
        local names, seen = {}, {}
        for k in pairs(FS) do
            if k:sub(1, #dir) == dir then
                local rest = k:sub(#dir + 1)
                local name = rest:match('^/?([^/]+)')   -- 去掉 dir 后还带一个前导斜杠
                if name and not seen[name] then seen[name] = true; names[#names + 1] = name end
            end
        end
        -- 注意：分隔符只能用转义写法 '\n'。直接敲回车会把字符串截断；
        -- 用 [[ ]] 长字符串则会把紧跟的换行吞掉（变成空分隔符，两个名字会粘在一起）。
        out = table.concat(names, '\n')
    elseif run:match('^dd ') then
        local of = run:match('of="(.-)"')
        local bs = tonumber(run:match('bs=(%d+)')) or 1
        local count = tonumber(run:match('count=(%d+)')) or 1
        FS[of] = string.rep('X', bs * count)
    elseif run:match('^free') then
        -- 照真机（NuttX）的 free 格式：分池打印，Umem 那行才是用户内存
        out = '              total       used       free    largest\n'
            .. '   GImageCache:   6291452\n'
            .. 'Kmem:     476916    361740    115176    111968\n'
            .. 'Umem:   13340924  11948660   1392264   1304010\n'
    elseif run:match('^ps') then
        out = '  PID  NAME        MEM\n'
            .. '   13  init        1234\n'
            .. '   46  miwear      654321\n'
            .. '   87  quickapp     98765\n'
    elseif run:match('^getprop') then
        if run:match('getprop "') then
            local key = run:match('getprop "(.-)"') or ''
            local table_ = { ['ro.build.version'] = '3.6.1', ['miwear_model'] = 'Xiaomi Smart Band 10' }
            out = (table_[key] or '')
        else
            out = 'ro.build.version=3.6.1\nmiwear_model=Xiaomi Smart Band 10\npersist.demo=1\n'
        end
    elseif run:match('^setprop') then
        out = ''
    elseif run:match('^mv ') then
        local a, b = run:match('mv "(.-)" "(.-)"')
        if a and b and FS[a] then FS[b] = FS[a]; FS[a] = nil end
    elseif run:match('^mkdir ') then
        -- 假 FS 不用建目录
    elseif run:match('^uname') then
        out = 'Linux miwear 4.19.0 aarch64'
    else
        out = 'ok'
    end
    if outFile then FS[outFile] = out end
    return true
end
os.clock = os.clock

lvgl = {
    HOR_RES = function() return 212 end,
    VER_RES = function() return 520 end,
    FLAG = { SCROLLABLE = 1, CLICKABLE = 2, HIDDEN = 4, EVENT_BUBBLE = 8, OVERFLOW_VISIBLE = 16 },
    EVENT = { CLICKED = 1, PRESSED = 2, RELEASED = 3 },
    -- 名字照原版实现来：是 ALIGN。我编过一个不存在的 TEXT_ALIGN，
    -- 结果桩全绿、真机报 "attempt to index a nil value (field 'TEXT_ALIGN')"
    ALIGN = { CENTER = 1, TOP_MID = 2, LEFT_MID = 3 },
    -- 名字与用法照原版：lvgl.Font('MiSans-Regular', 26)。内置 Montserrat 没汉字，别用。
    Font = function(name, size) return { name = name, size = size } end,
    BUILTIN_FONT = { MONTSERRAT_14 = 'f14', MONTSERRAT_24 = 'f24', MONTSERRAT_48 = 'f48' },
    Object = function(parent, opt)
        return { opt = opt, set = function(self, o) end,
                 add_flag = function() end,
                 clear_flag = function(self, f) if f == 4 then HIDDEN_CLEARED = HIDDEN_CLEARED + 1 end end,
                 onevent = function(self, ev, cb) self.cb = cb end }
    end,
    Label = function(parent, opt)
        return { opt = opt, text = opt and opt.text or '',
                 -- 改文字是 set { text = ... }，没有 set_text（我编过 set_text，真机报 nil）
                 set = function(self, o) if type(o) == 'table' and o.text ~= nil then self.text = o.text end end,
                 add_flag = function() end,
                 clear_flag = function(self, f) if f == 4 then HIDDEN_CLEARED = HIDDEN_CLEARED + 1 end end,
                 onevent = function(self, ev, cb) self.cb = cb end }
    end,
    Timer = function(opt)
        TIMER_CB = opt.cb                      -- 测试里手动触发
        return { resume = function() end, pause = function() end }
    end,
}
