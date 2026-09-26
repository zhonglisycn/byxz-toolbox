_lua/O66_Lua/main1.lua----
---json 转换工具
---@class JSON @by wx771720@outlook.com 2019-08-07 16:03:34
_G.JSON = {escape = "\\", comma = ",", colon = ":", null = "null"}

---将数据转换成 json 字符串
---@param data any @数据
---@param space number|string @美化输出时缩进空格数量或者字符串，默认 nil 表示不美化
---@param toArray boolean @如果是数组，是否按数组格式输出，默认 true
---@return string @返回 json 格式的字符串
function JSON.toString(data, space, toArray, __tableList, __keyList, __indent)
	if "boolean" ~= type(toArray) then toArray = true end
	if "table" ~= type(__tableList) then __tableList = {} end
	if "table" ~= type(__keyList) then __keyList = {} end
	if "number" == type(space) then space = space > 0 and string.format("%" .. tostring(space) .. "s", " ") or nil end
	if nil ~= space and nil == __indent then __indent = "" end

	local dataType = type(data)
	-- string
	if "string" == dataType then
		data = string.gsub(data, "\\", "\\\\")
		data = string.gsub(data, "\"", "\\\"")
		return "\"" .. data .. "\""
	end
	-- number
	if "number" == dataType then return tostring(data) end
	-- boolean
	if "boolean" == dataType then return data and "true" or "false" end
	-- table
	if "table" == dataType then
		table.insert(__tableList, data)

		local result, value
		if 0 == JSON._tableCount(data) then
			result = "{}"
		elseif toArray and JSON._isArray(data) then
			result = nil == space and "[" or (__indent .. "[")
			local subIndent = __indent and (__indent .. space)
			for i = 1, #data do
				value = data[i]
				if "table" == type(value) and JSON._indexOf(__tableList, value) >= 1 then
					print(string.format("json array loop refs warning : %s[%i]", JSON.toString(__keyList), i))
				else
					local valueString = JSON.toString(data[i], space, toArray, __tableList, table.insert({table.unpack(__keyList)}, i), subIndent)
					if valueString and subIndent and JSON._isBeginWith(valueString, subIndent) then valueString = string.sub(valueString, #subIndent + 1) end
					if nil == space then
						result = result .. (i > 1 and "," or "") .. (valueString or JSON.null)
					else
						result = result .. (i > 1 and "," or "") .. "\n" .. subIndent .. (valueString or JSON.null)
					end
				end
			end
			result = result .. (nil == space and "]" or ("\n" .. __indent .. "]"))
		else
			result = nil == space and "{" or (__indent .. "{")
			local index = 0
			local subIndent = __indent and (__indent .. space)
			for k, v in pairs(data) do
				if "table" == type(v) and JSON._indexOf(__tableList, v) >= 1 then
					print(string.format("json map loop refs warning : %s[%s]", JSON.toString(__keyList), k))
				else
					local valueString = JSON.toString(v, space, toArray, __tableList, table.insert({table.unpack(__keyList)}, k), subIndent)
					if valueString then
						if subIndent and JSON._isBeginWith(valueString, subIndent) then valueString = string.sub(valueString, #subIndent + 1) end
						if nil == space then
							result = result .. (index > 0 and "," or "") .. ("\"" .. k .. "\":") .. valueString
						else
							result = result .. (index > 0 and "," or "") .. "\n" .. subIndent .. ("\"" .. k .. "\" : ") .. valueString
						end
						index = index + 1
					end
				end
			end
			result = result .. (nil == space and "}" or ("\n" .. __indent .. "}"))
		end
		return result
	end
end

---去掉字符串首尾空格
---@param target string
---@return string
JSON._trim = function(target) return target and string.gsub(target, "^%s*(.-)%s*$", "%1") end
---判断字符串是否已指定字符串开始
---@param str string @需要判断的字符串
---@param match string @需要匹配的字符串
---@return boolean
JSON._isBeginWith = function(str, match) return nil ~= string.match(str, "^" .. match) end
---计算指定表键值对数量
---@param map table @表
---@return number @返回表数量
JSON._tableCount = function(map)
	local count = 0
	for _, __ in pairs(map) do count = count + 1 end
	return count
end
---判断指定表是否是数组（不包含字符串索引的表）
---@param target any @表
---@return boolean @如果不包含字符串索引则返回 true，否则返回 false
JSON._isArray = function(target)
	if "table" == type(target) then
		for key, _ in pairs(target) do if "string" == type(key) then return false end end
		return true
	end
	return false
end
---获取数组中第一个项索引
JSON._indexOf = function(array, item)
	for i = 1, #array do if item == array[i] then return i end end
	return -1
end

---将字符串转换成 table 对象
---@param text string json @格式的字符串
---@return any|nil @如果解析成功返回对应数据，否则返回 nil
JSON.toJSON = function(text)
	text = JSON._trim(text)
	-- string
	if "\"" == string.sub(text, 1, 1) and "\"" == string.sub(text, -1, -1) then return string.sub(JSON.findMeta(text), 2, -2) end
	if 4 == #text then
		-- boolean
		local lowerText = string.lower(text)
		if "false" == lowerText then
			return false
		elseif "true" == lowerText then
			return true
		end
		-- nil
		if JSON.null == lowerText then return end
	end
	-- number
	local number = tonumber(text)
	if number then return number end
	-- array
	if "[" == string.sub(text, 1, 1) and "]" == string.sub(text, -1, -1) then
		local remain = string.gsub(text, "[\r\n]+", "")
		remain = string.sub(remain, 2, -2)
		local array, index, value = {}, 1
		while #remain > 0 do
			value, remain = JSON.findMeta(remain)
			if value then
				value = JSON.toJSON(value)
				array[index] = value
				index = index + 1
			end
		end
		return array
	end
	-- table
	if "{" == string.sub(text, 1, 1) and "}" == string.sub(text, -1, -1) then
		local remain = string.gsub(text, "[\r\n]+", "")
		remain = string.sub(remain, 2, -2)
		local key, value
		local map = {}
		while #remain > 0 do
			key, remain = JSON.findMeta(remain)
			value, remain = JSON.findMeta(remain)
			if key and #key > 0 and value then
				key = JSON.toJSON(key)
				value = JSON.toJSON(value)
				if key and value then map[key] = value end
			end
		end
		return map
	end
end

---查找字符串中的 json 元数据
---@param text string @json 格式的字符串
---@return string,string @元数据,剩余字符串
JSON.findMeta = function(text)
	local stack = {}
	local index = 1
	local lastChar = nil
	while index <= #text do
		local char = string.sub(text, index, index)
		if "\"" == char then
			if char == lastChar then
				table.remove(stack, #stack)
				lastChar = #stack > 0 and stack[#stack] or nil
			else
				table.insert(stack, char)
				lastChar = char
			end
		elseif "\"" ~= lastChar then
			if "{" == char then
				table.insert(stack, "}")
				lastChar = char
			elseif "[" == char then
				table.insert(stack, "]")
				lastChar = char
			elseif "}" == char or "]" == char then
				-- assert(char == lastChar, text .. " " .. index .. " not expect " .. char .. "<=>" .. lastChar)
				table.remove(stack, #stack)
				lastChar = #stack > 0 and stack[#stack] or nil
			elseif JSON.comma == char or JSON.colon == char then
				if not lastChar then return string.sub(text, 1, index - 1), string.sub(text, index + 1) end
			end
		elseif JSON.escape == char then
			text = string.sub(text, 1, index - 1) .. string.sub(text, index + 1)
		end

		index = index + 1
	end
	return string.sub(text, 1, index - 1), string.sub(text, index + 1)
end

_G.getFileSize = function (path)
    local rf = io.open(path,"rb")
    local len = rf:seek("end")
    rf:close()
    return len
end

_G.getFolderSize =  function (path)
    local size = 0
    local dir, msg, code = lvgl.fs.open_dir(path)
    if not dir then
        -- print("open dir failed: ", msg, code)
        return size
    end

    while true do
        local d = dir:read()
        if not d then break end
        local is_dir = string.byte(d, 1) == string.byte("/", 1)
        local str = (is_dir and "dir: " or "file: ") .. d
        -- printf(str)

        if is_dir == true then
            size = size + getFolderSize(path .. d)
        else
            size = size + getFileSize(path .. '/' .. d)
        end
    end
    dir:close()

    return size
end

---@diagnostic disable: unused-function, missing-fields
local lvgl = require("lvgl")
-- require("json")
-- require("fs2")
local fsRoot = SCRIPT_PATH
local DEBUG_ENABLE = false
-- local version = 'v1.8'
-- local TEXT_FONT = lvgl.BUILTIN_FONT.MONTSERRAT_14

local function fileExists(name)
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
end

local appJsonPath = '/data/quickapp/apps.json' --P65及之前设备
local appJsonPathHide = '/data/quickapp/apps.json_hide' --P65及之前设备
local appPathApp = '/data/quickapp/app/' --P65及之前设备
local appPathApp_file2 = '/data/quickapp/files/' --P65及之前设备
local appPathApp_file3 = '/data/quickapp/mass/' --P65及之前设备
local appPathApp_file1 = '/data/quickapp/cache/' --P65及之前设备
local appPathSystem = '/data/quickapp/system/'
-- local appJsonPath = '/data/apps.json' --P67设备
-- local appJsonPathHide = '/data/apps.json_hide' --P67设备
-- local appPathApp = '/data/app/' --P67设备
-- local appPathApp_file1 = '/data/cache/' --P67设备
-- local appPathApp_file2 = '/data/files/' --P67设备
-- local appPathApp_file3 = '/data/mass/'--P67设备

local appLsFilePath = '/data/mass/tmp'

if string.find(fsRoot, '/home/watchface') ~= nil then
    DEBUG_ENABLE = true
    appPathApp = '/home/watchface/simulator/luavgl/examples/app/'
    appPathSystem = '/home/watchface/simulator/luavgl/examples/app1/'
    appJsonPath = '/home/watchface/simulator/luavgl/examples/fm2/apps.json'
    appJsonPathHide = '/home/watchface/simulator/luavgl/examples/fm2/apps.json_hide'
    appPathApp_file1 = '/home/watchface/simulator/luavgl/examples/app2/'
    appPathApp_file2 = '/home/watchface/simulator/luavgl/examples/app3/'
    appPathApp_file3 = '/home/watchface/simulator/luavgl/examples/app4/'
    appLsFilePath = '/home/watchface/simulator/luavgl/examples/ls2/'
else
    -- 在独立lua中可以使用
    -- TEXT_FONT = lvgl.Font('misansw medium', 22)
    -- TEXT_FONT = lvgl.Font('misansw_Medium', 22)
end

local isS3 = fileExists('/font/MiSans-Medium.ttf') or fileExists('/system/font/MiSans-Medium.ttf') or fileExists('/resource/font/MiSans-Medium.ttf')

local TEXT_FONT = lvgl.BUILTIN_FONT.MONTSERRAT_14
if DEBUG_ENABLE == false then
    if isS3 then
        TEXT_FONT = lvgl.Font('MiSans-Medium', 32)
    else
        TEXT_FONT = lvgl.Font('misansw_Medium', 32)
    end
end

local TEXT_FONT2 = lvgl.BUILTIN_FONT.MONTSERRAT_14
if DEBUG_ENABLE == false then
    if isS3 then
        TEXT_FONT2 = lvgl.Font('MiSans-Medium', 26)
    else
        TEXT_FONT2 = lvgl.Font('misansw_Medium', 26)
    end
end

local TEXT_FONT3 = lvgl.BUILTIN_FONT.MONTSERRAT_14
if DEBUG_ENABLE == false then
    if isS3 then
        TEXT_FONT3 = lvgl.Font('MiSans-Medium', 20)
    else
        TEXT_FONT3 = lvgl.Font('misansw_Medium', 20)
    end
end

local printf = DEBUG_ENABLE and print or function(...)
    end

local img_suff = {}
local function imgPath(src)
    if DEBUG_ENABLE then
        return fsRoot .. 'fm2/' .. src .. '.png'
    end
    local path = fsRoot .. src
    if img_suff[src] ~= nil then
        return path .. img_suff[src]
    end
    if fileExists(path .. '.bin') then
        img_suff[src] = '.bin'
        return path .. img_suff[src]
    elseif fileExists(path .. '.rle') then
        img_suff[src] = '.rle'
        return path .. img_suff[src]
    end
    return path
end

local rootbase1 = lvgl.Object(nil, {
    outline_width = 0,
    border_width = 0,
    pad_all = 0,
    bg_opa = lvgl.OPA(100),
    bg_color = 0,
    align = lvgl.ALIGN.CENTER,
    w = lvgl.HOR_RES(),
    h = lvgl.VER_RES()
})

rootbase1:clear_flag(lvgl.FLAG.SCROLLABLE)
rootbase1:add_flag(lvgl.FLAG.EVENT_BUBBLE)

local rootbase = lvgl.Object(rootbase1, {
        outline_width = 0,
        border_width = 0,
        pad_all = 0,
        bg_opa = lvgl.OPA(100),
        bg_color = 0,
        align = lvgl.ALIGN.CENTER,
        w = 212,
        h = 520
    })

rootbase:clear_flag(lvgl.FLAG.SCROLLABLE)
rootbase:add_flag(lvgl.FLAG.EVENT_BUBBLE)

function enableEventBubble(obj)
        -- Устанавливаем флаг «EVENT_BUBBLE» для текущего объекта
        obj:add_flag(lvgl.FLAG.EVENT_BUBBLE)

        -- Рекурсивно обходим всех детей
        local count = obj:get_child_cnt()
        for i = 0, count - 1 do
            local child = obj:get_child(i)
            if child then
                enableEventBubble(child)
            end
        end
    end
    enableEventBubble(rootbase)

---- 执行命令相关

local timer
local commandIndex = 1
local commandTable = {}

local function showToast(name)
    local img = rootbase:Image { src = imgPath(name), x = 6, y = -76 }
    local aimY = 60
    local inTimer = false
    img:Anim {
        run = true,
        start_value = -76,
        end_value = aimY + 86,
        time = 900, -- 560ms fixed
        repeat_count = 1,
        path = "ease_in_out",
        exec_cb = function(obj, now)
            if now <= aimY then
                img:set { y = now }
            else
                if now == aimY + 86 then
                    img:delete()
                end
            end
            -- img:set { y = now }
            -- if now == aimY then
            --     if inTimer then
            --         return
            --     end
            --     inTimer = true

            --     img:Anim {
            --         run = true,
            --         start_value = 0,
            --         end_value = 400,
            --         time = 400, -- 560ms fixed
            --         repeat_count = 1,
            --         path = "ease_in_out",
            --         exec_cb = function(obj, now)
            --             img:delete()
            --         end
            --     }

            --     -- lvgl.Timer {
            --     --     period = 1000,
            --     --     paused = false,
            --     --     repeat_count = 1,
            --     --     cb = function(t)
            --     --         img:delete()
            --     --     end
            --     -- }
            -- end
        end
    }
end

local function runCommandAndShowMsg(cmd)
    if cmd == 'waitfor' then
        showToast('reboot')
        return
    end

    if cmd == 'success' then
        showToast('success')
        return
    end

    printf('nsh:' .. cmd)
    if DEBUG_ENABLE then
        return
    end
    local dircmd = cmd
    os.execute(dircmd)
end

local function runCommandAndgetResult(cmd)
    printf('nsh:' .. cmd)
    -- if DEBUG_ENABLE then
    --     return
    -- end
    local tmpFilePath = '/data/tmpFile'
    if DEBUG_ENABLE then
        tmpFilePath = '/home/watchface/simulator/luavgl/examples/tmpFile'
    end
    local dircmd = cmd
    os.execute(dircmd .. " > " .. tmpFilePath)
    local strs = ''
    for f in io.lines(tmpFilePath) do
        strs = strs .. f .. '\n'
    end

    if #strs > 0 then
        strs = string.sub(strs, 1, -2)
    end
    printf(strs)
    os.execute("rm " .. tmpFilePath)

    return strs
end

local function doNextCommand()
    if commandIndex <= #commandTable then
        local cmd = commandTable[commandIndex]
        runCommandAndShowMsg(cmd)
        commandIndex = commandIndex + 1
    else
        -- timer:pause()
    end
end

lvgl.Timer {
    period = 1000,
    paused = false,
    cb = function(t)
        doNextCommand()
    end
}

local function doMuiltCommand(cmds)
    showToast("runing")
    commandTable = cmds
    commandIndex = 1
    -- timer:resume()
end

---- 文件读写相关
local function readFileToStr(file)
    if fileExists(file) == false then
        printf('File Not Found : ' .. file)
        return ''
    end
    local text = ''
    for f in io.lines(file) do
        text = text .. f .. '\n'
    end
    return text
end

function split(input, delimiter)
    local arr = {}
    function fAdd(w)
        if w and w ~= '' then
            table.insert(arr, w)
        end
    end
    string.gsub(input, '[^' .. delimiter ..']+', fAdd)
    return arr
end
---- 页面相关

local mainPage
local bindNewPage
local appsPage1

local appList

local reloadAppsFunc


local lfFilePage
local reloadFileSize
local fileSizeWd

local function showPage(wd)
    if mainPage == wd then
        printf("show mainpage")
        mainPage:clear_flag(lvgl.FLAG.HIDDEN)
    else
        printf("hide mainpage")
        mainPage:add_flag(lvgl.FLAG.HIDDEN)
    end

    if bindNewPage == wd then
        printf("show bindNewPage")
        bindNewPage:clear_flag(lvgl.FLAG.HIDDEN)
    else
        printf("hide bindNewPage")
        bindNewPage:add_flag(lvgl.FLAG.HIDDEN)
    end

    if appsPage1 == wd then
        printf("show appsPage1")
        reloadAppsFunc()
        appsPage1:clear_flag(lvgl.FLAG.HIDDEN)
    else
        printf("hide appsPage1")
        appsPage1:add_flag(lvgl.FLAG.HIDDEN)
    end

    if lfFilePage == wd then
        printf("show appsPage1")
        reloadFileSize()
        lfFilePage:clear_flag(lvgl.FLAG.HIDDEN)
    else
        printf("hide appsPage1")
        lfFilePage:add_flag(lvgl.FLAG.HIDDEN)
    end
end

---- 首页
local function createMainPage(rootWd)
    local root = lvgl.Object(rootWd, {
        outline_width = 0,
        border_width = 0,
        pad_all = 0,
        bg_opa = lvgl.OPA(100),
        bg_color = 0,
        align = lvgl.ALIGN.CENTER,
        w = 212,
        h = 520
    })

    root:clear_flag(lvgl.FLAG.SCROLLABLE)
    root:add_flag(lvgl.FLAG.EVENT_BUBBLE)

    printf(imgPath('title'))
    root:Image { src = imgPath('title'), x = 0, y = 33 }
    -- root:Image { src = imgPath('device'), x = 6, y = 6 } --圆表设备不显示

    -- root:Label {
    --     w = 80,
    --     h = 40,
    --     x = 185,
    --     y = 14,
    --     text = version,
    --     text_color = '#eeeeee',
    --     bg_color = 0,
    --     font_size = 30,
    --     border_width = 0,
    --     text_font = TEXT_FONT,
    --     text_align = lvgl.ALIGN.CENTER
    -- }--版本号

    -- local bindNew = root:Image { src = imgPath('rebind'), x = 6, y = 70 }
    -- bindNew:add_flag(lvgl.FLAG.CLICKABLE)
    -- bindNew:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
    --     showPage(bindNewPage)
    -- end)
    local dv = root:Image { src = imgPath('about'), x = 55, y = 436 }
    dv:add_flag(lvgl.FLAG.CLICKABLE)
    dv:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        local root = lvgl.Object(root, {
            outline_width = 0,
            border_width = 0,
            pad_all = 0,
            bg_opa = lvgl.OPA(100),
            bg_color = 0,
            align = lvgl.ALIGN.CENTER,
            w = 212,
            h = 520
        })

        root:clear_flag(lvgl.FLAG.SCROLLABLE)
        root:add_flag(lvgl.FLAG.EVENT_BUBBLE)

        local title_back_dv = root:Image { src = imgPath('back'), x = 55, y = 436 }
        root:Image { src = imgPath('device_detail'), x = 0, y = 0 }
        -- root:Image { src = imgPath('version'), x = 258, y = 6 } --圆表设备不显示

        title_back_dv:add_flag(lvgl.FLAG.CLICKABLE)
        title_back_dv:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
            root:clean()
            root:delete()
        end)
    end)


    local apps = root:Image { src = imgPath('apps'), x = 6, y = 77 }
    apps:add_flag(lvgl.FLAG.CLICKABLE)
    apps:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        showPage(appsPage1)
    end)

    local df = root:Image { src = imgPath('cc_title'), x = 6, y = 181 }
    df:add_flag(lvgl.FLAG.CLICKABLE)
    df:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        
        local rootDf = lvgl.Object(root, {
            outline_width = 0,
            border_width = 0,
            pad_all = 0,
            bg_opa = lvgl.OPA(100),
            bg_color = 0,
            align = lvgl.ALIGN.CENTER,
            w = 212,
            h = 520
        })

        rootDf:clear_flag(lvgl.FLAG.SCROLLABLE)
        rootDf:add_flag(lvgl.FLAG.EVENT_BUBBLE)

        local title_back_df = rootDf:Image { src = imgPath('back'), x = 55, y = 436 }
        local title_txt_df = rootDf:Image { src = imgPath('cc_txt'), x = 0, y = 33 }

        title_back_df:add_flag(lvgl.FLAG.CLICKABLE)
        title_back_df:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
            rootDf:clean()
            rootDf:delete()
        end)

        title_txt_df:add_flag(lvgl.FLAG.CLICKABLE)
        title_txt_df:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
            rootDf:clean()
            rootDf:delete()
        end)

        local str = runCommandAndgetResult('df -h')

        local str1 = 'system'
        local str2 = 'data'

        -- local strAll = ''
        -- local ss = split(str,'\n')
        -- for i=1,#ss,1 do
        --     if string.find(ss[i], str1) or string.find(ss[i], str2) then
        --         printf(ss[i])
        --         local ss2 = split(ss[i],' ')
        --         local start_i, end_j, substr = string.find(ss[i],ss2[2])
        --         strAll = strAll .. string.sub(ss[i], start_i) .. '\n'
        --     end
        -- end

        -- strAll = string.gsub(strAll,"Size","总大小")
        -- strAll = string.gsub(strAll,"Used","已使用")
        -- strAll = string.gsub(strAll,"Available","可用")
        -- strAll = string.gsub(strAll,"Mounted on","类型")
        -- strAll = string.gsub(strAll,"/data","数据")
        -- strAll = string.gsub(strAll,"/system","系统")

        -- for i=1,30,1 do
        --     strAll = string.gsub(strAll,"  "," ")
        -- end

        -- strAll = string.gsub(strAll,"Mounted on","Type")
        -- strAll = string.gsub(strAll,"/data","data")
        -- strAll = string.gsub(strAll,"/system","system")

        local function extractData(line)
            local parts = {}
            for part in string.gmatch(line, "%S+") do
                table.insert(parts, part)
            end
            return parts
        end
        
        local function removeM(size)
            return string.gsub(size, 'M', '')
        end
        
        local ss = split(str, '\n')
        for i = 1, #ss, 1 do
            if string.find(ss[i], str1) then
                local parts = extractData(ss[i])
                system = removeM(parts[3]) .. '/' .. parts[2]
            elseif string.find(ss[i], str2) then
                local parts = extractData(ss[i])
                data = removeM(parts[3]) .. '/' .. parts[2]
            end
        end
        
        -- printf("System: %s\n", system)
        -- printf("Data: %s\n", data)

        rootDf:Image { src = imgPath('cc_bg'), x = 6, y = 77 }

        rootDf:Label {
            w = 162,
            h = 42,
            x = 25,
            y = 87,
            text = "系统分区",
            text_color = '#ffffff',
            font_size = 32,
            text_align = lvgl.ALIGN.TOP_LEFT,
            text_font = TEXT_FONT
        }
        rootDf:Label {
            w = 162,
            h = 42,
            x = 25,
            y = 191,
            text = "用户分区",
            text_color = '#ffffff',
            font_size = 32,
            text_align = lvgl.ALIGN.TOP_LEFT,
            text_font = TEXT_FONT
        }

        rootDf:Label {
            w = 162,
            h = 34,
            x = 25,
            y = 129,
            text = system,
            text_color = '#a8a8a8',
            font_size = 26,
            text_align = lvgl.ALIGN.TOP_LEFT,
            text_font = TEXT_FONT2
        }

        rootDf:Label {
            w = 162,
            h = 34,
            x = 25,
            y = 233,
            text = data,
            text_color = '#a8a8a8',
            font_size = 26,
            text_align = lvgl.ALIGN.TOP_LEFT,
            text_font = TEXT_FONT2
        }

        rootDf:Image { src = imgPath('cc_tips'), x = 6, y = 285 }

    end)

    local lsFileClearTitle = root:Image { src = imgPath('lsfile_card'), x = 6, y = 285 }
    lsFileClearTitle:add_flag(lvgl.FLAG.CLICKABLE)
    lsFileClearTitle:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        showPage(lfFilePage)
    end)

    return root
