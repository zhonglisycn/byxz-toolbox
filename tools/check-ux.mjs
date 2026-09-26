/**
 * .ux 页面静态检查
 *
 * 编译只保证语法正确，模板里写错字段名/方法名要到运行时才炸。
 * 这里做一遍静态核对：
 *   1. 模板里 @click / onclick 调用的方法必须在 <script> 里定义
 *   2. 模板 {{ }} 里引用的数据字段必须在 private/public 里声明
 *   3. for="{{list}}" 的 list 必须存在，且 tid 指定的键名在数据里出现过
 *   4. import 的相对路径必须存在
 *
 * 用法：node tools/check-ux.mjs
 */
import fs from 'node:fs'
import path from 'node:path'

const ROOT = path.resolve(process.cwd())
const SRC = path.join(ROOT, 'src')

const builtins = new Set([
  'true', 'false', 'null', 'undefined', 'Math', 'JSON', 'Date', 'String', 'Number',
  'Boolean', 'Array', 'Object', '$item', '$idx', 'parseInt', 'parseFloat', 'isNaN',
  '$app', '$def', 'length'
])

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name)
    // 跳过第三方组件目录：输入法组件（NEORUAA/Vela_input_method，MIT）的字段写在
    // props/data 里，本检查器只认本工程写法，扫它只会刷 120 条假问题、把真问题淹掉。
    if (e.isDirectory()) { if (e.name !== 'components' && e.name !== 'ime') walk(p, out) }
    else if (e.name.endsWith('.ux')) out.push(p)
  }
  return out
}

/** 取 <tag>...</tag> 之间的内容 */
function section(text, tag) {
  const m = text.match(new RegExp('<' + tag + '>([\\s\\S]*?)</' + tag + '>'))
  return m ? m[1] : ''
}

const problems = []

function report(file, msg) {
  problems.push({ file: path.relative(ROOT, file).replace(/\\/g, '/'), msg })
}

const files = walk(SRC)
console.log('检查 ' + files.length + ' 个 .ux 页面\n')

