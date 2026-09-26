# -*- coding: utf-8 -*-
"""按 InputMethod.ux 里 pill 分支的真实坐标，把键盘渲染成 212x520 的图，用来和上游样机比对。

坐标全部从源码解析（不自造），素材用组件里真实的 png。渲染是近似的（字体、抗锯齿与设备不同），
目的是回答"三排键到底看不看得全、环在哪、顶栏三个键的位置对不对"这类版面问题。
用法：python tools/render-kb.py
产物：docs/渲染_我们的键盘.png、（配 side-by-side 到 docs/对比_目标与本机.png）
"""
import io, re, os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UX = os.path.join(ROOT, 'src', 'components', 'InputMethod', 'InputMethod.ux')
ASSETS = os.path.join(ROOT, 'src', 'components', 'InputMethod', 'assets', 'arc')
DOCS = os.path.join(ROOT, 'docs')

src = io.open(UX, encoding='utf-8').read()
branch = src[src.index("screentype==='pill-shaped'"):]

def need(pattern, tag):
    m = re.search(pattern, branch)
    if not m:
        raise SystemExit('解析失败：' + tag)
    return m.groups()

(box_h,) = need(r"pill-shaped'\}\}\" style=\"width: 100%;height: (\d+)px\"", '分支高度')
(c_top, c_h) = need(r"position:absolute;left:0px;top:(\d+)px;width:100%;height:(\d+)px;", '内容层')
(r_top, r_left) = need(r"width:188px;height:188px;top:(-?\d+)px;left:(\d+)px;position:absolute;", '进度环')
(bar_h,) = need(r"top: 0px;width: 212px;height: (\d+)px;", '顶栏盒')
box_h, c_top, c_h, r_top, r_left, bar_h = (int(box_h), int(c_top), int(c_h), int(r_top), int(r_left), int(bar_h))

# 顶栏三个键（英文模式可见的：123 / 大小写(a,bigA) / 退格）
top_imgs = []
for m in re.finditer(r'<img src="\./assets/arc/([a-zA-Z0-9_]+\.png)" style="position: absolute;([^"]*)"', branch):
    name, st = m.group(1), m.group(2)
    g = lambda k: float(re.search(k + r':\s*([-\d.]+)px', st).group(1)) if re.search(k + r':\s*([-\d.]+)px', st) else 0.0
    left, top, w, h = g('left'), g('top'), g('width'), g('height')
    if name in ('123.png', 'a.png', 'bigA.png', 'del.png', 'back2.png'):
        top_imgs.append((name, left, top, w, h))

# 三排字母键：缩进 + keys.full
indents = [float(x) for x in re.findall(r'margin-left: (\d+)px;margin-top: -?\d+px;height: 60px;', branch)[:3]]
rows = re.search(r"full: \[\s*\[([^\]]+)\],\s*\[([^\]]+)\],\s*\[([^\]]+)\],", src)
letters = [[c.strip().strip('"') for c in g.split(',')] for g in rows.groups()]
KEY, GAP = 60, 3
ROWSTEP = 55            # margin-top: -5px -> 每排推进 55
BADGE = 3               # 键与键之间是 margin-right:3px

W, H = 212, 520
img = Image.new('RGB', (W, H), (0, 0, 0))
d = ImageDraw.Draw(img, 'RGBA')

def font(sz):
    for p in (r'C:\Windows\Fonts\arialbd.ttf', r'C:\Windows\Fonts\arial.ttf'):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()

f32 = font(30)

# 键盘盒子（贴屏幕底）
box_top = H - box_h
# 进度环（作者原值：环是背景，白弧在环底）
cx, cy = r_left + 94, box_top + c_top + r_top + 94
d.ellipse([cx - 94, cy - 94, cx + 94, cy + 94], outline=(0, 0, 0), width=6)  # 轨道纯黑=不可见
d.arc([cx - 94, cy - 94, cx + 94, cy + 94], start=90 - 24, end=90 + 24, fill=(255, 255, 255), width=6)

# 三排字母键
def circle(x, y, txt):
    d.ellipse([x, y, x + KEY, y + KEY], fill=(38, 38, 38), outline=(60, 60, 60), width=2)
    bb = d.textbbox((0, 0), txt, font=f32)
    d.text((x + KEY / 2 - (bb[2] - bb[0]) / 2 - bb[0], y + KEY / 2 - (bb[3] - bb[1]) / 2 - bb[1]),
           txt, font=f32, fill=(255, 255, 255))

for ri, row in enumerate(letters):
    x0 = 3 + indents[ri]
    y0 = box_top + c_top + ri * ROWSTEP
    for ki, ch in enumerate(row):
        x = x0 + ki * (KEY + BADGE)
        if x > W:
            break
        circle(x, y0, ch)
    # 第三排的尾巴上还挂着空格键
    if ri == 2:
        x = x0 + len(row) * (KEY + BADGE)
        if x <= W:
            d.ellipse([x, y0, x + KEY, y0 + KEY], fill=(38, 38, 38), outline=(60, 60, 60), width=2)

# 顶栏三个键（叠在最上层，和真机 z 序一致）
for name, left, top, w, h in top_imgs:
    if name == 'back2.png':
        continue                      # 只有数字页才显示
    art = Image.open(os.path.join(ASSETS, name)).convert('RGBA').resize((int(w), int(h)), Image.LANCZOS)
    img.paste(art, (int(left), int(box_top + top)), art)

# 胶囊屏边框 + 底半圆参考线
d.arc([-106, -106, W + 106, 106], start=0, end=180, fill=(70, 70, 70), width=2)
d.arc([-106, H - 106, W + 106, H + 106], start=180, end=360, fill=(70, 70, 70), width=2)

out = os.path.join(DOCS, '渲染_我们的键盘.png')
img.save(out)
print('已渲染', out, img.size)
print('分支高 %d / 内容层 top %d 高 %d / 环 top %d left %d / 顶栏盒高 %d'
      % (box_h, c_top, c_h, r_top, r_left, bar_h))
print('键盘盒 y %d..%d；三排键 y %s' % (
    box_top, H,
    ', '.join(str(int(box_top + c_top + i * ROWSTEP)) for i in range(3))))
print('顶栏键：', [(n, int(l), int(t), int(w), int(h)) for n, l, t, w, h in top_imgs])