end

mainPage = createMainPage(rootbase)


local function createBindPage(rootWd)
    local root = lvgl.Object(rootWd, {
        outline_width = 0,
        border_width = 0,
        pad_all = 0,
        bg_opa = lvgl.OPA(100),
        bg_color = 0,
        align = lvgl.ALIGN.CENTER,
        w = 212,
        h = 520
    })

    root:clear_flag(lvgl.FLAG.SCROLLABLE)
    root:add_flag(lvgl.FLAG.EVENT_BUBBLE)
    
    
    local title_txt = root:Image { src = imgPath('rebind_title'), x = 0, y = 0}
    local title_back = root:Image { src = imgPath('back'), x = 6, y = 6 }

    title_back:add_flag(lvgl.FLAG.CLICKABLE)
    title_back:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        showPage(mainPage)
    end)

    title_txt:add_flag(lvgl.FLAG.CLICKABLE)
    title_txt:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        showPage(mainPage)
    end)

    root:Image { src = imgPath('rebind_img'), x = 85, y = 91 }
    root:Image { src = imgPath('rebind_info'), x = 26, y = 240 }

    local btn = root:Image { src = imgPath('bind'), x = 6, y = 356 }

    local flag = false
    btn:add_flag(lvgl.FLAG.CLICKABLE)
    btn:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        if flag then
            return
        end
        flag = true
        local cmds = {
            "cp /data/persist.db /data/persist.db.bk",
            "rm /data/persist.db",
            "waitfor",
            "waitfor",
            "reboot"}
        doMuiltCommand(cmds)
    end)

    return root
