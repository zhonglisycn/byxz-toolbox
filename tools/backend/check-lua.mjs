/**
 * Lua 语法体检：直接检查 .bin 里那份 Lua（而不是源码文件），
 * 这样"发出去的到底是什么"和"检查的是什么"永远是同一份。
 *
 * 用 fengari（Lua 5.3 的 JS 实现）编译一遍，报出语法错误与行号——后端的 Lua 是 5.3
 * （用到了 utf8.codes），版本正好对上。
 *
 * 用法：node tools/backend-port/check-lua.mjs <文件.bin|文件.lua> [...]
 */
import fs from 'node:fs'
import path from 'node:path'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const F = require(path.resolve('../.luacheck/node_modules/fengari/src/fengari.js'))
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = F

const TOC_OFF = 0x150
const HEAD_END = 0x90E

/** 从 Luavgl .bin 里取出条目 1 的 Lua 载荷 */
function luaFromBin(buf) {
  const off = buf.readUInt32LE(TOC_OFF + 16)
  const size = buf.readUInt32LE(TOC_OFF + 20)
  if (off !== HEAD_END) throw new Error('条目区起点异常: 0x' + off.toString(16))
  const blob = buf.subarray(off, off + size)
  const nl = blob[3]
  const name = blob.subarray(20, 20 + nl).toString('utf8').replace(/\0+$/, '')
  return { name, text: blob.subarray(20 + nl).toString('utf8') }
}

function check(file) {
  const buf = fs.readFileSync(file)
  let name = path.basename(file)
  let text
  if (buf.subarray(0, 4).toString('hex') === '5aa53412') {
    const r = luaFromBin(buf)
    name += ' → ' + r.name
    text = r.text
  } else {
    text = buf.toString('utf8')
  }
  const L = lauxlib.luaL_newstate()
  lualib.luaL_openlibs(L)
  const status = lauxlib.luaL_loadbuffer(L, to_luastring(text), null, to_luastring('@' + path.basename(file)))
  let msg = ''
  if (status !== lua.LUA_OK) {
    msg = to_jsstring(lua.lua_tostring(L, -1))
    lua.lua_pop(L, 1)
  }
  lua.lua_close(L)
  const lines = text.split('\n').length
  if (status === lua.LUA_OK) {
    console.log('  ✓ ' + name + '（' + lines + ' 行，语法通过）')
    return true
  }
  console.log('  ✗ ' + name + '（' + lines + ' 行）')
  console.log('    ' + msg.split('\n')[0])
  return false
}

const files = process.argv.slice(2)
if (!files.length) {
  console.log('用法：node tools/backend-port/check-lua.mjs <文件.bin|文件.lua> [...]')
  process.exit(1)
}
let bad = 0
for (const f of files) if (!check(f)) bad++
console.log(bad ? '\n有 ' + bad + ' 个没通过' : '\n全部通过')
process.exit(bad ? 1 : 0)
