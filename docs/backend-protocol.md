# 后端协议（从 resource.bin 的 Lua 源码里读出来的）

原版 Shell++ 是**两个组件**：

1. **快应用**（`com.shell.liangyi`，即那个 .rpk）= 管理界面。它把请求写成 JSON 文件放进**自己的私有目录**。
2. **表盘位的 Lua 应用**（`resource.bin`，Luavgl 容器）= 真正干活的：用设备自带的 **NSH** 执行命令、用 `dd` 读 `/dev/fb0` 取截图、读 `/proc` 拿内存/CPU。

两者不共享内存，只靠**请求/结果 JSON 文件**通信（后端在跑一个轮询循环）。所以这套东西可以拆开用：
只要快应用包名与后端约定的目录对得上，换掉任意一半都能继续工作。

## 目录（后端按顺序探测这三个）

```
/data/quickapp/files/<pkg>/     手环 9 Pro / Watch S4 系
/data/data/<pkg>/               手环 10 Pro（当前默认）
/data/files/<pkg>/              10 Pro 备选布局
```

`<pkg>` 就是应用包名——**所以包名必须和后端约定的一致，否则两边看不见对方**。

## 通信文件（一个功能一对）

| 功能 | 请求 / 结果 |
|---|---|
| 终端命令 | `cmd_request.json` / `cmd_result.json` |
| 文件浏览与读取 | `file_request.json` / `file_result.json` |
| 截图 | `screenshot_request.json` / `screenshot_result.json` |
| 悬浮截图 | `screenshot_float_request.json` / `screenshot_float_result.json` |
| 文件传输（传手机） | `file_transfer_request.json` / `file_transfer_result.json` |
| 应用管理 | `app_manager_request.json` / `app_manager_result.json` |
| 系统属性（亮度/设置等） | `property_request.json` / `property_result.json` |
| CPU 监控 | `cpu_monitor_request.json` / `cpu_monitor_result.json` |
| 内存监控 | `memory_monitor_request.json` / `memory_monitor_result.json` |
| 振动 | `vibration_request.json` |
| MCU 算力 | `mcu_bench_request.json` / `mcu_bench_result.json` |

状态/配置文件：`ipc_guard.json`（安全令牌）、`device_info.json`、`lua_extension_settings.json`、
`debug_test_mode.json`、`screenshot_debug.json`、`memory_monitor_state.json`、`cpu_monitor_state.json`、
`screenshots/`（截图目录）、`file_transfer/`。

## 安全令牌（必须带，否则被拒）

后端启动与轮换时写 `ipc_guard.json`：

```json
{ "type": "ipc_guard", "seq": 3, "token": "1769000000-a1b2c3d4", "timestamp": "..." }
```

- `token` = `os.time() .. '-' .. randomHex(8)`，**会滚动**（每次轮换 seq+1）；
- 每个请求都要带 `guard = <当前 token>`，校验失败后端直接丢（日志写「缺少或错误的安全令牌」）；
- 请求还要带 `seq`（自增），结果里回带同一个 `seq` 供配对。

后端还拦了一类命令：**终端命令若触及 IPC 文件名会被拒**（防止把自己的通信文件删了/覆盖了）。

## 请求里用到的字段

`action`（动作名，各功能自己的取值）、`seq`、`guard`、`path`、`cmd`、`property`、`value`、
`dest`、`sessionId`、`packages`、`package`、`operation`、`index`、`offset`、`length`、`chunkSize`、
`content`、`limit`、`all`、`visible`、`noIpc`、`timestamp`。

结果 JSON 的公共字段：`type`、`seq`、`status`（`ok`/`error`）、`message`、`timestamp`。

## 真机细节（源码里注释下来的，值得照抄）

- **命令执行**：`os.execute(cmd .. ' > "outFile"')`——**NSH 只支持 `>` 重定向 stdout**，
  写 `2>`（bash 语法）会让整行解析失败、命令根本不执行；stderr 通常也落在 stdout 里。
  输出上限 32 KB，超了截断加 `... [truncated]`；命令超时 10 秒。
- **截图**：`dd if=/dev/fb0 of=<tmp> bs=<strideBytes> skip=<skipRows> count=<n>`，
  `strideBytes = 屏宽 × 3`；每机型一套 profile（`strideBytes`/`skipRows`/`offsetBytes`/`directDd`），
  还有 `tryReadAt(offsetBytes)` → `tryReadAt(0)` 的兜底；截图请求超时 30 秒，历史保留 20 张。
- 写文件用**原子写**（先写临时文件再改名），避免快应用读到半截 JSON。
- 屏上 UI（Lua 侧）用 LVGL，宽高取 `lvgl.HOR_RES()/VER_RES()`，所以后端自己也是多机型自适应的。