end

bindNewPage = createBindPage(rootbase)

local function delMassFolder(folderPath)
    os.execute('rm -r ' .. folderPath)
    os.execute('mkdir -p ' .. folderPath)
end

local function createlfFilePage(rootWd)
    local root = lvgl.Object(rootWd, {
        outline_width = 0,
        border_width = 0,
        pad_all = 0,
        bg_opa = lvgl.OPA(100),
        bg_color = 0,
        align = lvgl.ALIGN.CENTER,
        w = 212,
        h = 520
    })

    root:clear_flag(lvgl.FLAG.SCROLLABLE)
    root:add_flag(lvgl.FLAG.EVENT_BUBBLE)

    
    local title_txt = root:Image { src = imgPath('lsfile_title'), x = 0, y = 34 }
    local title_back = root:Image { src = imgPath('back'), x = 55, y = 436 }
    root:Image { src = imgPath('ls_bg'), x = 6, y = 77 }
    root:Image { src = imgPath('ls_tip'), x = 6, y = 181 }
    root:Image { src = imgPath('lsfile_tips'), x = 25, y = 87 }

    title_back:add_flag(lvgl.FLAG.CLICKABLE)
    title_back:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        showPage(mainPage)
    end)

    title_txt:add_flag(lvgl.FLAG.CLICKABLE)
    title_txt:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        showPage(mainPage)
    end)

    local btn = root:Image { src = imgPath('lsfile_do'), x = 55, y = 354 }

    local flag = false
    btn:add_flag(lvgl.FLAG.CLICKABLE)
    btn:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        if flag then
            return
        end
        flag = true
        local cmds = {
            "success"
        }
        doMuiltCommand(cmds)
        delMassFolder(appLsFilePath)
        reloadFileSize()
        flag = false
    end)

    fileSizeWd = root:Label {
        w = 162,
        h = 34,
        x = 25,
        y = 129,
        text = '',
        text_color = '#a8a8a8',
        bg_color = 0,
        border_width = 0,
        font_size = 26,
        text_align = lvgl.ALIGN.TOP_LEFT,
        text_font = TEXT_FONT2
    }

    return root
