/**
 * 页面 <script> 语法自检：把每个 .ux 的 script 段抽出来交给 node --check。
 * 用途：改页面脚本后快速发现语法错（构建报的 UxLoader 不带文件名，不好定位）。
 * 用法：node tools/check-js.mjs
 */
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import { execFileSync } from 'node:child_process'

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..')
const files = []
for (const dir of fs.readdirSync(path.join(ROOT, 'src/pages'))) {
  const f = path.join(ROOT, 'src/pages', dir, dir + '.ux')
  if (fs.existsSync(f)) files.push(f)
}
files.push(path.join(ROOT, 'src/app.ux'))

let bad = 0
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8')
  const m = src.match(/<script>([\s\S]*?)<\/script>/)
  if (!m) { console.log('  - ' + path.relative(ROOT, f) + '（没有 script）'); continue }
  let i = 0
  const js = m[1].replace(/import\s+.*?\s+from\s+['"][^'"]+['"]/g, () => 'const __imp' + (i++) + ' = {}')
  const tmp = path.join(os.tmpdir(), 'ux-check-' + i + '-' + Date.now() + '.mjs')
  fs.writeFileSync(tmp, js)
  try {
    execFileSync(process.execPath, ['--check', tmp], { stdio: 'pipe' })
    console.log('  ✓ ' + path.relative(ROOT, f))
  } catch (e) {
    bad++
    const msg = String(e.stderr || e.message).split('\n').filter(l => /Error/.test(l))[0] || '语法错误'
    console.log('  ✗ ' + path.relative(ROOT, f) + '  → ' + msg.trim())
  }
  fs.unlinkSync(tmp)
}
console.log(bad === 0 ? '\n脚本语法全部通过' : '\n有 ' + bad + ' 个页面脚本语法有问题')
if (bad) process.exit(1)