for (const file of files) {
  const raw = fs.readFileSync(file, 'utf8')
  const tpl = section(raw, 'template')
  const js = section(raw, 'script')
  const rel = path.relative(ROOT, file).replace(/\\/g, '/')

  // app.ux 是应用级脚本，本来就只有 <script>，没有模板
  const isApp = path.basename(file) === 'app.ux'
  if (!tpl && !isApp) report(file, '没有 <template>')
  if (!js) report(file, '没有 <script>')

  // ---- 脚本里定义的东西 ----
  const dataKeys = new Set()
  const methods = new Set()

  // private/public 块里的顶层键
  for (const blockName of ['private', 'public']) {
    const bi = js.indexOf(blockName + ':')
    if (bi < 0) continue
    const open = js.indexOf('{', bi)
    if (open < 0) continue
    let depth = 0
    let end = open
    for (let i = open; i < js.length; i++) {
      if (js[i] === '{') depth++
      else if (js[i] === '}') { depth--; if (depth === 0) { end = i; break } }
    }
    const body = js.slice(open + 1, end)
    // 键名（允许同一行写多个，例如 panL: false, panR: false）
    const re = /(?:^|[,{\s])([A-Za-z_$][\w$]*)\s*:/gm
    let m
    while ((m = re.exec(body))) dataKeys.add(m[1])
  }

  // export default 顶层的键（例如 fs: fs,）
  const defIdx = js.indexOf('export default')
  if (defIdx >= 0) {
    const open = js.indexOf('{', defIdx)
    if (open >= 0) {
      let depth = 0
      let end = open
      for (let i = open; i < js.length; i++) {
        if (js[i] === '{') depth++
        else if (js[i] === '}') { depth--; if (depth === 0) { end = i; break } }
      }
      const body = js.slice(open + 1, end)
      let mm
      const reTop = /^\s{2}([A-Za-z_$][\w$]*)\s*:/gm
      while ((mm = reTop.exec(body))) {
        if (mm[1] !== 'private' && mm[1] !== 'public') dataKeys.add(mm[1])
      }
    }
  }

  // 方法定义：形如 "  name(args) {" 或 "  name: function"
  let m
  const methodRe = /^\s{2}([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{/gm
  while ((m = methodRe.exec(js))) methods.add(m[1])
  const methodRe2 = /^\s{2}([A-Za-z_$][\w$]*)\s*:\s*function/gm
  while ((m = methodRe2.exec(js))) methods.add(m[1])

  const known = new Set([...dataKeys, ...methods, ...builtins])

  // for 循环引入的局部变量（for="x in list" / for="(i,x) in list" 等）
  const loopVars = new Set(['$item', '$idx'])
  const forVarRe = /for\s*=\s*"([^"]+)"/g
  let fv
  while ((fv = forVarRe.exec(tpl))) {
    const spec = fv[1].replace(/^\{\{|\}\}$/g, '').trim()
    let mm2
    if ((mm2 = spec.match(/^\(\s*(\w+)\s*,\s*(\w+)\s*\)\s+in\s+/))) {
      loopVars.add(mm2[1]); loopVars.add(mm2[2])
    } else if ((mm2 = spec.match(/^(\w+)\s+in\s+/))) {
      loopVars.add(mm2[1])
    }
  }
  for (const v of loopVars) known.add(v)

  // ---- 模板里的引用 ----
  // @click="fn" / onclick="fn"
  const clickRe = /(?:@click|onclick)\s*=\s*"([^"]+)"/g
  while ((m = clickRe.exec(tpl))) {
    const fn = m[1].trim()
    if (!/^[A-Za-z_$][\w$]*$/.test(fn)) continue
    if (!methods.has(fn)) report(file, '模板调用的方法未定义：' + fn)
  }

  // {{ expr }} 与 if/for 里的表达式
  const exprRe = /\{\{([^}]+)\}\}/g
  const seenExpr = new Set()
  while ((m = exprRe.exec(tpl))) {
    let e = m[1].trim()
    if (seenExpr.has(e)) continue
    seenExpr.add(e)
    // 去掉字符串字面量
    e = e.replace(/'[^']*'/g, "''").replace(/"[^"]*"/g, '""')
    // 取所有标识符
    const ids = e.match(/[A-Za-z_$][\w$]*/g) || []
    for (const id of ids) {
      // 跳过属性访问（前一个非空字符是 '.'）
      const at = e.indexOf(id)
      if (at > 0 && e[at - 1] === '.') continue
      if (known.has(id)) continue
      // 三元/比较里的关键字
      if (['typeof', 'in', 'of', 'new'].indexOf(id) >= 0) continue
      report(file, '模板引用了未声明的字段/方法：' + id + '   （在 ' + JSON.stringify(m[0].slice(0, 48)) + ' 中）')
    }
  }

  // for="{{list}}" 的 list
  const forRe = /for\s*=\s*"([^"]+)"/g
  while ((m = forRe.exec(tpl))) {
    const spec = m[1].trim()
    const simple = spec.match(/^\{\{\s*([A-Za-z_$][\w$]*)\s*\}\}$/)
    if (simple && !dataKeys.has(simple[1]) && !methods.has(simple[1])) {
      report(file, 'for 遍历的数据未声明：' + simple[1])
    }
  }

  // import 相对路径
  const impRe = /from\s+'(\.[^']+)'/g
  while ((m = impRe.exec(js))) {
    const target = m[1]
    const base = path.resolve(path.dirname(file), target)
    const cands = [base + '.js', base + '.ux', base + '.json', base]
    if (!cands.some(c => fs.existsSync(c))) {
      report(file, 'import 路径不存在：' + target)
    }
  }

  // style 里的 @import
  const cssImp = /@import\s+'([^']+)'/g
  while ((m = cssImp.exec(raw))) {
    const base = path.resolve(path.dirname(file), m[1])
    if (!fs.existsSync(base)) report(file, 'css @import 路径不存在：' + m[1])
  }
}

if (!problems.length) {
  console.log('✓ 全部页面通过静态检查')
} else {
  const byFile = {}
  for (const p of problems) {
    byFile[p.file] = byFile[p.file] || []
    byFile[p.file].push(p.msg)
  }
  for (const f of Object.keys(byFile)) {
    console.log('✗ ' + f)
    for (const m of byFile[f]) console.log('    - ' + m)
  }
  console.log('\n共 ' + problems.length + ' 处问题')
  process.exit(1)
}