end

lfFilePage = createlfFilePage(rootbase)

local function setLabelStyle(lable)
    lable: set {
        bg_color = '#262626',
        radius = 10,
        border_width = 0,
        h = 100,
        w = 316,
        text_color = '#FFFFFF',
        text_font = TEXT_FONT
    }
end

local function removeAndSave(path,appInfo)
    local jsonStr = readFileToStr(path)

    local jsonObj = {
        InstalledApps = {}
    }

    if jsonStr ~= '' then
        jsonObj = JSON.toJSON(jsonStr)
    else
        return
    end

    for i=1,#jsonObj.InstalledApps,1 do
        local app = jsonObj.InstalledApps[i]
        if app.package == appInfo.package then
            table.remove(jsonObj.InstalledApps,i)
            break
        end
    end

    local newJsonStr = JSON.toString(jsonObj,4,true)

    printf('removeAndSave')
    printf(newJsonStr)

    local f = io.open(path, "w+")
    f:write(newJsonStr)
    f:close()
end

local function addAndSave(path,appInfo)
    local jsonStr = readFileToStr(path)

    local jsonObj = {
        InstalledApps = {}
    }

    if jsonStr ~= '' then
        jsonObj = JSON.toJSON(jsonStr)
    end

    table.insert(jsonObj.InstalledApps,appInfo)

    local newJsonStr = JSON.toString(jsonObj,4,true)

    printf('addAndSave')
    printf(newJsonStr)

    local f = io.open(path, "w+")
    f:write(newJsonStr)
    f:close()
