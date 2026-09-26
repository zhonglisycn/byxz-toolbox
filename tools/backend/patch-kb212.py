# -*- coding: utf-8 -*-
"""把 InputMethod 键盘改成 212 基准（对齐 com.zyz4.notebook 2.0.0 里的同一组件），
并只留英文键盘；修好终端页「每个字母覆盖 cmd」的接线错误。"""
import io, sys

def load(p):
    with io.open(p, 'r', encoding='utf-8') as f:
        return f.read()

def save(p, s):
    with io.open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(s)

def sub(s, old, new, n=1, tag=''):
    c = s.count(old)
    if c != n:
        print('!! [%s] 期望 %d 处，实际 %d 处：%r' % (tag, n, c, old[:70]))
        sys.exit(1)
    print('ok [%s] x%d' % (tag, n))
    return s.replace(old, new)

UX = r'C:\Users\39830\Documents\zcode\shellpp\src\components\InputMethod\InputMethod.ux'
TERM = r'C:\Users\39830\Documents\zcode\shellpp\src\pages\term\term.ux'

s = load(UX)

# ---- A. pill-shaped 分支：192 基准 -> 212 基准（notebook 版同款数字）----
s = sub(s, 'top:82px;left:2px;position:absolute;', 'top:82px;left:12px;position:absolute;',
        1, '进度环 left 2->12')
s = sub(s, '(screenWidth - 192)/2', '(screenWidth - 212)/2', 5, '居中基准 192->212')
s = sub(s, 'top: 0px;width: 192px;height: 110px;', 'top: 0px;width: 212px;height: 110px;',
        1, '顶栏盒子 192->212')
s = sub(s, 'width: 192px;height: 263px;', 'width: 212px;height: 263px;',
        1, '下展盒子 192->212')
# 输入显示条：3 + 206 + 3 = 212
s = sub(s, 'top: 47px;width: 186px;height: 60px;" src="./assets/arc/search.png"',
        'top: 47px;width: 206px;height: 60px;" src="./assets/arc/search.png"',
        1, '输入条 186->206')
# 右贴边键：向左让出 20px（212-48-9 / 212-60-12）
s = sub(s, 'left: 120px;top: 57px;width: 60px;height: 40px;" src="./assets/arc/down2.png"',
        'left: 140px;top: 57px;width: 60px;height: 40px;" src="./assets/arc/down2.png"',
        1, 'down2 120->140')
s = sub(s, 'left: 135px;top: 0px;width: 48px;height: 42px;',
        'left: 155px;top: 0px;width: 48px;height: 42px;',
        1, 'del 135->155')
# 居中键：+10
s = sub(s, 'left: 70px;top: 0px;width: 52px;height: 42px;',
        'left: 80px;top: 0px;width: 52px;height: 42px;',
        2, '123 键 70->80')
s = sub(s, 'top:0px;left:72px;width:48px;height:42px;', 'top:0px;left:82px;width:48px;height:42px;',
        2, '大小写键 72->82')
s = sub(s, 'top:196px;left:56px;width: 80px;height: 60px;" src="./assets/arc/up2.png"',
        'top:196px;left:66px;width: 80px;height: 60px;" src="./assets/arc/up2.png"',
        1, '下展收起键 56->66')

# ---- B. 只留英文键盘 ----
lang_img = ('          <img src="./assets/arc/{{lang}}.png" style="position: absolute;'
            "top:0px;left:9px;width: 48px;height: 42px;\" @click=\"onBtnClick('lang')\" "
            "show=\"{{downFlag==='' && !numFlag && !numFlag_jp}}\" />\n")
s = sub(s, lang_img, '          <!-- 本应用只用英文键盘：中/日词库已删，语言键去掉，该位置留给返回键 -->\n',
        1, '移除语言键')
s = sub(s, "show=\"{{numFlag && lang==='cn' ||numFlag_jp && lang==='jp' }}\"",
        'show="{{numFlag}}"', 1, '返回键条件')
