# -*- coding: utf-8 -*-
"""终端页键盘接线：追加而不是覆盖、去掉 192 补偿、清掉过期提示。"""
import io, sys

P = r'C:\Users\39830\Documents\zcode\shellpp\src\pages\term\term.ux'
with io.open(P, 'r', encoding='utf-8') as f:
    t = f.read()

def sub(s, old, new, n=1, tag=''):
    c = s.count(old)
    if c != n:
        print('!! [%s] 期望 %d 处，实际 %d 处：%r' % (tag, n, c, old[:80]))
        sys.exit(1)
    print('ok [%s] x%d' % (tag, n))
    return s.replace(old, new)

t = sub(t, '    <div class="kbwrap" style="padding-left: {{kbOff}}px">', '    <div class="kbwrap">',
        1, '去掉补左边距')
t = sub(t, '        dictionarypath="/components/InputMethod/assets/dictionary/"\n', '',
        1, '去掉词库路径')
t = sub(t, '    kbHide: true,\n    kbOff: 0,', '    kbHide: true,', 1, '去掉 kbOff 状态')
t = sub(t, '    // 键盘居中补偿：组件按 192 宽定位，屏更宽时补左边距\n'
           '    this.kbOff = Math.max(0, Math.round((app.w - 192) / 2))\n', '',
        1, '去掉 kbOff 计算')

# 每敲一个键组件发一次 complete（英文一个字符一次），必须追加
t = sub(t, '  onKbComplete(event) {',
        '  // 键盘每敲一下发一次 complete（英文模式下一次一个字符），所以这里是「追加」；\n'
        '  // 覆盖会让 cmd 永远只剩最后一个字符，等于打不进字。\n'
        '  onKbComplete(event) {', 1, '注释')
t = sub(t, '    this.cmd = String(t).slice(0, 60)',
        '    this.cmd = (this.cmd + String(t)).slice(0, 60)', 1, 'complete 改为追加')
t = sub(t, "    this.hint = '已填入：' + this.cmd + '\u3000点右上角「执行」'",
        "    this.hint = '已输入：' + this.cmd", 1, 'complete 提示')

t = sub(t, '''  onKbDelete() {
    this.cmd = this.cmd.slice(0, -1)
  },''', '''  // 组件自己的缓冲区空了才发 delete，所以退格由页面删自己的 cmd
  onKbDelete() {
    this.cmd = this.cmd.slice(0, -1)
    this.hint = this.cmd ? '已输入：' + this.cmd : '键盘只有英文；输完点右上角「执行」'
  },''', 1, 'delete 提示')

t = sub(t, "    hint: '先点键盘左下角的语言键切到 en（纯英文），再输命令；打完点右上角「执行」',",
        "    hint: '键盘只有英文；输完点右上角「执行」',", 1, '首屏提示')
t = sub(t, "    if (!this.kbHide) this.hint = '输完点右上角「执行」（键盘左下角可切 en/中文）'",
        "    if (!this.kbHide) this.hint = '键盘只有英文；输完点右上角「执行」'", 1, '弹出提示')

with io.open(P, 'w', encoding='utf-8', newline='') as f:
    f.write(t)
print('done')