end

local function getAllAppSize(package)
    local size = 0
    size = size + getFolderSize(appPathApp .. package)
    size = size + getFolderSize(appPathSystem .. package)
    size = size + getFolderSize(appPathApp_file1 .. package)
    size = size + getFolderSize(appPathApp_file2 .. package)
    size = size + getFolderSize(appPathApp_file3 .. package)

    local rs = ''
    if size > 1024 * 1024 then
        rs = math.floor(size*100/(1024*1024))/100 .. 'M'
    else
        rs = math.floor(size*100/(1024))/100 .. 'K'
    end
    return rs
end

local function createAppDetailPage(rootWd,appInfo)
    local root = lvgl.Object(rootWd, {
        outline_width = 0,
        border_width = 0,
        pad_all = 0,
        bg_opa = lvgl.OPA(100),
        bg_color = 0,
        align = lvgl.ALIGN.CENTER,
        w = 212,
        h = 520
    })

    root:clear_flag(lvgl.FLAG.SCROLLABLE)
    root:add_flag(lvgl.FLAG.EVENT_BUBBLE)

    
    local title_txt = root:Image { src = imgPath('appdetail'), x = 0, y = 33 }
    local title_back = root:Image { src = imgPath('back'), x = 55, y = 436 }

    title_back:add_flag(lvgl.FLAG.CLICKABLE)
    title_back:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        root:clean()
        root:delete()
    end)

    title_txt:add_flag(lvgl.FLAG.CLICKABLE)
    title_txt:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        root:clean()
        root:delete()
    end)

    local imgIconPath = appPathApp .. appInfo.package .. '/' .. appInfo.icon
    if fileExists(imgIconPath) == false then
        imgIconPath = imgPath('notfound')
    end
    local img = root:Image { src = imgIconPath, x = 56, y = 84 }
    local w, h = img:get_img_size()
    if w ~= 100 then
        local scale = math.floor(256*100/w)
        img:set {
            zoom = scale,
            w = w,
            h = w,
            x = 56 - math.floor((w - 100)/2),
            y = 84 - math.floor((w - 100)/2)
        }
    end

    local text = appInfo.package .. '\n版本号:' .. appInfo.versionName
    local label = root:Label {
        w = 200,
        h = 135,
        x = 6,
        y = 198,
        text = text,
        text_color = '#eeeeee',
        bg_color = 0,
        border_width = 0,
        font_size = 20,
        text_align = lvgl.ALIGN.TOP_MID,
        text_font = TEXT_FONT3
    }

    label:Anim {
        run = true,
        start_value = 0,
        end_value = 10,
        time = 10, -- 560ms fixed
        repeat_count = 1,
        path = "ease_in_out",
        exec_cb = function(obj, now)
            if now == 10 then
                local txt = getAllAppSize(appInfo.package)
                label:set {
                    text = text .. '\n' .. txt
                }
            end
        end
    }

    local btn = root:Image { src = imgPath('uninstallapp'), x = 2, y = 354 }

    local flag = false
    
    btn:add_flag(lvgl.FLAG.CLICKABLE)
    btn:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        if flag then
            return
        end
        flag = true

        -- local jsonStr = readFileToStr(appJsonPath)
        -- local jsonObj = JSON.toJSON(jsonStr)
    
        -- for i=1,#jsonObj.InstalledApps,1 do
        --     local app = jsonObj.InstalledApps[i]
        --     if app.package == appInfo.package then
        --         table.remove(jsonObj.InstalledApps,i)
        --         break
        --     end
        -- end

        -- local newJsonStr = JSON.toString(jsonObj,4,true)

        -- printf(newJsonStr)

        -- local f = io.open(appJsonPath, "w+")
        -- f:write(newJsonStr)
        -- f:close()
        -- if appInfo.hideFlag == nil or appInfo.hideFlag == false then
        --     removeAndSave(appJsonPath,appInfo)
        -- else
        --     removeAndSave(appJsonPathHide,appInfo)
        -- end
        removeAndSave(appJsonPath,appInfo)
        removeAndSave(appJsonPathHide,appInfo)
        
        local cmds = {
            "rm -r " .. appPathApp .. appInfo.package .. '/',
            "rm -r " .. appPathSystem .. appInfo.package .. '/',
            "rm -r " .. appPathApp_file1 .. appInfo.package .. '/',
            "rm -r " .. appPathApp_file2 .. appInfo.package .. '/',
            "rm -r " .. appPathApp_file3 .. appInfo.package .. '/',
            "waitfor",
            "waitfor",
            "reboot"
        }
        doMuiltCommand(cmds)
    end)

    if appInfo.hideFlag == nil or appInfo.hideFlag == false then
        local btn2 = root:Image { src = imgPath('hide'), x = 108, y = 354 }

        btn2:add_flag(lvgl.FLAG.CLICKABLE)
        btn2:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
            if flag then
                return
            end
            flag = true
    
            -- 隐藏APP
            removeAndSave(appJsonPath,appInfo)
            appInfo.hideFlag = true
            addAndSave(appJsonPathHide,appInfo)
    
            local cmds = {
                "waitfor",
                "waitfor",
                "reboot"
            }
            doMuiltCommand(cmds)
        end)
    else
        local btn2 = root:Image { src = imgPath('unhide'), x = 108, y = 354 }

        btn2:add_flag(lvgl.FLAG.CLICKABLE)
        btn2:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
            if flag then
                return
            end
            flag = true
            -- 显示APP
    
            removeAndSave(appJsonPathHide,appInfo)
            appInfo.hideFlag = nil
            addAndSave(appJsonPath,appInfo)
    
            local cmds = {
                "waitfor",
                "waitfor",
                "reboot"
            }
            doMuiltCommand(cmds)
        end)
    end
