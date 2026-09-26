/**
 * .ux 页面预览渲染器
 *
 * 目的：编译只保证语法正确，看不到"字体看不见/错位/重叠"这类布局问题。
 * 这里把 .ux 用**真实的核心逻辑**跑出数据（脚本真的执行 onInit/onReady），
 * 再渲染成 HTML，在 212×520 的胶囊屏里用 headless Edge 截图。
 *
 * 用法：
 *   node tools/preview.mjs              # 渲染全部页面
 *   node tools/preview.mjs xq index     # 只渲染指定页面
 * 产物：tools/preview/out/<page>.html 与 <page>.png（PNG 由 tools/preview.sh 生成）
 *
 * 说明：这是**近似**渲染。Vela 的 text/flex 行为与浏览器接近但不等价，
 * 用于发现"看不见/压字/溢出"，不能当作像素级验收。
 */
import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..')
const PRE = path.join(ROOT, 'tools/preview')
const TMP = path.join(PRE, '.work')
const OUT = path.join(PRE, 'out')

fs.mkdirSync(OUT, { recursive: true })
fs.rmSync(TMP, { recursive: true, force: true })
fs.mkdirSync(path.join(TMP, 'core'), { recursive: true })
fs.writeFileSync(path.join(TMP, 'package.json'), '{ "type": "module" }')

const SYS_URL = pathToFileURL(path.join(PRE, 'stub-sys.mjs')).href

/* ---------- 把 src/common/core 拷到 .work/core（并改写 @system 引用） ---------- */
const CORE = path.join(ROOT, 'src/common/core')
fs.mkdirSync(path.join(TMP, 'core', 'content'), { recursive: true })
function copyCore(dir, rel) {
  for (const f of fs.readdirSync(dir)) {
    const full = path.join(dir, f)
    if (fs.statSync(full).isDirectory()) {
      fs.mkdirSync(path.join(TMP, 'core', rel, f), { recursive: true })
      copyCore(full, path.join(rel, f))
      continue
    }
    if (!f.endsWith('.js')) continue
    let t = fs.readFileSync(full, 'utf8')
    t = rewriteSys(t)
    // Node ESM 需要显式扩展名
    t = t.replace(/from\s+'(\.[^']*)'/g, (all, spec) => /\.(js|mjs|json)$/.test(spec) ? all : "from '" + spec + ".js'")
    fs.writeFileSync(path.join(TMP, 'core', rel, f), t)
  }
}
copyCore(CORE, '')

/** 把 @system.xxx 的默认导入改写成桩模块的命名导入 */
function rewriteSys(js) {
  // 原版页面用的是双引号，这里单双引号都要认
  return js.replace(/import\s+([\w$]+)\s+from\s+['"]@system\.([\w]+)['"]/g,
    (all, local, name) => "import { " + name + " as " + local + " } from '" + SYS_URL + "'")
}

/* ---------- .ux 解析 ---------- */
function section(text, tag) {
  const m = text.match(new RegExp('<' + tag + '>([\\s\\S]*?)</' + tag + '>'))
  return m ? m[1] : ''
}

/** 极简 HTML 解析：只支持本工程用到的写法（div/text/image/scroll/input + 属性 + 文本） */
function parseNodes(html) {
  const nodes = []
  let i = 0
  const stack = [{ children: nodes }]
  const VOID = new Set(['br'])
  while (i < html.length) {
    const lt = html.indexOf('<', i)
    if (lt < 0) {
      const t = html.slice(i)
      if (t.trim()) stack[stack.length - 1].children.push({ text: t })
      break
    }
    if (lt > i) {
      const t = html.slice(i, lt)
      if (t.trim()) stack[stack.length - 1].children.push({ text: t })
    }
    const gt = html.indexOf('>', lt)
    if (gt < 0) break
    let tag = html.slice(lt + 1, gt).trim()
    const selfClose = tag.endsWith('/')
    if (selfClose) tag = tag.slice(0, -1).trim()
    if (tag.startsWith('/')) {
      stack.pop()
      i = gt + 1
      continue
    }
    // 注释
    if (tag.startsWith('!--')) {
      const end = html.indexOf('-->', lt)
      i = end < 0 ? html.length : end + 3
      continue
    }
    const nameMatch = tag.match(/^([\w-]+)/)
    const name = nameMatch ? nameMatch[1] : 'div'
    const attrs = {}
    const attrRe = /([@:\w-]+)\s*=\s*"([^"]*)"/g
    let m
    while ((m = attrRe.exec(tag))) attrs[m[1]] = m[2]
    const node = { tag: name, attrs: attrs, children: [] }
    stack[stack.length - 1].children.push(node)
    if (!selfClose && !VOID.has(name)) {
      stack.push(node)
    }
    i = gt + 1
  }
  return nodes
}

