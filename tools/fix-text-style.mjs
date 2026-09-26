/**
 * 修正 .ux 里"看不见的文字"
 *
 * 问题：Vela 里 <text> 不继承父容器的 color，按钮/弹窗里的文字如果没写颜色，
 * 就会用默认色（深色），压在深色按钮上等于看不见。
 *
 * 做法：解析模板，维护祖先栈；
 *   · 文字自身若已有"定义颜色的类"（base.css / 页面 CSS 里设了 color）→ 不动
 *   · 否则按上下文补一个内联 color：
 *       在按钮类祖先里 → #ffffff
 *       在弹窗里（标题/正文）→ 深棕
 *       其它 → #e8e8e8
 *
 * 用法：node tools/fix-text-style.mjs [--check]
 */
import fs from 'node:fs'
import path from 'node:path'

const ROOT = process.cwd()
const CHECK = process.argv.indexOf('--check') >= 0

/** 从 CSS 里抽出"类名 -> color" */
function colorMap(css) {
  const m = {}
  const re = /\.([\w-]+)\s*\{([^}]*)\}/g
  let x
  while ((x = re.exec(css))) {
    const body = x[2]
    const c = body.match(/(?:^|[;\s])color\s*:\s*([^;]+)/)
    if (c) m[x[1]] = c[1].trim()
  }
  return m
}

const baseCss = fs.readFileSync(path.join(ROOT, 'src/common/style/base.css'), 'utf8')
const BASE_COLORS = colorMap(baseCss)

const BTN_CLASSES = ['btn', 'btn-primary', 'btn-warn', 'btn-quiet', 'dialog-btn', 'dialog-btn-ok', 'dialog-btn-cancel', 'pad-btn']

function parseStyle(s) {
  const out = {}
  if (!s) return out
  for (const part of s.split(';')) {
    const i = part.indexOf(':')
    if (i < 0) continue
    out[part.slice(0, i).trim()] = part.slice(i + 1).trim()
  }
  return out
}

function styleStr(o) {
  return Object.keys(o).map(k => k + ': ' + o[k]).join('; ')
}

let changedFiles = 0
let changedTags = 0

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) walk(p, out)
    else if (e.name.endsWith('.ux')) out.push(p)
  }
  return out
}

for (const file of walk(path.join(ROOT, 'src/pages'))) {
  const raw = fs.readFileSync(file, 'utf8')
  // 页面自身 CSS 的颜色也参与判断
  const ownCss = (raw.match(/<style>([\s\S]*?)<\/style>/) || ['', ''])[1]
  const colors = Object.assign({}, BASE_COLORS, colorMap(ownCss))

  const tplStart = raw.indexOf('<template>')
  const tplEnd = raw.indexOf('</template>')
  if (tplStart < 0 || tplEnd < 0) continue
  const tpl = raw.slice(tplStart, tplEnd)

  let out = ''
  let i = 0
  const stack = []            // 祖先类名数组
  let localChanges = 0

  while (i < tpl.length) {
    const lt = tpl.indexOf('<', i)
    if (lt < 0) { out += tpl.slice(i); break }
    out += tpl.slice(i, lt)
    const gt = tpl.indexOf('>', lt)
    if (gt < 0) { out += tpl.slice(lt); break }
    const seg = tpl.slice(lt, gt + 1)
    const mName = seg.match(/^<\/?\s*([\w-]+)/)
    const name = mName ? mName[1] : ''
    const isClose = /^<\//.test(seg)

    if (isClose) {
      if (name !== 'text' && name !== 'image' && name !== 'input') stack.pop()
      out += seg
      i = gt + 1
      continue
    }

    if (name === 'text') {
      const cm = seg.match(/class="([^"]*)"/)
      const classes = cm ? cm[1].split(/\s+/).filter(Boolean) : []
      const statics = classes.filter(c => !c.includes('{'))
      const hasColor = statics.some(c => colors[c])

      if (!hasColor) {
        // 决定颜色
        const inBtn = stack.some(anc => anc.some(c => BTN_CLASSES.indexOf(c) >= 0))
        const inDialog = stack.some(anc => anc.indexOf('dialog') >= 0)
        let col = '#e8e8e8'
        if (inBtn) col = '#ffffff'
        else if (statics.indexOf('t-dlg-title') >= 0 || statics.indexOf('dialog-title') >= 0) col = '#2b1a0c'
        else if (statics.indexOf('t-dlg-body') >= 0 || statics.indexOf('dialog-body') >= 0) col = '#5c3a21'
        else if (inDialog) col = '#442813'

        const sm = seg.match(/style="([^"]*)"/)
        if (sm) {
          const st = parseStyle(sm[1])
          if (!st.color) {
            const merged = Object.assign({ color: col }, st)
            out += seg.replace(sm[0], 'style="' + styleStr(merged) + '"')
            localChanges++
          } else {
            out += seg
          }
        } else {
          out += seg.replace('<text', '<text style="color: ' + col + '"')
          localChanges++
        }
      } else {
        out += seg
      }
      i = gt + 1
      continue
    }

    // 记录祖先类名
    const cm2 = seg.match(/class="([^"]*)"/)
    const anc = cm2 ? cm2[1].split(/\s+/).filter(c => c && !c.includes('{')) : []
    stack.push(anc)
    out += seg
    i = gt + 1
  }

  if (localChanges > 0) {
    changedFiles++
    changedTags += localChanges
    if (!CHECK) {
      fs.writeFileSync(file, raw.slice(0, tplStart) + out + raw.slice(tplEnd))
    }
    console.log((CHECK ? '[需修] ' : '[已修] ') + path.relative(ROOT, file).replace(/\\/g, '/') + '  ' + localChanges + ' 处')
  }
}

console.log('\n' + (CHECK ? '待修复' : '已修复') + ' 文件 ' + changedFiles + ' 个，文字 ' + changedTags + ' 处')
