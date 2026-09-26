# -*- coding: utf-8 -*-
"""把装饰进度环放回来（用户选了「进度环」：别去掉），但按瘦身版面重新对齐。

原来：容器 305px，环 top 82（在 34px 偏移的内容层里），环底 ≈ 304 —— 环下方一大截是空的。
现在：容器 234px = 顶栏 46 + 环区 188，环直接挂在分支下、top 46，环底与键盘底齐平；
     字母三排仍从 46 开始，压在环身上（环是背景，白弧在环底＝键盘最下沿）。
     候选相关的（search.png / cvalWaiting / down2 / 下展面板）保持删除。
另：环是要跟着键盘横滚走的，之前为了关掉环我把 onscroll 解绑了，现在绑回来。
"""
import io, sys

P = r'C:\Users\39830\Documents\zcode\shellpp\src\components\InputMethod\InputMethod.ux'
with io.open(P, 'r', encoding='utf-8') as f:
    s = f.read()

def sub(s, old, new, n=1, tag=''):
    c = s.count(old)
    if c != n:
        print('!! [%s] 期望 %d 处，实际 %d 处：%r' % (tag, n, c, old[:90]))
        sys.exit(1)
    print('ok [%s] x%d' % (tag, n))
    return s.replace(old, new)

# 容器 216 -> 234（顶栏 46 + 环区 188）
s = sub(s, """<div if="{{screentype==='pill-shaped'}}" style="width: 100%;height: 216px">
        <div static style="position:absolute;left:0px;top:46px;width:100%;height:170px;">""",
        """<div if="{{screentype==='pill-shaped'}}" style="width: 100%;height: 234px">
        <div static style="position:absolute;left:0px;top:46px;width:100%;height:170px;">""",
        1, '容器 216->234')

# 环放回来：直接挂在分支下，top 46，环底 = 键盘底
s = sub(s, """        <div static style="position:absolute;left:0px;top:46px;width:100%;height:170px;">
          <scroll id="keyboard66" scroll-x="{{true}}" style=""",
        """        <progress percent="{{30+percent66}}" type="arc" style="start-angle:204deg;total-angle:-48deg;width:188px;height:188px;top:46px;left:12px;position:absolute;color:#ffffff;stroke-width:6px;layer-color:#262626;margin-left: {{(screenWidth - 212)/2}}px;"></progress>
        <div static style="position:absolute;left:0px;top:46px;width:100%;height:170px;">
          <scroll id="keyboard66" scroll-x="{{true}}" style=""",
        1, '环放回（top 46，底对齐）')

# 环要跟着横滚走
s = sub(s, """<scroll id="keyboard66" scroll-x="{{true}}" style="padding-left:""",
        """<scroll id="keyboard66" scroll-x="{{true}}" onscroll="handelScroll" style="padding-left:""",
        1, '绑回 onscroll')

with io.open(P, 'w', encoding='utf-8', newline='') as f:
    f.write(s)
print('done')