/* ---------- 表达式求值 ---------- */
const exprCache = {}
function makeEval(expr, keys) {
  const cacheKey = keys.join(',') + '|' + expr
  if (exprCache[cacheKey]) return exprCache[cacheKey]
  let fn
  try {
    fn = new Function(...keys, '$item', '$idx', 'return (' + expr + ')')
  } catch (e) {
    fn = () => '‹expr错误:' + expr + '›'
  }
  exprCache[cacheKey] = fn
  return fn
}

function evalExpr(expr, ctx) {
  const keys = Object.keys(ctx).filter(k => /^[A-Za-z_$][\w$]*$/.test(k))
  try {
    return makeEval(expr, keys)(...keys.map(k => ctx[k]), ctx.$item, ctx.$idx)
  } catch (e) {
    return undefined
  }
}

function interpolate(str, ctx) {
  return String(str).replace(/\{\{([^}]+)\}\}/g, (all, e) => {
    const v = evalExpr(e.trim(), ctx)
    return v === undefined || v === null ? '' : String(v)
  })
}

/* ---------- 渲染 ---------- */
const TAGMAP = { text: 'span', image: 'img', scroll: 'div', progress: 'div', input: 'button', swiper: 'div', stack: 'div', list: 'div' }

/** /common/xxx -> 工程内真实文件（预览用） */
const SRC_DIR = path.join(ROOT, 'src')
function appAsset(p) {
  if (p && p.charAt(0) === '/') {
    return pathToFileURL(path.join(SRC_DIR, p.slice(1))).href
  }
  return p
}

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

function renderChildren(children, ctx) {
  let out = ''
  let branchTaken = false
  for (const ch of children) {
    if (ch.text) { out += renderNode(ch, ctx, true); continue }
    const a = ch.attrs
    if (a.if !== undefined || a.elif !== undefined || a.else !== undefined) {
      let cond
      if (a.else !== undefined) cond = !branchTaken
      else if (a.elif !== undefined) cond = !branchTaken && !!evalExpr(interpolate(a.elif, ctx), ctx)
      else cond = !!evalExpr(interpolate(a.if, ctx), ctx)
      if (cond) {
        branchTaken = true
        out += renderNode(ch, ctx, false)
      }
      continue
    }
    branchTaken = false
    out += renderNode(ch, ctx, false)
  }
  return out
}

