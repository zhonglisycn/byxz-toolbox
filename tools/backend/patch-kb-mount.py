# -*- coding: utf-8 -*-
"""键盘按需挂载 + 宿主/组件样式串味防护，并在终端页加一行现场读数。

为什么改成按需挂载：上游组件源码里作者自己写着 "hide watchers (unreliable on some devices)"，
README 的属性表也说 hide 是「切换属性值隐藏或唤醒键盘」。真机上"呼不出"最可能就是
hide 属性变更这条路在这台设备上不生效。notebook / 作者示例都是把组件挂在一个状态变量下按需创建，
所以这里改成 if 挂载 + hide 传字面量 false（注意必须写 {{false}}，写 "false" 字符串是 truthy）。
"""
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
        print('!! [%s] 期望 %d 处，实际 %d 处：%r' % (tag, n, c, old[:80]))
        sys.exit(1)
    print('ok [%s] x%d' % (tag, n))
    return s.replace(old, new)

UX = r'C:\Users\39830\Documents\zcode\shellpp\src\components\InputMethod\InputMethod.ux'
TERM = r'C:\Users\39830\Documents\zcode\shellpp\src\pages\term\term.ux'

# ---- 组件根节点补 inline padding：宿主若也有 .page 类，base.css 的 padding 会串味到键盘 ----
s = load(UX)
s = sub(s, '<div class="page" style="flex-direction: column; height: {{hide ? \'0px\' : \'auto\'}}; overflow: {{hide ? \'hidden\' : \'visible\'}};">',
        '<div class="page" style="flex-direction: column; padding: 0px; height: {{hide ? \'0px\' : \'auto\'}}; overflow: {{hide ? \'hidden\' : \'visible\'}};">',
        1, '组件根 padding 归零')
save(UX, s)

# ---- 终端页：按需挂载 ----
t = load(TERM)
old_block = '''    <!-- 键盘组件（NEORUAA/Vela_input_method，MIT）：pill 分支已改成 212 基准，与手环 10
         屏宽一致，左右不再各空一条；组件自身绝对定位贴屏幕底部，这层只负责占位。 -->
    <div class="kbwrap">
      <input-method
        hide="{{kbHide}}"
        keyboardtype="QWERTY"
        maxlength="60"
        vibratemode="short"
        screentype="pill-shaped"
        @delete="onKbDelete"
        @complete="onKbComplete"
      ></input-method>
    </div>'''
new_block = '''    <!-- 键盘（NEORUAA/Vela_input_method，MIT）：pill 分支已改成 212 基准，与手环 10 屏宽一致。
         按需挂载而不是切 hide：组件作者在源码里标注 hide watcher 在部分设备不可靠，
         所以只在需要时把组件建出来，并直接传 hide={{false}} 让它一建出来就是展开的。
         注意 hide 必须写 {{false}}，字符串 "false" 是 truthy，会被当成隐藏。 -->
    <input-method if="{{kbOn}}"
      hide="{{false}}"
      keyboardtype="QWERTY"
      maxlength="60"
      vibratemode="short"
      screentype="pill-shaped"
      @visibility-change="onKbVisible"
      @key-down="onKbKey"
      @delete="onKbDelete"
      @complete="onKbComplete"
    ></input-method>'''
t = sub(t, old_block, new_block, 1, '按需挂载键盘')

t = sub(t, "    kbHide: true,\n    cmd: '',",
        "    kbOn: false,\n    keyCount: 0,\n    visCount: 0,\n    cmd: '',", 1, '新增键盘状态')

old_bar = '''      <div class="inputbar {{kbHide ? '' : 'inputbar-on'}}" @click="toggleKb">
        <text class="ib-text" style="font-size: 15px">{{cmd ? cmd : '点这里输命令'}}</text>
        <text class="ib-hint" style="font-size: 11px">{{kbHide ? '输入' : '收起'}}</text>
      </div>
      <text class="sec" style="font-size: 12px">{{hint}}</text>'''
new_bar = '''      <div class="inputbar {{kbOn ? 'inputbar-on' : ''}}" @click="toggleKb">
        <text class="ib-text" style="font-size: 15px">{{cmd ? cmd : '点这里输命令'}}</text>
        <text class="ib-hint" style="font-size: 11px">{{kbOn ? '收起' : '输入'}}</text>
      </div>
      <text class="sec" style="font-size: 12px">{{hint}}</text>
      <!-- 现场读数：键盘不弹时靠它区分「点没生效」「组件没渲染」「按键事件没回来」 -->
      <text class="sec" style="font-size: 12px">{{kbOn ? '键盘已挂载' : '键盘未挂载'}} · 按键 {{keyCount}} · 可见事件 {{visCount}}</text>'''
t = sub(t, old_bar, new_bar, 1, '读数行')

t = sub(t, '''  toggleKb() {
    this.$app.$def.tap()
    this.kbHide = !this.kbHide''',
        '''  toggleKb() {
    this.$app.$def.tap()
    this.kbOn = !this.kbOn''', 1, 'toggleKb 改挂载开关')

t = sub(t, '''  // 组件自己的缓冲区空了才发 delete，所以退格由页面删自己的 cmd
  onKbDelete() {''',
        '''  // 组件的键盘按下/显隐事件（README 里事件名是 kebab-case，模板里写 visibility-change）
  onKbKey() { this.keyCount = this.keyCount + 1 },

  onKbVisible(evt) {
    this.visCount = this.visCount + 1
    const v = evt && evt.detail ? evt.detail.visible : null
    this.hint = v === null ? this.hint : (v ? '键盘已展开' : '键盘已收起')
  },

  // 组件自己的缓冲区空了才发 delete，所以退格由页面删自己的 cmd
  onKbDelete() {''', 1, '键盘事件计数')

save(TERM, t)
print('done')
