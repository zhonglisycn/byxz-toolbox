# -*- coding: utf-8 -*-
"""键盘瘦身：去掉候选相关的一切 + 装饰进度环，高度 305 -> 216。

删的东西（pill 分支内）：
  1. <progress type="arc"> 装饰环（188x188，占了大半个键盘高度，只是滚动指示）
  2. search.png 输入/候选条（英文键盘没有候选，是个空灰框）
  3. #cvalWaiting 候选横滚行
  4. down2.png 候选展开箭头
  5. 整个候选下展面板（if downFlag==='down'，263px 高）
同时把三段高度收敛：容器 305->216、内容层 top 34->46 / height 276->170、顶栏盒子 110->46。
字母三排（60px 圆键、0/32/64 阶梯）原样不动 —— 那是键盘本体。
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

# 1. 装饰进度环
s = sub(s, '''          <progress percent="{{30+percent66}}" type="arc" style="start-angle:204deg;total-angle:-48deg;width:188px;height:188px;top:82px;left:12px;position:absolute;color:#ffffff;stroke-width:6px;layer-color:#262626;margin-left: {{(screenWidth - 212)/2}}px;"></progress>\n''',
        '', 1, '删进度环')

# 2. 输入/候选条 + 3. 候选横滚行 + 4. 展开箭头
s = sub(s, '''          <img static style="position: absolute;left: 3px;top: 47px;width: 206px;height: 60px;" src="./assets/arc/search.png" />\n''',
        '', 1, '删输入条')
s = sub(s, '''          <!-- 候选横滚行：整词在前、单字随后（拼音已在键盘上方独立小字行显示，这里不放 cval） -->
          <scroll id="cvalWaiting" scroll-x="{{true}}" style="position: absolute;left: 15px;top: 56px;width: 144px;height: 42px;">
            <div style="position: absolute;left: 0px;top: 0px;height: 42px;padding-right:20px">
              <text for="{{resultRow0}}" show="{{resultRow0.length > $idx}}" class="calbtn02" style="padding-right:10px" @click="onRsSelect(resultRow0[$idx])">{{resultRow0[$idx]}}</text>
            </div>
          </scroll>
''', '', 1, '删候选横滚行')
s = sub(s, '''          <img show="{{resultRow0.length > 0}}" style="position: absolute;left: 140px;top: 57px;width: 60px;height: 40px;" src="./assets/arc/down2.png" @click="onBtnClick('down')" />\n''',
        '', 1, '删展开箭头')

# 5. 候选下展面板（整块）
s = sub(s, '''        <!-- 这里使用show会导致每次输入都会加载全部候选列表，很卡 -->
        <div style="position: absolute;top: 47px;width: 100%;height: 263px;background-color: black;" if="{{downFlag==='down'}}">
          <div style="position: absolute;left: {{(screenWidth - 212)/2}}px;width: 212px;height: 263px;"> 
            <scroll scroll-y="{{true}}" class="list66 expanded-scroll">
              <div class="expanded-candidates expanded-candidates66">
                <text class="calbtn-down-text" for="{{item in resultList2}}" @click="onRsSelect(item)">{{item}}</text>
              </div>
            </scroll>
            <img static style="position: absolute;top:196px;left:66px;width: 80px;height: 60px;" src="./assets/arc/up2.png" @click="onBtnClick('down')" />
          </div>
        </div>
''', '', 1, '删候选下展面板')

# 6. 高度收敛
s = sub(s, '''<div if="{{screentype==='pill-shaped'}}" style="width: 100%;height: 305px">
        <div static style="position:absolute;left:0px;top:34px;width:100%;height:276px;">''',
        '''<div if="{{screentype==='pill-shaped'}}" style="width: 100%;height: 216px">
        <div static style="position:absolute;left:0px;top:46px;width:100%;height:170px;">''',
        1, '容器 305->216 / 内容 top46 height170')
s = sub(s, 'top: 0px;width: 212px;height: 110px;', 'top: 0px;width: 212px;height: 46px;',
        1, '顶栏盒子 110->46')
# 环和候选面板删掉后，滚动事件只为进度环服务了，去掉绑定（handelScroll 留着手动调用也不影响）
s = sub(s, '''<scroll id="keyboard66" scroll-x="{{true}}" onscroll="handelScroll"''',
        '''<scroll id="keyboard66" scroll-x="{{true}}"''', 1, '去掉 onscroll 绑定')

with io.open(P, 'w', encoding='utf-8', newline='') as f:
    f.write(s)
print('done')