function renderNode(node, ctx, isText) {
  if (isText) return esc(interpolate(node.text, ctx))

  const a = node.attrs
  // for 循环
  if (a.for !== undefined) {
    const spec = a.for.replace(/^\{\{|\}\}$/g, '').trim()
    let listExpr = spec
    let itemName = '$item'
    let idxName = '$idx'
    let m
    if ((m = spec.match(/^\(\s*(\w+)\s*,\s*(\w+)\s*\)\s+in\s+(.+)$/))) {
      idxName = m[1]; itemName = m[2]; listExpr = m[3]
    } else if ((m = spec.match(/^(\w+)\s+in\s+(.+)$/))) {
      itemName = m[1]; listExpr = m[2]
    }
    const list = evalExpr(listExpr, ctx)
    if (!list || !list.length) return ''
    const clone = { tag: node.tag, attrs: { ...a }, children: node.children }
    delete clone.attrs.for
    delete clone.attrs.tid
    let out = ''
    for (let k = 0; k < list.length; k++) {
      out += renderNode(clone, { ...ctx, [itemName]: list[k], [idxName]: k }, false)
    }
    return out
  }

  const tag = TAGMAP[node.tag] || node.tag
  let attrStr = ''
  for (const k in a) {
    if (k === 'if' || k === 'elif' || k === 'else' || k === 'tid' || k === 'class') continue
    if (k === '@click' || k === 'onclick') { attrStr += ' data-click="' + esc(a[k]) + '"'; continue }
    if (k === 'type' && tag === 'button') continue
    let v = interpolate(a[k], ctx)
    if (k === 'src') {
      if (!v) continue
      v = appAsset(v)                       // /common/xxx -> 真实文件路径
    }
    if (tag === 'button' && k === 'value') continue
    attrStr += ' ' + k + '="' + esc(v) + '"'
  }
  // class 只输出一次（Vela 的 text/image 在浏览器里需要额外的标记类）
  const userCls = node.attrs.class ? interpolate(node.attrs.class, ctx) : ''
  const extra = tag === 'span' ? 'ux-text' : (tag === 'img' ? 'ux-img' : '')
  const clsList = [extra, userCls].filter(Boolean).join(' ')
  const cls = clsList ? ' class="' + esc(clsList) + '"' : ''

  const inner = renderChildren(node.children, ctx)
  if (tag === 'img') {
    return '<img' + cls + attrStr + '>'
  }
  if (tag === 'button') {
    return '<button' + cls + attrStr + '>' + (inner || esc(interpolate(node.attrs.value || '', ctx))) + '</button>'
  }
  return '<' + tag + cls + attrStr + '>' + inner + '</' + tag + '>'
}

/* ---------- CSS ---------- */
function resolveCss(cssText, baseDir, depth = 0) {
  if (depth > 4) return cssText
  return cssText.replace(/@import\s+'([^']+)'\s*;?/g, (all, p) => {
    const f = path.resolve(baseDir, p)
    if (!fs.existsSync(f)) return '/* 缺失: ' + p + ' */'
    return resolveCss(fs.readFileSync(f, 'utf8'), path.dirname(f), depth + 1)
  })
}

function normalizeCss(css) {
  // Vela 元素选择器 -> 预览用的类选择器
  return css
    .replace(/(^|\})\s*text\s*\{/g, '$1 .ux-text {')
    .replace(/(^|\})\s*image\s*\{/g, '$1 .ux-img {')
    .replace(/(\d+)dp/g, '$1px')
}

/* ---------- 页面脚本求值 ---------- */
async function loadScript(uxPath, name) {
  const raw = fs.readFileSync(uxPath, 'utf8')
  let js = section(raw, 'script')
  js = rewriteSys(js)
  // ./xxx/common/core/<模块> 与 ./xxx/common/core/content/<模块> 都要指到 .work/core 下
  js = js.replace(/from\s+['"](\.[^'"]*)\/core\/([\w./-]+)['"]/g, (all, pre, mod) => {
    return "from '" + pathToFileURL(path.join(TMP, 'core', mod + '.js')).href + "'"
  })
  const f = path.join(TMP, 'page-' + name + '.mjs')
  fs.writeFileSync(f, js)
  const mod = await import(pathToFileURL(f).href + '?t=' + Date.now())
  return mod.default
}

function instantiate(def, appDef) {
  const vm = {}
  for (const k in def) {
    if (k === 'private' || k === 'public') continue
    vm[k] = def[k]
  }
  if (def.private) for (const k in def.private) vm[k] = def.private[k]
  if (def.public) for (const k in def.public) vm[k] = def.public[k]
  Object.defineProperty(vm, '$app', { value: { $def: appDef }, enumerable: false })
  return vm
}

/* ---------- 主流程 ---------- */
const ALL_PAGES = ['home', 'calc', 'eq', 'plot', 'about']

/* 本工程是纯工具类应用：页面不依赖任何"局内状态"，$app.$def 只有三个开关，
   所以不需要像《人生重开》那样预先造一局数据。 */
const HOOKS = {}
const PRE_HOOKS = {}

