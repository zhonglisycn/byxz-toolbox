/**
 * 后端冒烟测试：在 fengari 里用桩环境（假 lvgl / 假文件系统 / 假 NSH）把协议真跑一遍。
 *
 * 为什么要写：没有真机，后端一出错在手环上就是"黑屏、没反应"，什么都查不到。
 * 这里把设备接口全换成桩，然后**全部走协议**驱动：
 *   准备 device_info.json → 后端启动（写 ipc_guard.json）→ 带令牌发请求 → 检查结果文件。
 * 目录定位、令牌校验、seq 配对、每个功能的返回，都能在这一步验完。
 *
 * 用法：node tools/backend/test/smoke.mjs
 */
import fs from 'node:fs'
import path from 'node:path'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const F = require(path.resolve('../.luacheck/node_modules/fengari/src/fengari.js'))
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = F

const PRELUDE = fs.readFileSync('tools/backend/test/prelude.lua', 'utf8')
const BACKEND = fs.readFileSync('backend/toolbox-backend.lua', 'utf8')
const DIR = '/data/data/com.shell.liangyi/'

let pass = 0
let fail = 0
const ok = (name, cond, extra) => {
  if (cond) { pass++; console.log('  ✓ ' + name) }
  else { fail++; console.log('  ✗ ' + name + (extra ? '  → ' + extra : '')) }
}

/**
 * 起一个干净的后端实例。
 * 顺序很重要：桩 → 准备文件系统（模拟"快应用先留下 device_info.json"）→ 后端启动 → 断言。
 * 准备动作若写在后端之后，后端启动时就看不到 device_info.json，永远定位不到目录（踩过一次）。
 */
function boot(setupLua, afterLua) {
  const L = lauxlib.luaL_newstate()
  lualib.luaL_openlibs(L)
  const src = PRELUDE + '\n' + (setupLua || '') + '\n' + BACKEND + '\n' + (afterLua || 'return 1')
  const st = lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring('@case'))
  if (st !== lua.LUA_OK) return { error: '编译失败: ' + to_jsstring(lua.lua_tostring(L, -1)) }
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) return { error: '运行出错: ' + to_jsstring(lua.lua_tostring(L, -1)) }

  const api = {
    L,
    /** 求一个 Lua 表达式的值（出错/为 nil 都返回空串，测试里好断言） */
    get(expr) {
      const s = lauxlib.luaL_loadstring(L, to_luastring('return ' + expr))
      if (s !== lua.LUA_OK) return ''
      if (lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) return ''
      const raw = lua.lua_tostring(L, -1)
      lua.lua_pop(L, 1)
      if (!raw) return ''
      try { return to_jsstring(raw) } catch (e) { return String(raw) }
    },
    run(code) {
      const s = lauxlib.luaL_loadstring(L, to_luastring(code))
      if (s !== lua.LUA_OK) return to_jsstring(lua.lua_tostring(L, -1))
      if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) return to_jsstring(lua.lua_tostring(L, -1))
      return null
    },
    /** 触发后端主循环（桩 Timer 把回调存在 TIMER_CB 里） */
    tick() { return api.run('TIMER_CB()') },
    /** 读当前安全令牌（后端启动与轮换时写进 ipc_guard.json） */
    guard() {
      return api.get(`(function() local s = FS['${DIR}ipc_guard.json'] or '' return (s:match('"token":"([^"]+)"') or '') end)()`)
    },
    fs(key) { return api.get(`FS['${key}'] or ''`) },
    /**
     * 按协议发一个请求：取令牌 → 在 JS 里拼 JSON（后端的 jsonEncode 是 local，外面调不到）
     * → 用 Lua 长括号写请求文件（省掉转义）→ 跑一轮主循环 → 回结果 JSON。
     */
    send(feat, req) {
      const body = Object.assign({ guard: api.guard() }, req)
      const e1 = api.run(`FS['${DIR}${feat}_request.json'] = [==[${JSON.stringify(body)}]==]`)
      if (e1) return '❌ 写请求失败: ' + e1
      const e2 = api.run(`FS['${DIR}${feat}_result.json'] = nil`)   // 清掉上一轮结果，避免误判
      const e3 = api.tick()
      if (e3) return '❌ 主循环出错: ' + e3
      return api.fs(DIR + feat + '_result.json')
    },
  }
  return api
}

console.log('=== 后端冒烟测试（fengari + 桩，全部走协议）===')

console.log('\n--- 启动与目录定位 ---')
let b = boot(`FS['${DIR}device_info.json'] = '{"product":"Xiaomi Smart Band 10","model":"M2345B1","updatedAtUnix":"1769000000"}'`)
ok('后端加载并启动无报错', !b.error, b.error)
if (!b.error) {
  ok('写了 ipc_guard.json（含令牌）', b.guard().indexOf('1769') === 0, '令牌="' + b.guard() + '"')
  const st = b.fs(DIR + 'backend_status.json')
  ok('写了 backend_status.json（含屏宽与功能表）', st.indexOf('"sw":212') > 0 && st.indexOf('cmd') > 0, st.slice(0, 100))
  // 界面可见性：每页默认 HIDDEN，启动后必须至少清掉一次，否则真机就是全黑
  ok('界面有可见页面（清过 HIDDEN）', Number(b.get('HIDDEN_CLEARED')) > 0, 'HIDDEN_CLEARED=' + b.get('HIDDEN_CLEARED'))
}