# 数字/符号键：英文模式下也要能切（原来只在 cn 下显示）
s = sub(s, "src=\"./assets/arc/123.png\" style=\"position: absolute;left: 80px;top: 0px;"
           "width: 52px;height: 42px;\" @click=\"onBtnClick('switchNum')\" "
           "show=\"{{downFlag==='' && !numFlag && lang==='cn'}}\" />",
        "src=\"./assets/arc/123.png\" style=\"position: absolute;left: 80px;top: 0px;"
        "width: 52px;height: 42px;\" @click=\"onBtnClick('switchNum')\" "
        "show=\"{{downFlag==='' && !numFlag}}\" />", 1, '123 键对英文可见')
jp123 = ("          <img src=\"./assets/arc/123.png\" style=\"position: absolute;left: 80px;"
         "top: 0px;width: 52px;height: 42px;\" @click=\"onBtnClick('switchNum_jp')\" "
         "show=\"{{downFlag==='' && !numFlag_jp && lang==='jp'}}\" />\n")
s = sub(s, jp123, '', 1, '移除日文 123 键')
s = sub(s, '    lang: "cn",', '    lang: "en",', 1, '默认语言 en')
s = sub(s, '    screenWidth: 336,', '    screenWidth: 212,', 1, '默认屏宽 212')

old_lang_case = '''      case "lang":
        if (this.keyboardtype === "T9") {
          this.lang = this.lang === "cn" ? "en" : "cn";
        } else {
          if (this.lang === "cn") {
            this.lang = "en";
          } else if (this.lang === "en") {
            this.lang = "jp";
          } else {
            this.lang = "cn";
          }
        }
        this.cval = "";'''
new_lang_case = '''      case "lang":
        // 只用英文键盘（中/日词库与语言键都已删），这里固定 en，保留分支便于复用组件
        this.lang = "en";
        this.cval = "";'''
s = sub(s, old_lang_case, new_lang_case, 1, '语言键锁 en')

save(UX, s)

# ---- C. 终端页接线 ----
t = load(TERM)
t = sub(t, '''        dictionarypath="/components/InputMethod/assets/dictionary/"\n''', '',
        1, '去掉词库路径')
t = sub(t, '    <div class="kbwrap" style="padding-left: {{kbOff}}px">', '    <div class="kbwrap">',
        1, '去掉补左边距')
t = sub(t, '    padTop: 0, padBottom: 0, padSide: 0, fsTitle: 17, fsNav: 16,\n    kbHide: true,\n    kbOff: 0,',
        '    padTop: 0, padBottom: 0, padSide: 0, fsTitle: 17, fsNav: 16,\n    kbHide: true,',
        1, '去掉 kbOff 状态')
t = sub(t, '    this.kbOff = Math.max(0, Math.round((app.w - 192) / 2))\n', '', 1, '去掉 kbOff 计算')

old_complete = '''  onKbComplete(event) {
    const t = event && event.detail && event.detail.content ? event.detail.content : ''
    if (!t) return
    this.cmd = String(t).slice(0, 60)
    this.hint = '已填入：' + this.cmd + '　点右上角「执行」'
  },

  onKbDelete() {
    this.cmd = this.cmd.slice(0, -1)
    this.kbHide = !this.kbHide
    if (!this.kbHide) this.hint = '输完点右上角「执行」（键盘左下角可切 en/中文）'
  },'''
new_complete = '''  // 键盘每敲一下发一次 complete（英文模式一次一个字符，数字/符号键也走这里），
  // 所以这里是「追加」而不是覆盖 —— 覆盖会让 cmd 永远只剩最后一个字符。
  onKbComplete(event) {
    const t = event && event.detail && event.detail.content ? String(event.detail.content) : ''
    if (!t) return
    this.cmd = (this.cmd + t).slice(0, 60)
    this.hint = '已输入：' + this.cmd
  },

  // 组件自身缓冲区空了才会发 delete，所以退格由页面删自己的 cmd
  onKbDelete() {
    this.cmd = this.cmd.slice(0, -1)
    this.hint = this.cmd ? '已输入：' + this.cmd : '键盘只有英文；输完点右上角「执行」'
  },'''
t = sub(t, old_complete, new_complete, 1, '修正 complete/delete 接线')

t = sub(t, "    hint: '先点键盘左下角的语言键切到 en（纯英文），再输命令；打完点右上角「执行」',",
        "    hint: '键盘只有英文；输完点右上角「执行」',", 1, '首屏提示')
save(TERM, t)
print('done')