const wanted = process.argv.slice(2)
const pages = wanted.length ? wanted : ALL_PAGES

// 加载 app.ux（页面里会访问 this.$app.$def）
const appDefRaw = await loadScript(path.join(ROOT, 'src/app.ux'), 'app')
const appDef = instantiate(appDefRaw, null)
if (appDef.onCreate) appDef.onCreate()

const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, 'src/manifest.json'), 'utf8'))

for (const p of pages) {
  const real = p
  const uxPath = path.join(ROOT, 'src/pages', real, real + '.ux')
  if (!fs.existsSync(uxPath)) { console.log('跳过（不存在）: ' + p); continue }
  const raw = fs.readFileSync(uxPath, 'utf8')
  const tpl = section(raw, 'template')
  const pageCss = section(raw, 'style')
  const def = await loadScript(uxPath, real)
  const vm = instantiate(def, appDef)
  try {
    if (PRE_HOOKS[p]) PRE_HOOKS[p](appDef)
    if (vm.onInit) vm.onInit()
    if (vm.onReady) vm.onReady()
    if (HOOKS[p]) HOOKS[p](vm)
  } catch (e) {
    console.log('⚠ ' + p + ' 生命周期报错: ' + e.message)
  }

  const tree = parseNodes(tpl)
  let body = ''
  try {
    body = renderChildren(tree, vm)
  } catch (e) {
    body = '<pre style="color:#f66">渲染失败: ' + esc(e.message) + '</pre>'
  }

  const baseCss = resolveCss(fs.readFileSync(path.join(ROOT, 'src/common/style/base.css'), 'utf8'),
    path.join(ROOT, 'src/common/style'))
  const ownCss = resolveCss(pageCss, path.dirname(uxPath))

  const html = `<!doctype html>
<html><head><meta charset="utf-8"><title>${p}</title>
<style>
  html,body { margin:0; padding:0; background:#2b2f36; }
  * { box-sizing: border-box; }
  /* 关键：Vela 里 div 默认就是 flex 容器（浏览器里不是），不补这条布局会完全不对 */
  div, scroll, list, list-item, stack, swiper, progress { display: flex; }
  /* 滚动区必须能收缩：浏览器里 flex item 默认 min-height:auto，会被内容顶高，
     把后面的底部按钮/翻页条挤出屏幕；真机 Yoga 的最小尺寸是 0，本来就会收缩。
     不补这条，预览会误报"底部按钮看不见"。 */
  scroll, .scroll { min-height: 0; overflow: hidden; }
  .ux-text { display: inline-block; }
  .ux-img { display: block; }
  #dev { position: relative; width: 212px; height: 520px; overflow: hidden; background: #0d0f12; font-family: "Microsoft YaHei", "Noto Sans SC", sans-serif; }
  /* 设备上页面根节点的父级是框架给的屏幕容器（不是 flex 容器），页面根的 height:100%
     才能真正生效、flex:1 的滚动区才会收缩，底部按钮才留在屏内。上面那条 div{display:flex}
     会把 #dev 也变成 flex 容器，导致页面根被内容撑高、底部按钮被裁到屏外——预览就成了假象。 */
  #dev { display: block; }
  #dev * { font-family: inherit; }
${normalizeCss(baseCss)}
${normalizeCss(ownCss)}
  /* 胶囊屏遮罩：圆角外的部分涂成机身色，模拟四角被切掉 */
  /* 真机是胶囊屏：上下是半径 106px 的半圆（不是圆角矩形）。
     遮罩必须一致，否则预览会把被玻璃切掉的内容也画出来，骗自己。 */
  #mask { position:absolute; left:0; top:0; width:212px; height:520px; border-radius:106px;
          box-shadow: 0 0 0 400px #2b2f36; pointer-events:none; }
</style></head>
<body><div id="dev">${body}<div id="mask"></div></div></body></html>`

  const outHtml = path.join(OUT, p + '.html')
  fs.writeFileSync(outHtml, html)
  console.log('已渲染 ' + p + ' -> ' + path.relative(ROOT, outHtml))
}
