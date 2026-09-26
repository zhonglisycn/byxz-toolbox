# 工具箱（byxz）

小米手环 10（Vela 快应用，212×520 胶囊屏）上的**工具箱**。功能蓝本取自手环工具类应用
**Shell++（`com.shell.liangyi`）**，在**手环 10** 上重新实现——界面端与后端都是本项目的独立重写，
原版未开源，**致谢原作者 IKUN_CXKPRO**（米坛主页：https://www.bandbbs.cn/members/323974/ ）。

- 产物：`dist/工具箱_byxz.bin`（约 210 KB）
- 包名：`com.byxz.toolbox`，版本 1.2.0
- 后端：`dist/后端_byxz_v0.4.2.bin`（表盘位 Lua 应用，48 KB）

## 1. 双组件架构

快应用沙箱拿不到的东西（跑系统命令、读 `/proc`、读帧缓冲截图）靠一个**装在表盘位的 Lua 后端**做，
两边用**请求/结果 JSON 文件**通信：

- 目录按包名走，每个请求带 `ipc_guard.json` 里滚动的安全令牌 + 自增 `seq`，10 秒超时、32KB 输出上限、原子写；
- 协议细节见 `docs/backend-protocol.md`，客户端实现在 `src/common/core/bridge.js`；
- 后端源码：`backend/toolbox-backend.lua`（本项目重写，约 1000 行；原版约 5400 行）。
  **原版的 Lua 源码不随本仓库分发。**

## 2. 功能

| 页面 | 内容 |
| --- | --- |
| 终端 | 自己敲命令执行（QWERTY 键盘）；**命令历史**（最近 12 条点一下填回）、**脚本**（把常用命令存起来一键跑） |
| 监控 | CPU 负载 / 内存（NuttX 分池）/ 进程列表，可浮动显示 |
| 文件 | 浏览、看文本、十六进制、复制移动删除；**就地编辑**（覆盖写，按两次确认） |
| 更多工具 | `/proc` 速览、**算力跑分 + 历次成绩柱状图**、截图 |
| 存储分析 | 各应用占用排行（占比条）+ 点开看详情，可导出清单文本 |
| 本机信息 | 内核 / 内存池 / 分区表 / CPU 负载 / free / mount / df 一页看全，可汇总成文本 |
| 系统管家 | 内存·CPU·进程三项体检 + **只提示不动手**的处理建议，可一键清本应用缓存 |
| 应用管理 | 读取已装应用；**隐藏 / 恢复 / 删除**（要 confirm，先备份 `apps.json`） |
| 系统属性 | 读 `getprop` 全量，选中一键改 0/1/清空/反转（要 confirm） |
| 后端日志 | 后端侧日志回读，排查通信问题 |
| 后端诊断 | 六步自检：设备信息 → 可写目录 → `device_info.json` → 令牌 → 真发一条命令 |
| 设置 / 关于 | 按键振动、界面留白、**导出配置与用法（文本）**、版本与许可 |

**红线**：不实现闪存读写（按偏移读写固件会变砖）；改已装应用、重启系统这类操作一律要 `confirm`。

## 2.1 版本历史

- **v1.2.0**：新增命令历史与脚本、文件就地编辑、存储分析、本机信息、系统管家、跑分配置历史曲线、配置导出（共 15 页）
- **v1.1.x**：终端页键盘修好（几何按 212px 重排、按键 `flex-shrink:0`、按需挂载）；后端重写为多页 LVGL 界面；致谢点名作者

## 3. 工程要点

- **多机型适配层**：一套代码跑 192 / 212 / 336 宽；启动读 `device.getInfo()` 算出档位与留白、字号，
  页面只读结果，配合媒体查询调整行高与按钮尺寸。原版按 336 写死，在 212 上"部分点不到"。
- **胶囊屏几何**：212×520、上下各是半径 106px 的半圆；全宽内容可用区约 174×420，
  键盘要把整排键停在弧区以外（`tools/check-kb-layout.mjs` 里有断言）。
- **键盘**：组件取自 [NEORUAA/Vela_input_method](https://github.com/NEORUAA/Vela_input_method)（MIT）。
  用到手环 10 上要改三处：几何按 212px 屏宽重排（原作者按 192 摆的，会整体偏左）、
  按键加 `flex-shrink:0`（否则 10 个 60px 的键被压成约 21px，只看得见行尾）、
  按需挂载（`if` + `hide={{false}}`）——作者自己在源码里标注 `hide` watcher 在部分设备不可靠，
  这正是"呼不出键盘"的原因。
- **设备是 NuttX，不是 Linux**：`free` 是分池输出（取 `Umem:` 行），CPU 负载读 `/proc/cpuload`，
  进程列表走 `ps`（`/proc/<pid>/` 里没有 `VmRSS`）。
- **Lua 端的坑**：原版后端贴着 200 个文件级 `local` 上限，多一个 `local` 就整块编译失败、真机黑屏且无报错；
  Lua 模式串里不能写转义换行（用 `gmatch('[^%c]+')` 切行）。

## 4. 构建与检查

```bash
npm install
bash tools/build-bin.sh          # 静态检查 + 编译，输出 dist/工具箱_byxz.bin
bash tools/run-tests.sh          # 内核测试 + 键盘几何自检
bash tools/backend/test/run.sh   # 后端：fengari 语法体检 + 协议冒烟（桩 lvgl / 假 FS / 假 NSH）
```

`tools/set-pkg.sh` 可在自有包名与"与后端互通"包名之间一键切换。

## 5. 致谢与许可

- **Shell++（`com.shell.liangyi`）** by **IKUN_CXKPRO**（米坛主页：https://www.bandbbs.cn/members/323974/ ）：
  功能蓝本与后端协议来源。该项目未开源，本项目为**独立重写实现**，经许可参考其行为并致谢作者。
- **[NEORUAA/Vela_input_method](https://github.com/NEORUAA/Vela_input_method)**（MIT）：`src/components/InputMethod/`
  输入法组件，保留其许可证与署名，本仓库只做几何与性能改动。
- **米环管理 3.0**：隐藏/删除应用的机制（搬 `apps.json` 的 `InstalledApps` / `HiddenApps`）与
  Luavgl 容器格式的参考。
- 本工程代码以 **MIT** 许可发布，见 `LICENSE`。