console.log('\n--- 令牌校验 ---')
b = boot(`FS['${DIR}device_info.json'] = '{}'`)
if (!b.error) {
  b.run(`FS['${DIR}cmd_request.json'] = [==[{"cmd":"uname -a","seq":1,"guard":"wrong"}]==]`)
  b.tick()
  const rejected = b.fs(DIR + 'cmd_result.json')
  ok('令牌不对 → 拒绝并说明原因', rejected.indexOf('令牌不正确') > 0 && rejected.indexOf('"seq":1') > 0, rejected.slice(0, 110))
  ok('被拒的请求文件也被消费掉', b.fs(DIR + 'cmd_request.json') === '')
}

console.log('\n--- 命令（NSH）---')
b = boot(`FS['${DIR}tool_hello.json'] = '{}'`)
if (!b.error) {
  const res = b.send('cmd', { cmd: 'uname -a', seq: 7 })
  ok('带令牌 → 拿到 stdout', res.indexOf('Linux miwear') > 0 && res.indexOf('"seq":7') > 0 && res.indexOf('"status":"ok"') > 0, res.slice(0, 130))
  const empty = b.send('cmd', { cmd: '', seq: 8 })
  ok('空命令 → 明确报错', empty.indexOf('"status":"error"') > 0 && empty.indexOf('命令为空') > 0, empty.slice(0, 110))
}

console.log('\n--- 监控（读 /proc）---')
b = boot(`
  FS['${DIR}tool_hello.json'] = '{}'
  FS['/proc/meminfo'] = 'MemTotal:        16400000 kB\\nMemAvailable:     4100000 kB\\nMemFree: 2000000 kB\\n'
  FS['/proc/loadavg'] = '0.35 0.42 0.31 1/120 345\\n'
  FS['/proc/stat'] = 'cpu  100 20 30 850 0 0 0 0 0 0\\n'
`)
if (!b.error) {
  const mem = b.send('memory_monitor', { action: 'status', seq: 11 })
  // 真机（NuttX）的 free 是分池的，要取 Umem：13340924 里用了 11948660 → 89%
  ok('内存：解析 NuttX free 的 Umem（89%）',
    mem.indexOf('"usedPercent":89') > 0 && mem.indexOf('MEM 89%') > 0 && mem.indexOf('free(Umem)') > 0, mem.slice(0, 150))
  ok('内存：总数取自 Umem 而不是别的池', mem.indexOf('"totalKb":13340924') > 0, mem.slice(0, 150))
  const cpu = b.send('cpu_monitor', { action: 'status', seq: 12 })
  ok('CPU：负载 0.35 与忙闲比 15%', cpu.indexOf('"load1":0.35') > 0 && cpu.indexOf('"busyPercent":15') > 0, cpu.slice(0, 150))
}

console.log('\n--- 文件 ---')
b = boot(`
  FS['${DIR}tool_hello.json'] = '{}'
  FS['/tmp/a.txt'] = 'hello'
  FS['/tmp/b.txt'] = 'world'
`)
if (!b.error) {
  const list = b.send('file', { action: 'list', path: '/tmp', seq: 13 })
  ok('列目录：返回 items 与数量', list.indexOf('"count":2') > 0 && list.indexOf('a.txt') > 0, list.slice(0, 150))
  const text = b.send('file', { action: 'text', path: '/tmp/a.txt', seq: 14 })
  ok('读文本：内容正确', text.indexOf('"text":"hello"') > 0, text.slice(0, 120))
  const missing = b.send('file', { action: 'text', path: '/tmp/none.txt', seq: 15 })
  ok('读不存在的文件：给明确错误', missing.indexOf('"status":"error"') > 0 && missing.indexOf('读不到') > 0, missing.slice(0, 120))
}

console.log('\n--- 截图（按屏宽算参数）---')
b = boot(`FS['${DIR}tool_hello.json'] = '{}'`)
if (!b.error) {
  const shot = b.send('screenshot', { dest: 't.raw', seq: 21 })
  ok('截图：stride = 屏宽×3 = 636', shot.indexOf('"strideBytes":636') > 0, shot.slice(0, 150))
  ok('截图：字节数 = 636×520 = 330720', shot.indexOf('"bytes":330720') > 0, shot.slice(0, 150))
  ok('截图：结果带全部参数（便于真机标定）', shot.indexOf('"skipRows":520') > 0 && shot.indexOf('"bpp":3') > 0, shot.slice(0, 150))
}

console.log('\n----------------------------------------')
console.log(fail === 0 ? '全部通过：' + pass + ' 项' : '失败 ' + fail + ' 项 / 通过 ' + pass + ' 项')
process.exit(fail === 0 ? 0 : 1)