end

local function showAppDetailPage(root,app)
    printf(JSON.toString(app,4,true))

    createAppDetailPage(root,app)
end

local function reloadApps(root,list)
    local jsonStr = readFileToStr(appJsonPath)
    local jsonObj = JSON.toJSON(jsonStr)

    local jsonStrHide = readFileToStr(appJsonPathHide)
    if jsonStrHide ~= '' then
        local jsonObjHide = JSON.toJSON(jsonStrHide)
        for i=1,#jsonObjHide.InstalledApps,1 do
            table.insert(jsonObj.InstalledApps,jsonObjHide.InstalledApps[i])
        end
    end
    list:clean()

    local baseIndex = 0
    for i=1,#jsonObj.InstalledApps,1 do
        local app = jsonObj.InstalledApps[i]
        -- local btn = list:add_btn(appPathApp .. app.package .. '/' .. app.icon,app.package)
        -- setLabelStyle(btn)
        -- btn:set
        -- btn:add_flag(lvgl.FLAG.CLICKABLE)
        -- btn:onevent(lvgl.EVENT.CLICKED, function(obj, code)
        --     showAppDetailPage(app)
        -- end)
        ---- 112 8 96 8
        local x = 56
        local y = (i - 1 + baseIndex)*104
        local imgIconPath = appPathApp .. app.package .. '/' .. app.icon
        if fileExists(imgIconPath) == false then
            imgIconPath = imgPath('notfound')
        end
        local img = list:Image { src = imgIconPath, x = x, y = y}
        img:set {
            w = 100,
            h = 100
        }
        if app.hideFlag ~= nil and app.hideFlag == true then
            list:Image { src = imgPath('hideicon'), x = x + 100 - 32, y = y + 100 - 32}
        end
        local w, h = img:get_img_size()
        if w ~= 100 then
            local scale = math.floor(256*100/w)
            img:set {
                zoom = scale,
                w = w,
                h = w,
                x = 56 - math.floor((w - 100)/2),
                y = (i - 1 + baseIndex)*104 - math.floor((w - 100)/2)
            }
        end
        img:add_flag(lvgl.FLAG.CLICKABLE)
        img:onevent(lvgl.EVENT.CLICKED, function(obj, code)
            showAppDetailPage(root,app)
        end)
    end

    baseIndex = baseIndex + #jsonObj.InstalledApps

    -- local dir, msg, code = lvgl.fs.open_dir(appPathApp)
    -- if not dir then
    --     print("open dir failed: ", msg, code)
    --     return
    -- end

    -- while true do
    --     local d = dir:read()
    --     if not d then break end
    --     local is_dir = string.byte(d, 1) == string.byte("/", 1)

    --     if is_dir then
    --         local dirName = string.gsub(d,"/","",1)
    --         -- local label = list:add_text(dirName)
    --         local label = list:add_btn(imgPath('back'),dirName)
    --         -- setLabelStyle(label)

    --         label:add_flag(lvgl.FLAG.CLICKABLE)
    --         label:onevent(lvgl.EVENT.CLICKED, function(obj, code)
    --             showAppDetailPage(dirName)
    --         end)
    --     end
    -- end
    -- dir:close()
