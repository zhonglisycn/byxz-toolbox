# backend —— 表盘位 Lua 后端（我们的基线）

这里放**我们重写的后端**（`toolbox-backend.lua`，约 1000 行）。原版的 Lua 源码（约 5400 行）
**不随本仓库分发**，仅作为行为与协议的参考。

## 来源与致谢

- 功能与原始实现来自 **Shell++（`com.shell.liangyi`）** 的开发者的表盘位 Lua 后端；
  经许可参考其行为与协议，本目录的代码为独立重写。**致谢原作者。**
- 配套的快应用（本仓库 `src/`）是按同一套协议重写的界面端。
- 容器格式：`resource.bin` 是 Luavgl 容器（`0x1234A55A` 魔数 + 索引表 + 条目区），
  条目 1 的载荷即入口 Lua；解包/回包脚本见 `tools/backend/`，回包做了字节级自检。

## 这份 Lua 干的事

- 用设备自带的 **NSH** 跑命令（`os.execute(cmd .. ' > out')`；NSH **只支持 `>`**，写 `2>` 整行会解析失败）
- `dd if=/dev/fb0` 读帧缓冲截图（每机型一套 stride/skip profile）
- 读 `/proc`、文件浏览与传输、应用管理、LVGL 界面（表盘位的"脸"）
- 与快应用用**请求/结果 JSON 文件**通信（协议见 `docs/backend-protocol.md`）

## 改这份代码的红线

1. **不许新增文件级 `local`。** 它已经贴着 Lua 的 200 个上限，多一个 `local`（哪怕只是
   `local X = '/path'`）整个 chunk 就编译不过，**真机表现是黑屏且没有任何报错**。
   常量写进已有的表、算式内联、逻辑内联进已有函数。
2. **改完必须过语法体检**：`node tools/backend/check-lua.mjs <bin 或 lua>`（fengari / Lua 5.3），
   报错带行号；`tools/backend/build-variants.py` 已把它接进出厂检查。
3. **按固件偏移读写闪存的功能（改"系统版本"字符串那类）不要在手环 10 上启用**：
   偏移是按 10 Pro 固件写死的，对不上就是砖。用原作者自己的 `supported=false` 分支关掉。
