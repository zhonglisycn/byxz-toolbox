/**
 * 键盘 pill 分支几何自检
 *
 * 背景：pill-shaped 分支是绝对定位拼出来的，改宽度基准（192 -> 212）时人手算 x 很容易
 * 算错或让两个键压在一起（123 键与大小写键在英文模式下同时显示，原来靠语言键互斥）。
 * 这里直接把 InputMethod.ux 里 pill 分支的绝对定位元素解析出来做算术检查。
 *
 * 用法：node tools/check-kb-layout.mjs
 */
import fs from 'node:fs'
import path from 'node:path'

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..')
const UX = path.join(ROOT, 'src/components/InputMethod/InputMethod.ux')
const src = fs.readFileSync(UX, 'utf8')

const W = 212      // pill 键盘盒子宽度
const H = 305      // 键盘总高
const TOPBAR_H = 110

// 取出 pill-shaped 分支
const start = src.indexOf("screentype==='pill-shaped'")
if (start < 0) { console.error('找不到 pill-shaped 分支'); process.exit(1) }
const rest = src.slice(start)
const end = rest.indexOf('\n      <div if="{{screentype===', 10)
const branch = end > 0 ? rest.slice(0, end) : rest

let fails = 0
function check(ok, msg) {
  console.log((ok ? '  ✓ ' : '  ✗ ') + msg)
  if (!ok) fails++
}

/* ---------- 1. 全部绝对定位元素必须在盒子里 ---------- */
const rects = []
// 逐个 <img ... /> 取出来再看 style：show="{{x.length > 0}}" 里带 '>'，不能用 [^>]* 截断
const imgRe = /<img\b[\s\S]*?\/>/g
let m
while ((m = imgRe.exec(branch))) {
  const tagTxt = m[0]
  const st = (tagTxt.match(/style="([^"]*)"/) || [])[1]
  if (!st) continue
  const g = (k) => {
    const mm = st.match(new RegExp(k + ':\\s*([-\\d.]+)px'))
    return mm ? parseFloat(mm[1]) : null
  }
  const left = g('left'), width = g('width')
  const top = g('top')
  if (left === null || width === null) continue
  const tag = (tagTxt.match(/([a-z0-9_]+\.png)/i) || ['?'])[1]
  rects.push({ tag, left, width, top: top === null ? 0 : top, raw: tagTxt })
}

console.log('pill 分支里带 left/width 的图片元素：' + rects.length)
check(rects.length >= 4, '解析到至少 4 个定位图片（实际 ' + rects.length + '）')

for (const r of rects) {
  check(r.left >= 0 && r.left + r.width <= W,
    r.tag + ' 在盒内：left ' + r.left + ' + ' + r.width + ' ≤ ' + W)
}

/* ---------- 2. 英文模式下同时可见的顶栏键不能重叠 ---------- */
// 顶栏（top:0，高 42）里英文模式会同时出现的：123、大小写、删除
// 注意 a.png / bigA.png 是同一个位置的两个互斥图标（upperFlag 切换），只取默认态那个
const topbar = rects.filter((r) => r.top < 5 && r.tag !== 'search.png')
const EN_VISIBLE = ['123.png', 'a.png', 'del.png']
const shown = topbar.filter((r) => EN_VISIBLE.indexOf(r.tag) >= 0)
console.log('英文模式顶栏同时可见：' + shown.map((r) => r.tag + '@' + r.left).join(', '))

const shift = topbar.filter((r) => r.tag === 'a.png' || r.tag === 'bigA.png')
check(shift.length === 2 && shift[0].left === shift[1].left && shift[0].width === shift[1].width,
  'a.png / bigA.png 同位置互斥（原地切换大小写图标）')

for (let i = 0; i < shown.length; i++) {
  for (let j = i + 1; j < shown.length; j++) {
    const a = shown[i], b = shown[j]
    const overlap = a.left < b.left + b.width && b.left < a.left + a.width
    check(!overlap, a.tag + '(' + a.left + '-' + (a.left + a.width) + ') 不与 ' +
      b.tag + '(' + b.left + '-' + (b.left + b.width) + ') 重叠')
  }
}

