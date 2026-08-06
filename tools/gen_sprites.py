#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
翠鸟(翡)桌面宠物 sprite 生成器
扁平卡通风,侧视朝左,4x 超采样后缩到 256x256 抗锯齿,透明背景。
输出到 ../Resources/Sprites/*.png 以及 sprites.json、../Resources/peep.wav。
"""
import math, os, json, wave, struct
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Sprites")
SS = 4            # 超采样倍数
SIZE = 256        # 输出尺寸

# ---- 配色 ----
TEAL   = (22, 166, 179, 255)
TEAL_D = (15, 120, 132, 255)
ORANGE = (240, 145, 59, 255)
ORANGE_D = (214, 110, 36, 255)
WHITE  = (253, 246, 230, 255)
BEAK   = (26, 26, 26, 255)
EYE    = (24, 28, 32, 255)
LEG    = (224, 96, 48, 255)
BLUSH  = (244, 122, 142, 180)
HEART  = (235, 84, 110, 255)
ZCOLOR = (150, 196, 206, 255)
SHADOW = (0, 0, 0, 55)

# 系统字体(用于 zzz 等文字),带缓存
_FONT_PATHS = ["/System/Library/Fonts/Helvetica.ttc",
               "/System/Library/Fonts/Supplemental/Arial.ttf"]
_FONT_CACHE = {}

def font(size):
    if size in _FONT_CACHE:
        return _FONT_CACHE[size]
    f = None
    for p in _FONT_PATHS:
        try:
            f = ImageFont.truetype(p, size)
            break
        except Exception:
            pass
    if f is None:
        f = ImageFont.load_default()
    _FONT_CACHE[size] = f
    return f
FISH_BODY = (202, 214, 222, 255)
FISH_DARK = (150, 168, 180, 255)
EGG_SHELL = (252, 244, 224, 255)
EGG_SPCK  = (196, 158, 96, 255)


def heart(d, cx, cy, r, color):
    poly = []
    for deg in range(0, 360, 8):
        t = math.radians(deg)
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t))
        poly.append((cx + x * r / 16.0, cy + y * r / 16.0))
    d.polygon(poly, fill=color)


def draw_kingfisher(W, H, *, wing="folded", leg_phase=0.0, eye_closed=False,
                    body_dy=0, blush=False, heart_eye=False, zzz=False,
                    head_up=False, mouth_open=False, alert=False,
                    head_tilt=0.0, hide_legs=False, fish_in_beak=False,
                    look_down=False, x_eye=False, tongue=False,
                    fluff=False, tail_wag=0.0, butt_up=False, sweat=False,
                    fish_bite=0.0, head_raise_amt=0.0, head_jab=0.0):
    """画一只翠鸟,返回 RGBA Image。wing: folded / midup / up / middown / spread"""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = W / 256.0

    def E(cx, cy, rx, ry, fill):
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill)

    cx, cy = W * 0.54, H * 0.58 + body_dy * s

    # (脚下阴影由 ShadowController 运行时按太阳角度绘制,这里不再写死)

    # ---- 身体(橙腹)----
    body_rx = 62*s + (8*s if fluff else 0)
    body_ry = 52*s + (8*s if fluff else 0)
    E(cx, cy + 6*s, body_rx, body_ry, ORANGE)
    E(cx - 10*s, cy + 16*s, 30*s, 26*s, (255, 196, 120, 255))

    # ---- 背/披风(青)----
    d.pieslice([cx-72*s, cy-44*s, cx+74*s, cy+34*s], 180, 360, fill=TEAL)
    d.pieslice([cx-10*s, cy-44*s, cx+74*s, cy+10*s], 180, 360, fill=TEAL_D)

    # ---- 尾巴(青,右后;butt_up 翘起 + tail_wag 左右摆)----
    ty = (-14*s) if butt_up else 0
    tw = tail_wag * s
    tail = [(cx+58*s+tw, cy-2*s+ty), (cx+96*s+tw, cy-22*s+ty),
            (cx+98*s+tw, cy-4*s+ty), (cx+64*s+tw, cy+14*s+ty)]
    d.polygon(tail, fill=TEAL)
    d.polygon([(cx+74*s+tw, cy-6*s+ty), (cx+92*s+tw, cy-18*s+ty),
               (cx+84*s+tw, cy-4*s+ty)], fill=TEAL_D)

    # ---- 翅膀 ----
    wcx, wcy = cx + 4*s, cy + 2*s
    if wing == "folded":
        d.ellipse([wcx-40*s, wcy-22*s, wcx+40*s, wcy+22*s], fill=TEAL_D)
        d.ellipse([wcx-30*s, wcy-14*s, wcx+34*s, wcy+16*s], fill=TEAL)
        d.line([(wcx-20*s, wcy+10*s), (wcx+30*s, wcy-6*s)], fill=TEAL_D, width=max(2, int(3*s)))
    elif wing == "spread":
        # 日光浴:两翼向两侧展开
        for sign in (-1, 1):
            base = (wcx, wcy + 2*s)
            tip  = (wcx + sign*86*s, wcy - 18*s)
            mid  = (wcx + sign*60*s, wcy + 26*s)
            d.polygon([base, tip, mid], fill=TEAL_D)
            d.polygon([(base[0], base[1]+6*s), (tip[0], tip[1]+10*s), (mid[0], mid[1]-4*s)], fill=TEAL)
    else:
        angle = {"midup": -0.5, "up": -1.1, "middown": 0.2}[wing]
        span = 70*s
        tip = (wcx + math.cos(angle)*span*0.2, wcy + math.sin(angle)*span)
        base_l = (wcx - 26*s, wcy + 8*s)
        base_r = (wcx + 20*s, wcy + 16*s)
        mid   = (wcx + 6*s, wcy + math.sin(angle)*span*0.6)
        d.polygon([base_l, base_r, tip], fill=TEAL_D)
        d.polygon([base_l, (base_l[0]+14*s, base_l[1]+6*s), mid], fill=TEAL)
        d.line([base_l, tip], fill=TEAL_D, width=max(2, int(3*s)))

    # ---- 头(青圆,左前)----
    head_lift = (14*s if head_up else 0) + head_raise_amt * s
    hx = cx - 46*s + head_tilt * s
    hy = cy - 30*s - head_lift
    hx -= 18*s * head_jab          # 啄:头向前(左)猛送
    hy += 12*s * head_jab          # 啄:头向下送
    E(hx, hy, 38*s, 36*s, TEAL)
    d.polygon([(hx-8*s, hy-32*s), (hx-2*s, hy-46*s), (hx+6*s, hy-30*s)], fill=TEAL_D)

    # ---- 白颊/耳斑 ----
    E(hx + 10*s, hy + 6*s, 16*s, 13*s, WHITE)
    E(hx - 4*s, hy + 26*s, 16*s, 10*s, WHITE)

    # ---- 喙(尖锥,朝左;张嘴时下喙尖端下落 → 朝前张开,嘴尖仍尖)----
    by = hy + 6*s + (4*s if look_down else 0)
    beak_drop = 9*s if mouth_open else 0
    # 上喙(尖)
    d.polygon([(hx-30*s, by-5*s), (hx-72*s, by+2*s),
               (hx-72*s, by+6*s), (hx-30*s, by+10*s)], fill=BEAK)
    # 下喙(三角,尖在嘴尖;张嘴时尖端下落;再加厚)
    d.polygon([(hx-30*s, by+6*s), (hx-72*s, by+7*s + beak_drop),
               (hx-30*s, by+16*s)], fill=(40, 40, 40, 255))
    # 张嘴时的橙色口腔
    if mouth_open:
        d.polygon([(hx-32*s, by+6*s), (hx-70*s, by+8*s + beak_drop*0.4),
                   (hx-32*s, by+14*s)], fill=(230, 120, 70, 255))
    # 舌头(死掉)
    if tongue:
        d.polygon([(hx-60*s, by+14*s), (hx-72*s, by+22*s), (hx-58*s, by+16*s)], fill=(235, 110, 130, 255))

    # ---- 眼睛 ----
    ex, ey = hx - 6*s, hy - 4*s + (6*s if look_down else 0)
    if heart_eye:
        heart(d, ex, ey, 13*s, HEART)
    elif x_eye:
        # 死掉:X 眼
        r = 7*s
        for a, b in [((ex-r, ey-r),(ex+r, ey+r)), ((ex-r, ey+r),(ex+r, ey-r))]:
            d.line([a, b], fill=EYE, width=max(2, int(3*s)))
    elif eye_closed:
        d.arc([ex-10*s, ey-5*s, ex+10*s, ey+9*s], 200, 340, fill=EYE, width=max(2, int(4*s)))
    else:
        E(ex, ey, 8*s, 8*s, WHITE)
        pr = 5*s if alert else 6*s
        E(ex + 1*s, ey + 1*s, pr, pr, EYE)
        d.ellipse([ex-1*s, ey-4*s, ex+4*s, ey+1*s], fill=WHITE)
        if alert:  # 锐利眉头
            d.line([(ex-9*s, ey-9*s), (ex+2*s, ey-6*s)], fill=EYE, width=max(2, int(3*s)))

    # ---- 用力汗滴 ----
    if sweat:
        sx, sy = hx + 30*s, hy - 16*s
        d.polygon([(sx-4*s, sy), (sx, sy-12*s), (sx+4*s, sy)], fill=(120, 200, 230, 255))
        d.ellipse([sx-4*s, sy-2*s, sx+4*s, sy+6*s], fill=(120, 200, 230, 255))

    # ---- 爪(橙)----
    def leg(x_top, x_bot, lift=False):
        y_top = cy + 40*s
        y_bot = (cy + 58*s) if not lift else (cy + 46*s)
        d.line([(x_top, y_top), (x_bot, y_bot)], fill=LEG, width=max(2, int(4*s)))
        for dx in (-6*s, 0, 6*s):
            d.line([(x_bot, y_bot), (x_bot+dx, y_bot+7*s)], fill=LEG, width=max(2, int(3*s)))
    if wing in ("up", "midup", "middown") or hide_legs:
        if not hide_legs:  # 飞行收爪
            for x_top in (cx-14*s, cx+12*s):
                d.line([(x_top, cy+34*s), (x_top+2*s, cy+44*s)], fill=LEG, width=max(2, int(4*s)))
    else:
        left_x  = cx - 16*s + math.cos(leg_phase*math.pi) * 8*s
        right_x = cx + 16*s - math.cos(leg_phase*math.pi) * 8*s
        left_lift  = math.sin(leg_phase*math.pi*2) > 0.3
        right_lift = math.sin(leg_phase*math.pi*2 + math.pi) > 0.3
        leg(left_x, left_x, lift=left_lift)
        leg(right_x, right_x, lift=right_lift)

    # ---- 叼鱼/吞鱼(fish_bite: 0=完整 1=吃完)----
    bite = 0.0 if fish_in_beak else fish_bite
    if fish_in_beak or (0.0 < fish_bite < 1.0):
        fl = 14*s * (1 - bite * 0.85)
        if fl > 2*s:
            fx = (hx - 78*s) + bite * 34*s    # 鱼往喙里送
            fy = by + 24*s - bite * 8*s
            d.ellipse([fx-fl, fy-7*s, fx+fl, fy+7*s], fill=FISH_BODY)
            d.polygon([(fx+fl*0.8, fy), (fx+fl*1.8, fy-8*s),
                       (fx+fl*1.8, fy+8*s)], fill=FISH_DARK)
            if bite < 0.6:
                d.ellipse([fx-4*s, fy-2*s, fx+1*s, fy+3*s], fill=EYE)  # 鱼眼

    # ---- 红晕 ----
    if blush:
        E(hx + 14*s, hy + 14*s, 8*s, 6*s, BLUSH)

    # ---- Zzz(用真字体,递增小写 z,经典睡觉符号)----
    if zzz:
        for tx, ty, sz in [(hx + 34*s, hy - 22*s, 20),
                           (hx + 52*s, hy - 42*s, 30),
                           (hx + 74*s, hy - 68*s, 42)]:
            d.text((tx, ty), "z", font=font(int(sz*s)), fill=ZCOLOR)

    return img


def draw_egg(W, H, stage):
    """stage: 0 整蛋 1 裂纹 2 破壳探头"""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = W / 256.0
    cx, cy = W * 0.5, H * 0.66
    rx, ry = 58*s, 74*s
    import random
    rnd = random.Random(7)

    if stage < 2:
        # 整蛋 + 斑点 + 阴影
        d.ellipse([cx-rx, cy-ry, cx+rx, cy+ry], fill=EGG_SHELL)
        for _ in range(14):
            ang = rnd.random()*math.pi*2
            rr = rnd.random()*0.8
            px = cx + math.cos(ang)*rx*rr
            py = cy + math.sin(ang)*ry*rr
            d.ellipse([px-3*s, py-3*s, px+3*s, py+3*s], fill=EGG_SPCK)
        if stage >= 1:
            pts = [(cx-6*s, cy-ry*0.8), (cx+8*s, cy-ry*0.4), (cx-6*s, cy),
                   (cx+10*s, cy+ry*0.3), (cx-4*s, cy+ry*0.7)]
            for i in range(len(pts)-1):
                d.line([pts[i], pts[i+1]], fill=EGG_SPCK, width=max(2, int(3*s)))
    else:
        # 破壳:下半壳杯 + 两片碎壳 + 探出的鸟头
        rimY = cy - ry*0.12
        cup = [(cx-rx, rimY)]
        n = 9
        for i in range(n+1):
            t = i / n
            xx = cx - rx + 2*rx*t
            yy = rimY + (7*s if i % 2 else -7*s)
            cup.append((xx, yy))
        cup.append((cx+rx, rimY))
        steps = 26
        for i in range(1, steps):
            t = math.pi + math.pi*(i/steps)   # 下半椭圆
            cup.append((cx + rx*math.cos(t), cy + ry*math.sin(t)))
        d.polygon(cup, fill=EGG_SHELL)
        for _ in range(10):
            ang = math.pi*rnd.random() + math.pi
            rr = rnd.random()*0.8
            px = cx + math.cos(ang)*rx*rr
            py = cy + math.sin(ang)*ry*rr
            d.ellipse([px-3*s, py-3*s, px+3*s, py+3*s], fill=EGG_SPCK)
        # 两片碎壳
        d.polygon([(cx-rx*0.5, rimY-2*s), (cx-rx*0.95, rimY-28*s),
                   (cx-rx*0.1, rimY-22*s), (cx-rx*0.2, rimY+2*s)], fill=EGG_SHELL)
        d.polygon([(cx+rx*0.5, rimY-2*s), (cx+rx*0.95, rimY-28*s),
                   (cx+rx*0.1, rimY-22*s), (cx+rx*0.2, rimY+2*s)], fill=EGG_SHELL)
        # 探出的鸟头
        hcx, hcy = cx, rimY - 24*s
        d.ellipse([hcx-28*s, hcy-26*s, hcx+28*s, hcy+24*s], fill=TEAL)
        d.polygon([(hcx-28*s, hcy-4*s), (hcx-58*s, hcy+2*s), (hcx-28*s, hcy+8*s)], fill=BEAK)
        d.ellipse([hcx+6*s, hcy-14*s, hcx+20*s, hcy], fill=WHITE)
        d.ellipse([hcx+10*s, hcy-10*s, hcx+18*s, hcy-2*s], fill=EYE)
    return img


def render(name, rotate=0, egg_stage=None, **kw):
    if egg_stage is not None:
        big = draw_egg(SIZE*SS, SIZE*SS, egg_stage)
    else:
        big = draw_kingfisher(SIZE*SS, SIZE*SS, **kw)
    if rotate:
        big = big.rotate(rotate, resample=Image.BICUBIC, expand=False)
    small = big.resize((SIZE, SIZE), Image.LANCZOS)
    small.save(os.path.join(OUT, name + ".png"))
    print("  wrote", name + ".png")


def render_shadow(name="shadow"):
    """柔和的地面阴影:径向渐变椭圆(黑色 alpha 软衰减)。由 ShadowController 缩放使用。"""
    W, H = 256, 96
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    cx, cy = W / 2, H / 2
    rx, ry = W * 0.48, H * 0.46
    for y in range(H):
        for x in range(W):
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            r = math.sqrt(dx * dx + dy * dy)
            if r < 1.0:
                # 硬边:中心实、衰减陡(羽化小)
                a = int(238 * (1 - r) ** 3.2)
                px[x, y] = (0, 0, 0, a)
    img.save(os.path.join(OUT, name + ".png"))
    print("  wrote", name + ".png")


def render_branch(name="branch"):
    """一根带叶小树枝:鸟停在高处时脚下停靠用。"""
    SS = 4
    W, H = 256 * SS, 96 * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = SS
    cy = H * 0.52
    # 枝干
    d.line([(W * 0.08, cy + 2 * s), (W * 0.92, cy - 2 * s)],
           fill=(104, 70, 40, 255), width=int(11 * s))
    d.line([(W * 0.10, cy + 1 * s), (W * 0.90, cy - 1 * s)],
           fill=(140, 98, 56, 255), width=int(6 * s))
    # 小分枝节
    for fx in (0.30, 0.62):
        d.ellipse([W * fx - 4 * s, cy - 5 * s, W * fx + 4 * s, cy + 5 * s],
                  fill=(90, 60, 34, 255))
    # 叶子
    leaf = (88, 168, 78, 255)
    leaf_d = (60, 128, 56, 255)
    for lx, ang, sc in [(0.30, 0.7, 1.0), (0.50, -0.6, 0.9), (0.66, 0.5, 1.0), (0.80, -0.5, 0.8)]:
        cx = W * lx
        l = 30 * s * sc
        ex = cx + math.cos(ang) * l
        ey = cy - math.sin(ang) * l
        d.ellipse([min(cx, ex) - 9 * s, min(cy, ey) - 11 * s,
                   max(cx, ex) + 9 * s, max(cy, ey) + 11 * s], fill=leaf)
        d.ellipse([min(cx, ex) - 3 * s, min(cy, ey) - 4 * s,
                   max(cx, ex) + 3 * s, max(cy, ey) + 4 * s], fill=leaf_d)
    img.resize((256, 96), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))
    print("  wrote", name + ".png")


def montage(names, out="contact.png"):
    """把若干帧拼成一张检查图"""
    cols = 4
    rows = math.ceil(len(names)/cols)
    cell = SIZE
    sheet = Image.new("RGBA", (cols*cell, rows*cell), (24, 28, 34, 255))
    from PIL import ImageFont
    for i, (label, fn) in enumerate(names):
        r, c = divmod(i, cols)
        p = os.path.join(OUT, fn + ".png")
        if os.path.exists(p):
            im = Image.open(p).convert("RGBA")
            sheet.alpha_composite(im, (c*cell, r*cell))
    sheet.save(os.path.join(OUT, out))
    print("  wrote", out)


def main():
    os.makedirs(OUT, exist_ok=True)
    # 基础
    render("idle_0", wing="folded", body_dy=0)
    render("idle_1", wing="folded", body_dy=-3)
    render("idle_blink", wing="folded", eye_closed=True)
    render("walk_0", wing="folded", leg_phase=0.0)
    render("walk_1", wing="folded", leg_phase=0.25)
    render("walk_2", wing="folded", leg_phase=0.5)
    render("walk_3", wing="folded", leg_phase=0.75)
    render("fly_0", wing="folded")
    render("fly_1", wing="midup")
    render("fly_2", wing="up")
    render("fly_3", wing="middown")
    render("happy_0", wing="folded", mouth_open=True, heart_eye=True, blush=True, body_dy=-2)
    render("happy_1", wing="midup",  mouth_open=True, heart_eye=True, blush=True, body_dy=-8)
    render("sleep_0", wing="folded", eye_closed=True, body_dy=0)
    render("sleep_1", wing="folded", eye_closed=True, body_dy=-2)

    # 习性:俯冲捕鱼相关
    render("dive_0", wing="folded", hide_legs=True, rotate=90)          # 流线型朝下
    render("fly_fish_0", wing="folded", fish_in_beak=True)
    render("fly_fish_1", wing="midup",  fish_in_beak=True)
    render("fly_fish_2", wing="up",     fish_in_beak=True)
    render("fly_fish_3", wing="middown", fish_in_beak=True)
    render("eat_0", wing="folded", fish_in_beak=True, head_up=True, mouth_open=True)
    render("eat_1", wing="folded", fish_bite=0.55, head_up=True, mouth_open=True)
    render("eat_2", wing="folded", fish_bite=1.0, head_up=True,
           head_raise_amt=10, eye_closed=True)                            # 仰脖吞下,眯眼满足

    # 习性:鸣唱
    render("sing_0", wing="folded", head_up=True, mouth_open=True)
    render("sing_1", wing="midup",  head_up=True, mouth_open=True)

    # 习性:栖枝守候(锐利眼神 + 歪头)
    render("watch_0", wing="folded", alert=True)
    render("watch_1", wing="folded", alert=True, head_tilt=-4)

    # 习性:日光浴(展翅蓬毛)
    render("sun_0", wing="spread", fluff=True, eye_closed=True)
    render("sun_1", wing="spread", fluff=True)

    # 习性:啄屏幕(头带动猛啄,闭嘴)
    render("peck_0", wing="folded", look_down=True, head_jab=1.0, body_dy=-2)
    render("peck_1", wing="folded")

    # 显示/隐藏:蛋壳 + 死掉
    render("egg_0", egg_stage=0)
    render("egg_1", egg_stage=1)
    render("egg_2", egg_stage=2)
    render("dead", wing="up", x_eye=True, tongue=True, hide_legs=True, rotate=180)

    # 地面阴影贴图(运行时按太阳角度缩放)
    render_shadow()
    # 树枝贴图(高处停靠)
    render_branch()

    # 吃完拉屎:翘屁股 + 尾巴摆 + 汗滴
    render("poop_0", wing="folded", butt_up=True, tail_wag=-5, sweat=True, body_dy=4)
    render("poop_1", wing="folded", butt_up=True, tail_wag=5, sweat=True, body_dy=4)

    seq = {
        "fps": {
            "idle": 4, "walk": 8, "fly": 10, "happy": 6, "sleep": 2,
            "dive": 8, "fly_fish": 10, "eat": 4, "sing": 6, "watch": 3,
            "sun": 3, "hover": 10, "egg": 4, "dead": 1, "poop": 6, "peck": 8
        },
        "sequences": {
            "idle":     ["idle_0", "idle_1", "idle_0", "idle_blink"],
            "walk":     ["walk_0", "walk_1", "walk_2", "walk_3"],
            "fly":      ["fly_1", "fly_2", "fly_3", "fly_2"],   # 空中全程扇翅
            "hover":    ["fly_1", "fly_2", "fly_1", "fly_3"],   # 悬停=原地振翅
            "happy":    ["happy_0", "happy_1", "happy_0", "happy_1"],
            "sleep":    ["sleep_0", "sleep_1"],
            "dive":     ["dive_0"],
            "fly_fish": ["fly_fish_1", "fly_fish_2", "fly_fish_3", "fly_fish_2"],
            "eat":      ["eat_0", "eat_0", "eat_1", "eat_2"],
            "sing":     ["sing_0", "sing_1"],
            "watch":    ["watch_0", "watch_1"],
            "sun":      ["sun_0", "sun_1"],
            "egg":      ["egg_0", "egg_0", "egg_1", "egg_1", "egg_2"],
            "dead":     ["dead"],
            "poop":     ["poop_0", "poop_1", "poop_0", "poop_1", "poop_0"],
            "peck":     ["peck_0", "peck_1"]
        }
    }
    with open(os.path.join(OUT, "sprites.json"), "w") as f:
        json.dump(seq, f, indent=2)
    print("  wrote sprites.json")

    # 检查图
    montage([
        ("dive", "dive_0"), ("fly_fish", "fly_fish_0"), ("eat0", "eat_0"),
        ("eat1", "eat_1"), ("eat2", "eat_2"),
        ("sing", "sing_0"), ("watch", "watch_0"), ("sun", "sun_0"),
        ("egg0", "egg_0"), ("egg1", "egg_1"), ("egg2", "egg_2"),
        ("dead", "dead"), ("poop", "poop_0"),
    ])


def gen_peep():
    """生成一个短促的‘啾’声(频率上扫+淡入淡出),16-bit PCM wav。"""
    out = os.path.join(os.path.dirname(__file__), "..", "Resources", "peep.wav")
    sr = 22050
    dur = 0.16
    n = int(sr * dur)
    frames = []
    phase = 0.0
    for i in range(n):
        t = i / sr
        f = 1700 + (2600 - 1700) * (i / n)
        f += 40 * math.sin(2 * math.pi * 18 * t)
        env = math.sin(math.pi * i / n)
        amp = 0.35 * env
        phase += 2 * math.pi * f / sr
        s = amp * math.sin(phase)
        frames.append(int(max(-1, min(1, s)) * 32767))
    with wave.open(out, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(struct.pack("<" + "h" * n, *frames))
    print("  wrote peep.wav")


if __name__ == "__main__":
    main()
    gen_peep()