end

local function createAppPage(rootWd)

    local root = lvgl.Object(rootWd, {
        outline_width = 0,
        border_width = 0,
        pad_all = 0,
        bg_opa = lvgl.OPA(100),
        bg_color = 0,
        align = lvgl.ALIGN.CENTER,
        w = 212,
        h = 520
    })

    root:clear_flag(lvgl.FLAG.SCROLLABLE)
    root:add_flag(lvgl.FLAG.EVENT_BUBBLE)

    
    local title_txt = root:Image { src = imgPath('app_title'), x = 0, y = 33 }


    title_txt:add_flag(lvgl.FLAG.CLICKABLE)
    title_txt:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        showPage(mainPage)
    end)

    -- root:Image { src = imgPath('risk'), x = 89, y = 82 } --跑道屏不显示

    -- appList = lvgl.List(root, {
    --     x = 10,
    --     y = 102,
    --     w = 336,
    --     h = 378,
    --     bg_color = 0,
    --     border_width = 0,
    --     pad_all = 10,
    --     pad_row = 6,
    --     text_font = lvgl.BUILTIN_FONT.MONTSERRAT_32
    -- })
    appList = lvgl.Object(root, {
        x = 0,
        y = 84,
        w = 212,
        h = 340,
        bg_color = 0,
        border_width = 0,
        pad_all = 0,
        text_font = TEXT_FONT
    })

    root:Image { src = imgPath('blackzz'), x = 0, y = 335 }
    local title_back = root:Image { src = imgPath('back'), x = 55, y = 436 }
        title_back:add_flag(lvgl.FLAG.CLICKABLE)
    title_back:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        showPage(mainPage)
    end)

    reloadAppsFunc = function()
        reloadApps(root,appList)
    end

    return root
end

appsPage1 = createAppPage(rootbase)

reloadFileSize = function ()
    local size = getFolderSize(appLsFilePath)

    local rs = ''
    if size > 1024 * 1024 then
        rs = math.floor(size*100/(1024*1024))/100 .. 'M'
    else
        rs = math.floor(size*100/(1024))/100 .. 'K'
    end
    fileSizeWd:set {
        text = rs
    }
end


showPage(mainPage)� 