/**
 * 与「表盘位 Lua 后端」通信（文件 IPC）
 *
 * 原版是两个组件：快应用负责界面，表盘位的 Lua 应用负责干活（跑 NSH 命令、读 /dev/fb0 截图、
 * 读 /proc）。两者只靠目录里的请求/结果 JSON 文件通信，后端在跑轮询循环。
 * 协议细节见 docs/backend-protocol.md。
 *
 * 用法：
 *   bridge.setPkg('com.shell.liangyi')
 *   bridge.findDir(function (ok) { ... })          // 探测后端目录
 *   bridge.call('cmd', { action: 'run', cmd: 'free' }, function (err, res) { ... })
 *
 * 注意：后端按**包名**找目录，所以包名必须和它约定的一致（见文档）。
 */
import file from '@system.file'
import device from '@system.device'

// Vela 快应用只能写自己的私有目录，用的就是 internal:// 这套 URI；
// 原版快应用也是这么写的（internal://files/cmd_result.json 等）。
// 千万别用 /data/... 绝对路径去写——沙箱直接拒绝（实测三个候选目录全写不进）。
const CANDIDATES = [
  'internal://files/',
  'internal://cache/',
  'internal://',
  '/data/data/{pkg}/',
  '/data/files/{pkg}/'
]

let PKG = 'com.byxz.toolbox'
let DIR = ''
let TOKEN = ''
let SEQ = 0
let busy = false

export function setPkg(p) { PKG = p; DIR = '' }
export function pkg() { return PKG }
export function dir() { return DIR }
export function hasGuard() { return !!TOKEN }

/**
 * 探测通信目录：**用写测试**，不用猜。
 *
 * 目录布局随系统版本变（Pro / 手环 10 / 手环 9 都不同），但有一条是确定的：
 * 快应用只能写自己包名下的目录。所以挨个试写一个小文件，写得进的那个就是我们的目录，
 * 也就是后端该去读的地方——探测结果顺便当"向后端报到"用（见 announce）。
 */
export function findDir(cb) {
  if (DIR) { cb(true); return }
  let i = 0
  const next = function () {
    if (i >= CANDIDATES.length) { cb(false); return }
    const cand = CANDIDATES[i].replace('{pkg}', PKG)
    i++
    try {
      file.writeText({
        uri: cand + 'tool_hello.json',
        text: JSON.stringify({ pkg: PKG, at: String(Math.floor(Date.now() / 1000)) }),
        success: function () { DIR = cand; cb(true) },
        fail: function () { next() }
      })
    } catch (e) { next() }
  }
  next()
}

/**
 * 向后端报到：写 device_info.json（后端靠它定位目录与识别机型）+ 路标文件。
 * 后端启动时会轮询这几个目录找 device_info.json，所以这一步越早越好。
 */
export function announce(cb) {
  const self = this
  let info = null
  try {
    device.getInfo({
      success: function (r) { info = r; go() },
      fail: function () { go() }
    })
  } catch (e) { go() }

  function go() {
    findDir(function (ok) {
      if (!ok) { if (cb) cb('没有可写的目录'); return }
      const r = info || {}
      const body = {
        product: r.model || r.product || '',
        model: r.model || '',
        brand: r.brand || '',
        osVersion: r.osVersionName || '',
        screenWidth: r.screenWidth || 0,
        screenHeight: r.screenHeight || 0,
        screenShape: r.screenShape || '',
        appPkg: PKG,
        updatedAtUnix: String(Math.floor(Date.now() / 1000))
      }
      writeJson(DIR + 'device_info.json', body, function (err) {
        if (cb) cb(err || null)
      })
    })
  }
}

function readJson(uri, cb) {
  try {
    file.readText({
      uri: uri,
      success: function (d) {
        try { cb(null, JSON.parse(d.text)) } catch (e) { cb('结果不是合法 JSON', null) }
      },
      fail: function (d, code) { cb('读不到 ' + uri + '（' + code + '）', null) }
    })
  } catch (e) { cb('文件接口不可用', null) }
}

function writeJson(uri, obj, cb) {
  try {
    file.writeText({
      uri: uri,
      text: JSON.stringify(obj),
      success: function () { cb(null) },
      fail: function (d, code) { cb('写不进 ' + uri + '（' + code + '）') }
    })
  } catch (e) { cb('文件接口不可用') }
}

/** 读安全令牌（后端会轮换，每次调用都重读一次最稳） */
export function refreshGuard(cb) {
  if (!DIR) { findDir(function (ok) { if (!ok) { cb('没找到后端目录'); return } refreshGuard(cb) }); return }
  readJson(DIR + 'ipc_guard.json', function (err, o) {
    if (err) { cb('后端还没启动（读不到 ipc_guard.json）'); return }
    TOKEN = o && o.token ? String(o.token) : ''
    cb(TOKEN ? null : '令牌为空')
  })
}