/* ---------- 3. 关键尺寸与文案核实 ---------- */
check(branch.indexOf('height: 305px') > 0, '键盘总高 305（作者原值，不许再动）')
check(branch.indexOf('height: 110px') > 0, '顶栏盒子 110（作者原值）')
check(branch.indexOf('top:34px') > 0 && branch.indexOf('height:276px') > 0, '内容层 top34/276（作者原值：三排键下沿落在盒内 y=204）')
// 真机踩过：键没有 flex-shrink:0，10 个 60px 的键被压成 ~21px，字叠在一起、只看得见行尾
check(/\.calbtn66\s*\{[^}]*flex-shrink:\s*0/.test(src), '.calbtn66 有 flex-shrink:0（不许被压扁）')
check((src.match(/height: 60px;flex-shrink: 0;/g) || []).length >= 9, '三排容器都锁了 flex-shrink:0')
check(src.indexOf('width: 60px;height: 60px;flex-shrink: 0;') > 0, '空格键锁了 flex-shrink:0')
// 内容层必须显式 630px：否则它等于视口 212，键被压扁、横滚也没得滑（真机就是这样只看得见行尾）
check((branch.match(/width: 630px/g) || []).length === 3, '三个内容层都写了 width: 630px（可横滚）')
check(branch.indexOf('screenWidth - 192') < 0, '不再使用 192 基准')
check((src.match(/screenWidth - 212/g) || []).length === 4, '212 基准共 4 处')
// 候选相关的东西删掉后不许回来（英文键盘没有候选，它们只是白占遮挡面积）
check(branch.indexOf('search.png') < 0, '没有候选/输入条 search.png')
check(branch.indexOf('cvalWaiting') < 0, '没有候选横滚行')
check(branch.indexOf('down2.png') < 0, '没有候选展开箭头')
check(branch.indexOf('<progress') > 0, '进度环保留（用户指定要留）')
check(branch.indexOf('top:82px;left:12px') > 0, '进度环 top82（作者原值）')
check(branch.indexOf('onscroll="handelScroll"') > 0, '环跟着键盘横滚（onscroll 绑着）')
check(branch.indexOf('263px') < 0, '没有 263px 的候选下展面板')

const dataLang = src.match(/lang:\s*"(\w+)",/)
check(!!dataLang && dataLang[1] === 'en', '默认语言是 en（实际 ' + (dataLang && dataLang[1]) + '）')
check(src.indexOf('lang.png') < 0 || src.indexOf('assets/arc/{{lang}}.png') < 0, '语言切换键已移除')

// 纵向版面 = 作者原值（305 / top34 / 276 / 环 top82 / 顶栏 110）。
// 教训：这套数字是作者按胶囊屏几何调好的，我按"省遮挡"自己改纵向尺寸，
// 连改三版都出事（键压扁、行坐进弧区、黑底不铺到屏幕底）。现在只准横向做修复（键不被压扁、
// 内容层 630px 可横滚），纵向一律不许动。
check(branch.indexOf('padding-bottom') < 0, '没有我自加的黑底补高（回作者原值）')

const term = fs.readFileSync(path.join(ROOT, 'src/pages/term/term.ux'), 'utf8')
check(term.indexOf('this.cmd + String(t)') > 0, '终端页对键盘输入做追加（不是覆盖）')
check(term.indexOf('kbOff') < 0, '终端页没有遗留的居中补偿')
check(term.indexOf('kbHide') < 0, '终端页没有遗留的 kbHide')
check(term.indexOf('dictionarypath') < 0, '终端页不再加载词库')
// 按需挂载：不用 hide 切换（作者的 watcher 在部分设备不生效），且 hide 必须是字面量 false 而不是字符串
check(/<input-method\s+if="\{\{kbOn\}\}"/.test(term), '组件用 if="{{kbOn}}" 按需挂载')
check(term.indexOf('hide="{{false}}"') > 0, 'hide 传的是字面量 {{false}}')
check(term.indexOf('hide="false"') < 0, '没用字符串 "false"（truthy，会被当隐藏）')

console.log(fails === 0 ? '\n✓ 键盘几何自检通过' : '\n✗ 键盘几何自检失败 ' + fails + ' 项')
process.exit(fails === 0 ? 0 : 1)
