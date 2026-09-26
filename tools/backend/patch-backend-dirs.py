# -*- coding: utf-8 -*-
"""第二道补丁：目录发现（在手环 10 上更关键）。

第一道补丁已经加了候选表与路标函数；这里把它接上：
  1. 候选表追加 EXTRA_DIRS（手环 10 的目录布局可能与 10 Pro 不同）；
  2. 非 Pro 机型不再被硬拽到 Pro 的目录，改用"读到 device_info.json 的那个目录"；
  3. 兜底用路标文件反推目录。

用法：python tools/backend-port/patch-backend-dirs.py
"""
import io

P = 'backend/backend-band10.lua'
s = io.open(P, encoding='utf-8').read()

old_cand = """    local candidates = {
        BAND9_PRO_DIR,         -- Band 9 Pro / Watch S4 / Watch S4 41mm
        BAND10_PRO_DIR,        -- Band 10 Pro
        BAND10_PRO_FILES_DIR,  -- Band 10 Pro fallback
    }"""
new_cand = """    local candidates = {
        BAND9_PRO_DIR,         -- Band 9 Pro / Watch S4 / Watch S4 41mm
        BAND10_PRO_DIR,        -- Band 10 Pro
        BAND10_PRO_FILES_DIR,  -- Band 10 Pro fallback
    }
    -- 手环 10（VelaOS 4.0）目录布局可能不同：候选都试一遍，
    -- 快应用写在哪个目录、就在哪个目录读到它的 device_info.json
    for i = 1, #EXTRA_DIRS do candidates[#candidates + 1] = EXTRA_DIRS[i] end
    local helloDir = resolveTargetDirByHello()
    if helloDir then candidates[#candidates + 1] = helloDir end"""
assert old_cand in s, '候选表没匹配上'
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
        -- 不能按 Pro 的布局硬拽（否则两个组件永远看不见对方）
        chosenDir = selected._sourceDir or chosenDir
    end"""
assert old_pick in s, '设备分支没匹配上'
s = s.replace(old_pick, new_pick, 1)

io.open(P, 'w', encoding='utf-8', newline='\n').write(s)
print('第二道补丁完成：候选表扩容 + 非 Pro 机型用实际目录')