/**
 * 通用调用：写 <name>_request.json，然后轮询 <name>_result.json，直到 seq 对上或超时。
 * cb(err, result)
 */
export function call(name, req, cb) {
  if (busy) { cb('上一次请求还没回来'); return }
  const start = function () {
    busy = true
    SEQ++
    const seq = SEQ
    const body = {}
    for (const k in req) body[k] = req[k]
    body.seq = seq
    body.guard = TOKEN
    body.timestamp = String(Math.floor(Date.now() / 1000))

    const reqFile = DIR + name + '_request.json'
    const resFile = DIR + name + '_result.json'
    writeJson(reqFile, body, function (e1) {
      if (e1) { busy = false; cb(e1); return }
      let waited = 0
      const poll = function () {
        if (waited > 12000) { busy = false; cb('后端没有响应（超过 12 秒）'); return }
        waited += 300
        readJson(resFile, function (e2, o) {
          if (!e2 && o && Number(o.seq) === seq) { busy = false; cb(null, o); return }
          setTimeout(poll, 300)
        })
      }
      setTimeout(poll, 200)
    })
  }

  if (!DIR) {
    findDir(function (ok) {
      if (!ok) { cb('没找到后端目录（后端未安装或包名不一致）'); return }
      refreshGuard(function (e) { if (e) { cb(e); return } start() })
    })
    return
  }
  refreshGuard(function (e) { if (e) { cb(e); return } start() })
}

/** 读后端留下的状态文件（能读到 = 两边用的是同一个目录） */
export function readBackendStatus(cb) {
  if (!DIR) { findDir(function (ok) { if (!ok) { cb('没有可写目录'); return } readBackendStatus(cb) }); return }
  readJson(DIR + 'backend_status.json', function (err, o) {
    if (err) { cb('读不到 backend_status.json', null); return }
    cb(null, o)
  })
}

/** 后端在不在线：给「关于」页显示用 */
export function status(cb) {
  findDir(function (ok) {
    if (!ok) { cb({ online: false, why: '没找到后端目录' }); return }
    readJson(DIR + 'ipc_guard.json', function (err, o) {
      if (err) { cb({ online: false, why: '目录在，但读不到 ipc_guard.json' }); return }
      cb({ online: !!o && !!o.token, why: '', dir: DIR, token: o ? String(o.token) : '' })
    })
  })
}

/* ---------- 常用功能的薄封装 ----------
   动作名都是从后端 Lua 源码里核对过的（不是猜的）：
     cmd        { cmd, noIpc }                     命令，没有 action 字段
     file       action = list | text | info | hex | image | copy | move | delete | write
     cpu/memory action = monitor_start | monitor_stop | clear | float_on | float_off | status
     app_manager action = apps | app_size | icon_cache_reset | set_visible | delete | reboot_system
     property   action = get | set（property 字段决定查什么，如 cache_status / cache_clear）
               另有 about_status/about_set/about_restore —— 那是**按固件偏移读写闪存**的，
               手环 10 上一律不调用（偏移对不上就是砖），所以这里不封装。
   结果里命令输出在 stdout，列表在 items。
*/

/** 跑一条命令（后端用 NSH 执行；只有 stdout 会被捕获，2> 不支持） */
export function runCmd(command, cb) {
  call('cmd', { cmd: command }, cb)
}

/** 文件：列表 / 读文本 / 详情 */
export function listDir(path, cb) { call('file', { action: 'list', path: path }, cb) }
export function readText(path, cb) { call('file', { action: 'text', path: path }, cb) }
export function fileInfo(path, cb) { call('file', { action: 'info', path: path }, cb) }

/** 监控：开始 / 停止 / 状态（悬浮层那两项先不做，免得挡界面） */
export function cpuMonitor(action, cb) { call('cpu_monitor', { action: action || 'status' }, cb) }
export function memoryMonitor(action, cb) { call('memory_monitor', { action: action || 'status' }, cb) }

/** 缓存：查状态 / 清理（走后端的 property 通道） */
export function cacheStatus(cb) { call('property', { action: 'cache_status' }, cb) }
export function cacheClear(cb) { call('property', { action: 'cache_clear' }, cb) }

/** 已安装应用列表 */
export function appList(cb) { call('app_manager', { action: 'apps' }, cb) }

export default {
  setPkg, pkg, dir, hasGuard, findDir, announce, refreshGuard, call, status, readBackendStatus,
  runCmd, listDir, readText, fileInfo, cpuMonitor, memoryMonitor, cacheStatus, cacheClear, appList
}
