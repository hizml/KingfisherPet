#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
翠鸟(翡)桌面宠物 sprite 生成器 · 多主题版

几何绘制路径(draw_kingfisher / draw_egg)对所有主题一致,只换调色板;
再叠加每个主题的"后处理器"(对 flat 成品帧做风格转换)。

输出到 ../Resources/Sprites/<theme>/{*.png, sprites.json},
以及 ../Resources/peep_*.wav(多种叫声,不随主题变)。

主题清单见 THEMES:flat / clay / pixel / neon / ink / watercolor。
"""
import math, os, json, wave, struct, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps

RES = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "Resources"))
OUT_BASE = os.path.join(RES, "Sprites")
SS = 4            # 几何超采样倍数
SIZE = 256        # 输出尺寸

# ---- 基础调色板(flat 主题直接用)----
# 键名即绘制函数里 C("name") 取的色名;色值是 RGBA。
BASE_PALETTE = {
    "TEAL":     (22, 166, 179, 255),
    "TEAL_D":   (15, 120, 132, 255),
    "ORANGE":   (240, 145, 59, 255),
    "ORANGE_D": (214, 110, 36, 255),
    "WHITE":    (253, 246, 230, 255),
    "BEAK":     (26, 26, 26, 255),
    "BEAK_D":   (40, 40, 40, 255),   # 下喙
    "BEAK_HI":  (70, 70, 70, 255),   # 喙基高光
    "EYE":      (24, 28, 32, 255),
    "LEG":      (224, 96, 48, 255),
    "BLUSH":    (244, 122, 142, 180),
    "HEART":    (235, 84, 110, 255),
    "ZCOLOR":   (150, 196, 206, 255),
    "FISH_BODY":(202, 214, 222, 255),
    "FISH_DARK":(150, 168, 180, 255),
    "EGG_SHELL":(252, 244, 224, 255),
    "EGG_SPCK": (196, 158, 96, 255),
    "BELLY":    (255, 196, 120, 255),
    "MOUTH":    (230, 120, 70, 255),
    "TONGUE":   (235, 110, 130, 255),
    "SWEAT":    (120, 200, 230, 255),
    "BRANCH":   (104, 70, 40, 255),
    "BRANCH_L": (140, 98, 56, 255),
    "BRANCH_D": (90, 60, 34, 255),
    "LEAF":     (88, 168, 78, 255),
    "LEAF_D":   (60, 128, 56, 255),
}

# ---- 主题调色板(只列要覆盖的键;未列出的沿用 BASE_PALETTE)----
THEME_PALETTES = {
    "flat": {},   # 完全用基础
    "clay": {},   # 几何色不变,靠后处理加软 3D
    "pixel": {},  # 靠后处理量化
    "neon": {
        "TEAL":     (0, 229, 255, 255),
        "TEAL_D":   (0, 170, 200, 255),
        "ORANGE":   (255, 140, 40, 255),
        "ORANGE_D": (220, 95, 20, 255),
        "WHITE":    (210, 245, 255, 255),
        "BEAK":     (40, 40, 60, 255),
        "BEAK_D":   (20, 20, 36, 255),
        "BEAK_HI":  (90, 90, 120, 255),
        "EYE":      (10, 10, 20, 255),
        "LEG":      (255, 90, 120, 255),
        "HEART":    (255, 60, 160, 255),
        "ZCOLOR":   (0, 229, 255, 255),
    },
    "ink": {
        "TEAL":     (28, 28, 28, 255),
        "TEAL_D":   (10, 10, 10, 255),
        "ORANGE":   (200, 70, 30, 255),   # 一抹橙保留
        "ORANGE_D": (150, 50, 20, 255),
        "WHITE":    (240, 240, 235, 255),
        "BEAK":     (0, 0, 0, 255),
        "BEAK_D":   (0, 0, 0, 255),
        "BEAK_HI":  (80, 80, 80, 255),
        "EYE":      (0, 0, 0, 255),
        "LEG":      (0, 0, 0, 255),
        "HEART":    (180, 40, 30, 255),
        "ZCOLOR":   (60, 60, 60, 255),
        "FISH_BODY":(60, 60, 60, 255),
        "FISH_DARK":(20, 20, 20, 255),
        "EGG_SHELL":(235, 230, 220, 255),
        "EGG_SPCK": (40, 40, 40, 255),
        "BELLY":    (220, 90, 40, 255),
    },
    "watercolor": {
        "TEAL":     (60, 150, 165, 235),
        "TEAL_D":   (40, 110, 125, 225),
        "ORANGE":   (235, 140, 70, 235),
        "ORANGE_D": (205, 105, 50, 225),
        "WHITE":    (252, 248, 238, 230),
        "BEAK":     (50, 45, 50, 235),
        "EYE":      (40, 40, 45, 235),
        "LEG":      (210, 100, 70, 230),
        "HEART":    (225, 100, 120, 230),
        "ZCOLOR":   (120, 170, 180, 230),
    },
}

def palette_for(theme):
    p = dict(BASE_PALETTE)
    p.update(THEME_PALETTES.get(theme, {}))
    return p


# ---- 系统字体(用于 zzz 等文字),带缓存 ----
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


def heart(d, cx, cy, r, color):
    poly = []
    for deg in range(0, 360, 8):
        t = math.radians(deg)
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t))
        poly.append((cx + x * r / 16.0, cy + y * r / 16.0))
    d.polygon(poly, fill=color)


def draw_kingfisher(W, H, pal, *, wing="folded", leg_phase=0.0, eye_closed=False,
                    body_dy=0, blush=False, heart_eye=False, zzz=False,
                    head_up=False, mouth_open=False, alert=False,
                    head_tilt=0.0, hide_legs=False, fish_in_beak=False,
                    look_down=False, x_eye=False, tongue=False,
                    fluff=False, tail_wag=0.0, butt_up=False, sweat=False,
                    fish_bite=0.0, head_raise_amt=0.0, head_jab=0.0):
    """画一只翠鸟,返回 RGBA Image。wing: folded / midup / up / middown / spread。
    pal:调色板 dict(色名 -> RGBA)。"""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = W / 256.0

    def C(name):
        return pal[name]

    def E(cx, cy, rx, ry, fill):
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill)

    cx, cy = W * 0.54, H * 0.58 + body_dy * s

    # ---- 身体(橙腹)----
    body_rx = 62*s + (8*s if fluff else 0)
    body_ry = 52*s + (8*s if fluff else 0)
    E(cx, cy + 6*s, body_rx, body_ry, C("ORANGE"))
    E(cx - 10*s, cy + 16*s, 30*s, 26*s, C("BELLY"))

    # ---- 背/披风(青)----
    d.pieslice([cx-72*s, cy-44*s, cx+74*s, cy+34*s], 180, 360, fill=C("TEAL"))
    d.pieslice([cx-10*s, cy-44*s, cx+74*s, cy+10*s], 180, 360, fill=C("TEAL_D"))

    # ---- 尾巴(青,右后;butt_up 翘起 + tail_wag 左右摆)----
    ty = (-14*s) if butt_up else 0
    tw = tail_wag * s
    tail = [(cx+58*s+tw, cy-2*s+ty), (cx+96*s+tw, cy-22*s+ty),
            (cx+98*s+tw, cy-4*s+ty), (cx+64*s+tw, cy+14*s+ty)]
    d.polygon(tail, fill=C("TEAL"))
    d.polygon([(cx+74*s+tw, cy-6*s+ty), (cx+92*s+tw, cy-18*s+ty),
               (cx+84*s+tw, cy-4*s+ty)], fill=C("TEAL_D"))

    # ---- 翅膀 ----
    wcx, wcy = cx + 4*s, cy + 2*s
    if wing == "folded":
        d.ellipse([wcx-40*s, wcy-22*s, wcx+40*s, wcy+22*s], fill=C("TEAL_D"))
        d.ellipse([wcx-30*s, wcy-14*s, wcx+34*s, wcy+16*s], fill=C("TEAL"))
        d.line([(wcx-20*s, wcy+10*s), (wcx+30*s, wcy-6*s)], fill=C("TEAL_D"), width=max(2, int(3*s)))
    elif wing == "spread":
        # 日光浴:两翼向两侧展开
        for sign in (-1, 1):
            base = (wcx, wcy + 2*s)
            tip  = (wcx + sign*86*s, wcy - 18*s)
            mid  = (wcx + sign*60*s, wcy + 26*s)
            d.polygon([base, tip, mid], fill=C("TEAL_D"))
            d.polygon([(base[0], base[1]+6*s), (tip[0], tip[1]+10*s), (mid[0], mid[1]-4*s)], fill=C("TEAL"))
    else:
        angle = {"midup": -0.5, "up": -1.1, "middown": 0.2}[wing]
        span = 70*s
        tip = (wcx + math.cos(angle)*span*0.2, wcy + math.sin(angle)*span)
        base_l = (wcx - 26*s, wcy + 8*s)
        base_r = (wcx + 20*s, wcy + 16*s)
        mid   = (wcx + 6*s, wcy + math.sin(angle)*span*0.6)
        d.polygon([base_l, base_r, tip], fill=C("TEAL_D"))
        d.polygon([base_l, (base_l[0]+14*s, base_l[1]+6*s), mid], fill=C("TEAL"))
        d.line([base_l, tip], fill=C("TEAL_D"), width=max(2, int(3*s)))

    # ---- 头(青圆,左前)----
    head_lift = (14*s if head_up else 0) + head_raise_amt * s
    hx = cx - 46*s + head_tilt * s
    hy = cy - 30*s - head_lift
    hx -= 18*s * head_jab          # 啄:头向前(左)猛送
    hy += 12*s * head_jab          # 啄:头向下送
    E(hx, hy, 38*s, 36*s, C("TEAL"))
    d.polygon([(hx-8*s, hy-32*s), (hx-2*s, hy-46*s), (hx+6*s, hy-30*s)], fill=C("TEAL_D"))

    # ---- 白颊/耳斑 ----
    E(hx + 10*s, hy + 6*s, 16*s, 13*s, C("WHITE"))
    E(hx - 4*s, hy + 26*s, 16*s, 10*s, C("WHITE"))

    # ---- 喙(尖锥,朝左;张嘴时下喙尖端下落 → 朝前张开,嘴尖仍尖)----
    by = hy + 6*s + (4*s if look_down else 0)
    beak_drop = 9*s if mouth_open else 0
    # 张嘴:先口腔、再舌头(都在喙之下 → 上下喙后画、层级都高于舌头,舌头只在缝里露)
    if mouth_open:
        d.polygon([(hx-32*s, by+6*s), (hx-70*s, by+8*s + beak_drop*0.4),
                   (hx-32*s, by+14*s)], fill=C("MOUTH"))
        if not tongue:
            # 舌头:扁平、贴下喙;底(by+14)严格在下喙底(by+16)之上,下喙盖住超出部分
            d.ellipse([hx-66*s, by+9*s, hx-48*s, by+14*s], fill=C("TONGUE"))
    # 上喙(尖)
    d.polygon([(hx-30*s, by-5*s), (hx-72*s, by+2*s),
               (hx-72*s, by+6*s), (hx-30*s, by+10*s)], fill=C("BEAK"))
    # 下喙(三角,尖在嘴尖;张嘴时尖端下落;再加厚)
    d.polygon([(hx-30*s, by+6*s), (hx-72*s, by+7*s + beak_drop),
               (hx-30*s, by+16*s)], fill=C("BEAK_D"))
    # 喙基高光
    d.polygon([(hx-34*s, by-3*s), (hx-50*s, by), (hx-40*s, by+3*s)], fill=C("BEAK_HI"))
    # 舌头(死掉,单独,不改)
    if tongue:
        d.polygon([(hx-60*s, by+14*s), (hx-72*s, by+22*s), (hx-58*s, by+16*s)],
                  fill=C("TONGUE"))

    # ---- 眼睛 ----
    ex, ey = hx - 6*s, hy - 4*s + (6*s if look_down else 0)
    if heart_eye:
        heart(d, ex, ey, 13*s, C("HEART"))
    elif x_eye:
        # 死掉:X 眼
        r = 7*s
        for a, b in [((ex-r, ey-r),(ex+r, ey+r)), ((ex-r, ey+r),(ex+r, ey-r))]:
            d.line([a, b], fill=C("EYE"), width=max(2, int(3*s)))
    elif eye_closed:
        d.arc([ex-10*s, ey-5*s, ex+10*s, ey+9*s], 200, 340, fill=C("EYE"), width=max(2, int(4*s)))
    else:
        E(ex, ey, 8*s, 8*s, C("WHITE"))
        pr = 5*s if alert else 6*s
        E(ex + 1*s, ey + 1*s, pr, pr, C("EYE"))
        d.ellipse([ex-1*s, ey-4*s, ex+4*s, ey+1*s], fill=C("WHITE"))
        if alert:  # 锐利眉头
            d.line([(ex-9*s, ey-9*s), (ex+2*s, ey-6*s)], fill=C("EYE"), width=max(2, int(3*s)))

    # ---- 用力汗滴 ----
    if sweat:
        sx, sy = hx + 30*s, hy - 16*s
        d.polygon([(sx-4*s, sy), (sx, sy-12*s), (sx+4*s, sy)], fill=C("SWEAT"))
        d.ellipse([sx-4*s, sy-2*s, sx+4*s, sy+6*s], fill=C("SWEAT"))

    # ---- 爪(橙)----
    def leg(x_top, x_bot, lift=False):
        y_top = cy + 40*s
        y_bot = (cy + 58*s) if not lift else (cy + 46*s)
        d.line([(x_top, y_top), (x_bot, y_bot)], fill=C("LEG"), width=max(2, int(4*s)))
        for dx in (-6*s, 0, 6*s):
            d.line([(x_bot, y_bot), (x_bot+dx, y_bot+7*s)], fill=C("LEG"), width=max(2, int(3*s)))
    if wing in ("up", "midup", "middown") or hide_legs:
        if not hide_legs:  # 飞行收爪
            for x_top in (cx-14*s, cx+12*s):
                d.line([(x_top, cy+34*s), (x_top+2*s, cy+44*s)], fill=C("LEG"), width=max(2, int(4*s)))
    else:
        left_x  = cx - 16*s + math.cos(leg_phase*math.pi) * 8*s
        right_x = cx + 16*s - math.cos(leg_phase*math.pi) * 8*s
        left_lift  = math.sin(leg_phase*math.pi*2) > 0.3
        right_lift = math.sin(leg_phase*math.pi*2 + math.pi) > 0.3
        leg(left_x, left_x, lift=left_lift)
        leg(right_x, right_x, lift=right_lift)

    # ---- 叼鱼/吞鱼:鱼从嘴尖竖直下垂(头在嘴尖、身朝下);bite 增大抬进嘴里、缩短 ----
    bite = 0.0 if fish_in_beak else fish_bite
    if fish_in_beak or (0.0 < fish_bite < 1.0):
        fl = 18*s * (1 - bite * 0.85)                  # 鱼长(竖向)
        fw = 6*s
        if fl > 3*s:
            fcx = (hx - 72*s) + bite * 10*s            # 鱼头在嘴尖,随 bite 进嘴
            fcy = by + 8*s + fl / 2 - bite * fl * 0.4   # 鱼中心,随 bite 上抬
            d.ellipse([fcx - fw, fcy - fl/2, fcx + fw, fcy + fl/2], fill=C("FISH_BODY"))
            d.polygon([(fcx, fcy + fl/2), (fcx - 6*s, fcy + fl/2 + 9*s),
                       (fcx + 6*s, fcy + fl/2 + 9*s)], fill=C("FISH_DARK"))   # 尾在下
            if bite < 0.6:
                d.ellipse([fcx - 2*s, fcy - fl/2, fcx + 3*s, fcy - fl/2 + 4*s], fill=C("EYE"))  # 眼靠头(上)

    # ---- 红晕 ----
    if blush:
        E(hx + 14*s, hy + 14*s, 8*s, 6*s, C("BLUSH"))

    # ---- Zzz(用真字体,递增小写 z,经典睡觉符号)----
    if zzz:
        for tx, ty, sz in [(hx + 34*s, hy - 22*s, 20),
                           (hx + 52*s, hy - 42*s, 30),
                           (hx + 74*s, hy - 68*s, 42)]:
            d.text((tx, ty), "z", font=font(int(sz*s)), fill=C("ZCOLOR"))

    return img


def draw_egg(W, H, pal, stage):
    """stage: 0 整蛋 1 裂纹 2 破壳探头"""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = W / 256.0

    def C(name):
        return pal[name]

    cx, cy = W * 0.5, H * 0.66
    rx, ry = 58*s, 74*s
    rnd = random.Random(7)

    if stage < 2:
        # 整蛋 + 斑点 + 阴影
        d.ellipse([cx-rx, cy-ry, cx+rx, cy+ry], fill=C("EGG_SHELL"))
        for _ in range(14):
            ang = rnd.random()*math.pi*2
            rr = rnd.random()*0.8
            px = cx + math.cos(ang)*rx*rr
            py = cy + math.sin(ang)*ry*rr
            d.ellipse([px-3*s, py-3*s, px+3*s, py+3*s], fill=C("EGG_SPCK"))
        if stage >= 1:
            pts = [(cx-6*s, cy-ry*0.8), (cx+8*s, cy-ry*0.4), (cx-6*s, cy),
                   (cx+10*s, cy+ry*0.3), (cx-4*s, cy+ry*0.7)]
            for i in range(len(pts)-1):
                d.line([pts[i], pts[i+1]], fill=C("EGG_SPCK"), width=max(2, int(3*s)))
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
        d.polygon(cup, fill=C("EGG_SHELL"))
        for _ in range(10):
            ang = math.pi*rnd.random() + math.pi
            rr = rnd.random()*0.8
            px = cx + math.cos(ang)*rx*rr
            py = cy + math.sin(ang)*ry*rr
            d.ellipse([px-3*s, py-3*s, px+3*s, py+3*s], fill=C("EGG_SPCK"))
        # 两片碎壳
        d.polygon([(cx-rx*0.5, rimY-2*s), (cx-rx*0.95, rimY-28*s),
                   (cx-rx*0.1, rimY-22*s), (cx-rx*0.2, rimY+2*s)], fill=C("EGG_SHELL"))
        d.polygon([(cx+rx*0.5, rimY-2*s), (cx+rx*0.95, rimY-28*s),
                   (cx+rx*0.1, rimY-22*s), (cx+rx*0.2, rimY+2*s)], fill=C("EGG_SHELL"))
        # 探出的鸟头
        hcx, hcy = cx, rimY - 24*s
        d.ellipse([hcx-28*s, hcy-26*s, hcx+28*s, hcy+24*s], fill=C("TEAL"))
        d.polygon([(hcx-28*s, hcy-4*s), (hcx-58*s, hcy+2*s), (hcx-28*s, hcy+8*s)], fill=C("BEAK"))
        d.ellipse([hcx+6*s, hcy-14*s, hcx+20*s, hcy], fill=C("WHITE"))
        d.ellipse([hcx+10*s, hcy-10*s, hcx+18*s, hcy-2*s], fill=C("EYE"))
    return img


# =========================================================================
# 主题后处理器:作用在 flat 风格的成品 RGBA 帧上,返回风格化帧。
# 输入已是 SIZE x SIZE;输出同尺寸。
# =========================================================================

def _split_alpha(img):
    """返回 (rgb, alpha)。rgb 为透明区填黑的 RGB,alpha 为 L。"""
    img = img.convert("RGBA")
    return img.split()


def _compose(rgb_or_rgba, alpha):
    """用给定 alpha 合成(保持原色或新色)。"""
    base = rgb_or_rgba.convert("RGBA")
    r, g, b, _ = base.split()
    return Image.merge("RGBA", (r, g, b, alpha))


def post_clay(img):
    """粘土软陶:柔和内高光 + 右下投影 + 边缘减淡,模拟软 3D。"""
    img = img.convert("RGBA")
    alpha = img.split()[3]
    # 不透明区裁剪框(给高光/阴影定位)
    bbox = img.getbbox()

    # 1) 内高光:在主体上半叠一个偏白径向 alpha 椭圆
    hi = Image.new("RGBA", img.size, (0, 0, 0, 0))
    hd = ImageDraw.Draw(hi)
    if bbox:
        cx = (bbox[0] + bbox[2]) / 2
        cy = bbox[1] + (bbox[3] - bbox[1]) * 0.30
        rx = (bbox[2] - bbox[0]) * 0.42
        ry = (bbox[3] - bbox[1]) * 0.30
        hd.ellipse([cx-rx, cy-ry, cx+rx, cy+ry], fill=(255, 255, 255, 70))
    hi = hi.filter(ImageFilter.GaussianBlur(14))
    img = Image.alpha_composite(img, hi)

    # 2) 边缘减淡(浅色描边内收),模拟陶器反光
    edge = Image.new("RGBA", img.size, (255, 255, 255, 0))
    ed = ImageDraw.Draw(edge)
    ed.rectangle([0, 0, img.size[0], img.size[1]], fill=(255, 255, 255, 28))
    edge_alpha = alpha.filter(ImageFilter.MaxFilter(5))      # 稍微外扩
    inner = edge_alpha.filter(ImageFilter.MinFilter(9))      # 内缩一圈
    rim_mask = ImageChops_sub(edge_alpha, inner)             # 边缘带
    rim = _compose(Image.new("RGBA", img.size, (255, 255, 255, 255)), rim_mask)
    rim.putalpha(rim_mask)
    img = Image.alpha_composite(img, rim)

    # 3) 右下投影:把主体复制、染深、模糊、偏移,叠在主体之下
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rectangle([0, 0, img.size[0], img.size[1]], fill=(0, 0, 0, 90))
    sh_alpha = alpha.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(6))
    shadow.putalpha(sh_alpha)
    off = (6, 6)
    shadow = ImageChops_offset(shadow, off[0], off[1])
    # 投影在主体之下
    base = Image.alpha_composite(Image.new("RGBA", img.size, (0, 0, 0, 0)), shadow)
    img = Image.alpha_composite(base, img)
    return img


def post_pixel(img):
    """像素风:降采样到 64px(硬边块状)再 NEAREST 放回 256px;量化到限定色板。"""
    img = img.convert("RGBA")
    PX = 64
    small = img.resize((PX, PX), Image.NEAREST)
    # 量化色板:取 flat 主色 + 过渡
    palette_colors = [
        (22,166,179),(15,120,132),(240,145,59),(214,110,36),
        (253,246,230),(26,26,26),(40,40,40),(24,28,32),(224,96,48),
        (235,84,110),(255,196,120),(230,120,70),(235,110,130),
        (202,214,222),(150,168,180),(252,244,224),(196,158,96),
        (120,200,230),(88,168,78),(60,128,56),(150,196,206),
    ]
    px = small.load()
    for y in range(PX):
        for x in range(PX):
            r, g, b, a = px[x, y]
            if a < 40:
                px[x, y] = (0, 0, 0, 0)
                continue
            # 找最近色
            best = None
            best_d = 1e9
            for (cr, cg, cb) in palette_colors:
                d = (r-cr)**2 + (g-cg)**2 + (b-cb)**2
                if d < best_d:
                    best_d = d
                    best = (cr, cg, cb)
            px[x, y] = (best[0], best[1], best[2], 255 if a > 120 else a)
    return small.resize((SIZE, SIZE), Image.NEAREST)


def post_neon(img):
    """霓虹:深底 + 青橙发光描边 + 外发光。透明区保持透明。"""
    img = img.convert("RGBA")
    alpha = img.split()[3]

    # 1) 取边缘(主体轮廓)
    edge = alpha.filter(ImageFilter.FIND_EDGES)
    # 描边染色:亮青
    edge_blur = edge.filter(ImageFilter.GaussianBlur(2))
    glow_cyan = _compose(Image.new("RGBA", img.size, (0, 229, 255, 255)), edge_blur)

    # 2) 主体降暗、偏向深底(保留少量原色)
    darkened = Image.new("RGBA", img.size, (10, 14, 28, 0))
    # 只在主体内填深色,把原图饱和度压低、亮度降低
    gray = ImageOps.grayscale(img.convert("RGB"))
    dark_rgb = ImageOps.colorize(gray, black=(8, 12, 24), white=(30, 60, 80))
    body = dark_rgb.convert("RGBA")
    body.putalpha(alpha)
    # 叠一抹青橙(用原图 alpha 区分:橙腹区偏橙、其余偏青)—— 简化:整体偏青
    tint = Image.new("RGBA", img.size, (0, 180, 220, 60))
    tint.putalpha(ImageChops_mul(alpha, tint.split()[3]))
    body = Image.alpha_composite(body, tint)

    # 3) 外发光:主体 alpha 模糊后叠亮色
    glow = alpha.filter(ImageFilter.GaussianBlur(8))
    glow_layer = _compose(Image.new("RGBA", img.size, (0, 200, 255, 180)), glow)
    glow2 = alpha.filter(ImageFilter.GaussianBlur(16))
    glow_layer2 = _compose(Image.new("RGBA", img.size, (255, 120, 40, 90)), glow2)

    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out = Image.alpha_composite(out, glow_layer2)
    out = Image.alpha_composite(out, glow_layer)
    out = Image.alpha_composite(out, body)
    out = Image.alpha_composite(out, glow_cyan)
    return out


def post_ink(img):
    """水墨国风:灰度→阈值黑色写意笔触;喙/腹一抹橙保留。
    实现:把青/背/尾/头压成黑墨;橙腹/喙/腿保留;边缘加抖动笔触感。"""
    img = img.convert("RGBA")
    alpha = img.split()[3]
    rgb = img.convert("RGB")
    px = rgb.load()
    w, h = rgb.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    rnd = random.Random(12345)
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            a = img.getpixel((x, y))[3]
            if a < 30:
                continue
            # 判定是否橙色系(腹/喙):R 高、G/B 低
            is_orange = r > 150 and r - b > 60
            if is_orange:
                # 保留一抹橙,但稍微压暗、加水墨边缘抖动
                jitter = rnd.random() * 20 - 10
                op[x, y] = (max(0, min(255, int(r + jitter))),
                            max(0, min(255, int(g * 0.7))),
                            max(0, min(255, int(b * 0.6))),
                            a)
            else:
                # 转黑墨:亮度阈值 + 抖动
                lum = 0.299*r + 0.587*g + 0.114*b
                # 亮区(白颊)留白,暗区转黑
                if lum > 200:
                    op[x, y] = (235, 232, 225, a)
                else:
                    jitter = rnd.random() * 25
                    v = 0 if lum < 160 else int(40 - jitter)
                    v = max(0, min(60, v))
                    op[x, y] = (v, v, v, a)
    # 边缘墨晕:轻微模糊后 alpha 衰减叠加
    ink_bleed = out.filter(ImageFilter.GaussianBlur(0.8))
    return ink_bleed


def post_watercolor(img):
    """水彩手绘:轻渗色(GaussianBlur)+ 纸纹(multiply)+ 边缘水痕。"""
    img = img.convert("RGBA")
    alpha = img.split()[3]

    # 1) 渗色:轻微模糊颜色,保持 alpha 硬边
    blurred = img.filter(ImageFilter.GaussianBlur(1.2))
    # 用原 alpha 复位边缘(避免颜色溢出太远)
    b_r, b_g, b_b, _ = blurred.split()
    softened = Image.merge("RGBA", (b_r, b_g, b_b, alpha))

    # 2) 纸纹:随机噪声生成米色纸面,multiply 叠加
    w, h = img.size
    noise = Image.new("L", (w, h))
    npix = noise.load()
    rnd = random.Random(99)
    for y in range(h):
        for x in range(w):
            npix[x, y] = 225 + rnd.randint(-18, 18)
    paper = Image.merge("RGB", (noise, noise,
                                ImageOps.colorize(noise, (0, 0, 0), (250, 244, 230)).split()[1]))
    paper = paper.convert("RGBA")
    # multiply 纸纹(只在主体内)
    paper_a = ImageChops_mul(alpha, Image.new("L", (w, h), 255))
    paper.putalpha(paper_a)
    # 把纸纹作为底(主体外透明),主体颜色 multiply 纸纹
    # 用 ImageChops multiply 在 RGB 上
    mult = ImageChops_multiply(softened.convert("RGB"), paper.convert("RGB"))
    m_r, m_g, m_b = mult.split()
    result = Image.merge("RGBA", (m_r, m_g, m_b, alpha))

    # 3) 水痕边缘:边缘加深一点
    edge = alpha.filter(ImageFilter.FIND_EDGES)
    edge_dark = _compose(Image.new("RGBA", img.size, (60, 50, 60, 90)), edge)
    result = Image.alpha_composite(result, edge_dark)
    return result


def post_flat(img):
    return img.convert("RGBA")


POSTPROCESSORS = {
    "flat": post_flat,
    "clay": post_clay,
    "pixel": post_pixel,
    "neon": post_neon,
    "ink": post_ink,
    "watercolor": post_watercolor,
}

# 主题中文名(用于检查图标题/将来 UI)
THEME_NAMES = {
    "flat": "扁平卡通",
    "clay": "粘土软陶",
    "pixel": "像素风",
    "neon": "霓虹",
    "ink": "水墨国风",
    "watercolor": "水彩手绘",
}


# ---- ImageChops 辅助(避免每次 import 长名)----
def ImageChops_sub(a, b):
    from PIL import ImageChops
    return ImageChops.subtract(a, b)

def ImageChops_mul(a, b):
    from PIL import ImageChops
    return ImageChops.multiply(a, b)

def ImageChops_offset(img, x, y):
    from PIL import ImageChops
    return ImageChops.offset(img, x, y)

def ImageChops_multiply(a, b):
    from PIL import ImageChops
    return ImageChops.multiply(a.convert("RGB"), b.convert("RGB"))


def render(name, theme, pal, post, rotate=0, egg_stage=None, **kw):
    """渲染单帧:几何(SS 超采样)-> 缩到 SIZE -> rotate -> 后处理 -> 存主题目录。"""
    if egg_stage is not None:
        big = draw_egg(SIZE*SS, SIZE*SS, pal, egg_stage)
    else:
        big = draw_kingfisher(SIZE*SS, SIZE*SS, pal, **kw)
    if rotate:
        big = big.rotate(rotate, resample=Image.BICUBIC, expand=False)
    small = big.resize((SIZE, SIZE), Image.LANCZOS)
    # 后处理(在 SIZE 尺寸上)
    small = post(small)
    out_dir = os.path.join(OUT_BASE, theme)
    os.makedirs(out_dir, exist_ok=True)
    small.save(os.path.join(out_dir, name + ".png"))


def render_shadow(theme, post):
    """柔和地面阴影:径向渐变椭圆。像素风做硬边、霓虹做发光,其余靠主题后处理或保持。"""
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
                a = int(238 * (1 - r) ** 3.2)
                px[x, y] = (0, 0, 0, a)
    if theme == "pixel":
        # 硬边像素阴影:降采样
        img = img.resize((64, 24), Image.NEAREST).resize((W, H), Image.NEAREST)
    elif theme == "neon":
        # 发光阴影:青色外发光
        a = img.split()[3]
        glow = _compose(Image.new("RGBA", img.size, (0, 200, 255, 200)),
                        a.filter(ImageFilter.GaussianBlur(4)))
        img = Image.alpha_composite(glow, img)
    out_dir = os.path.join(OUT_BASE, theme)
    os.makedirs(out_dir, exist_ok=True)
    img.save(os.path.join(out_dir, "shadow.png"))


def render_branch(theme, post, pal):
    """一根带叶小树枝:鸟停在高处时脚下停靠用。按主题上色 + 后处理。"""
    W, H = 256 * SS, 96 * SS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = SS
    cy = H * 0.52
    def C(n): return pal[n]
    # 枝干
    d.line([(W * 0.08, cy + 2 * s), (W * 0.92, cy - 2 * s)],
           fill=C("BRANCH"), width=int(11 * s))
    d.line([(W * 0.10, cy + 1 * s), (W * 0.90, cy - 1 * s)],
           fill=C("BRANCH_L"), width=int(6 * s))
    # 小分枝节
    for fx in (0.30, 0.62):
        d.ellipse([W * fx - 4 * s, cy - 5 * s, W * fx + 4 * s, cy + 5 * s],
                  fill=C("BRANCH_D"))
    # 叶子
    for lx, ang, sc in [(0.30, 0.7, 1.0), (0.50, -0.6, 0.9), (0.66, 0.5, 1.0), (0.80, -0.5, 0.8)]:
        cx = W * lx
        l = 30 * s * sc
        ex = cx + math.cos(ang) * l
        ey = cy - math.sin(ang) * l
        d.ellipse([min(cx, ex) - 9 * s, min(cy, ey) - 11 * s,
                   max(cx, ex) + 9 * s, max(cy, ey) + 11 * s], fill=C("LEAF"))
        d.ellipse([min(cx, ex) - 3 * s, min(cy, ey) - 4 * s,
                   max(cx, ex) + 3 * s, max(cy, ey) + 4 * s], fill=C("LEAF_D"))
    small = img.resize((256, 96), Image.LANCZOS)
    if theme == "pixel":
        small = small.resize((64, 24), Image.NEAREST).resize((256, 96), Image.NEAREST)
    else:
        small = post(small)
    out_dir = os.path.join(OUT_BASE, theme)
    os.makedirs(out_dir, exist_ok=True)
    small.save(os.path.join(out_dir, "branch.png"))


def montage_for(theme, names, out="contact.png"):
    """把若干帧拼成一张检查图(按主题)。"""
    cols = 4
    rows = math.ceil(len(names)/cols)
    cell = SIZE
    sheet = Image.new("RGBA", (cols*cell, rows*cell), (24, 28, 34, 255))
    d_dir = os.path.join(OUT_BASE, theme)
    for i, (label, fn) in enumerate(names):
        r, c = divmod(i, cols)
        p = os.path.join(d_dir, fn + ".png")
        if os.path.exists(p):
            im = Image.open(p).convert("RGBA")
            sheet.alpha_composite(im, (c*cell, r*cell))
    sheet.save(os.path.join(d_dir, out))


# 每个主题渲染的所有帧定义(几何参数,所有主题共用)
def render_all_frames(theme, pal, post):
    print(f"=== 主题 {theme}({THEME_NAMES[theme]})===")
    # 基础
    render("idle_0", theme, pal, post, wing="folded", body_dy=0)
    render("idle_1", theme, pal, post, wing="folded", body_dy=-3)
    render("idle_blink", theme, pal, post, wing="folded", eye_closed=True)
    render("walk_0", theme, pal, post, wing="folded", leg_phase=0.0)
    render("walk_1", theme, pal, post, wing="folded", leg_phase=0.25)
    render("walk_2", theme, pal, post, wing="folded", leg_phase=0.5)
    render("walk_3", theme, pal, post, wing="folded", leg_phase=0.75)
    render("fly_0", theme, pal, post, wing="folded")
    render("fly_1", theme, pal, post, wing="midup")
    render("fly_2", theme, pal, post, wing="up")
    render("fly_3", theme, pal, post, wing="middown")
    render("happy_0", theme, pal, post, wing="folded", mouth_open=True, heart_eye=True, blush=True, body_dy=-2)
    render("happy_1", theme, pal, post, wing="midup",  mouth_open=True, heart_eye=True, blush=True, body_dy=-8)
    render("sleep_0", theme, pal, post, wing="folded", eye_closed=True, body_dy=0)
    render("sleep_1", theme, pal, post, wing="folded", eye_closed=True, body_dy=-2)

    # 俯冲捕鱼
    render("dive_0", theme, pal, post, wing="folded", hide_legs=True, rotate=90)
    render("fly_fish_0", theme, pal, post, wing="folded", fish_in_beak=True)
    render("fly_fish_1", theme, pal, post, wing="midup",  fish_in_beak=True)
    render("fly_fish_2", theme, pal, post, wing="up",     fish_in_beak=True)
    render("fly_fish_3", theme, pal, post, wing="middown", fish_in_beak=True)
    render("eat_0", theme, pal, post, wing="folded", fish_in_beak=True, head_up=True, mouth_open=True)
    render("eat_1", theme, pal, post, wing="folded", fish_bite=0.55, head_up=True, mouth_open=True)
    render("eat_2", theme, pal, post, wing="folded", fish_bite=1.0, head_up=True,
           head_raise_amt=10, eye_closed=True)

    # 鸣唱
    render("sing_0", theme, pal, post, wing="folded", head_up=True, mouth_open=True)
    render("sing_1", theme, pal, post, wing="midup",  head_up=True, mouth_open=True)

    # 栖枝守候
    render("watch_0", theme, pal, post, wing="folded", alert=True)
    render("watch_1", theme, pal, post, wing="folded", alert=True, head_tilt=-4)

    # 日光浴
    render("sun_0", theme, pal, post, wing="spread", fluff=True, eye_closed=True)
    render("sun_1", theme, pal, post, wing="spread", fluff=True)

    # 啄屏幕
    render("peck_0", theme, pal, post, wing="folded", look_down=True, head_jab=1.0, body_dy=-2)
    render("peck_1", theme, pal, post, wing="folded")

    # 蛋壳 + 死掉
    render("egg_0", theme, pal, post, egg_stage=0)
    render("egg_1", theme, pal, post, egg_stage=1)
    render("egg_2", theme, pal, post, egg_stage=2)
    render("dead", theme, pal, post, wing="up", x_eye=True, tongue=True, mouth_open=True, hide_legs=True, rotate=180)

    # 阴影 + 树枝
    render_shadow(theme, post)
    render_branch(theme, post, pal)

    # 拉屎
    render("poop_0", theme, pal, post, wing="folded", butt_up=True, tail_wag=-5, sweat=True, body_dy=4)
    render("poop_1", theme, pal, post, wing="folded", butt_up=True, tail_wag=5, sweat=True, body_dy=4)

    # 序列(所有主题一致)
    seq = {
        "fps": {
            "idle": 4, "walk": 8, "fly": 10, "happy": 6, "sleep": 2,
            "dive": 8, "fly_fish": 10, "eat": 4, "sing": 6, "watch": 3,
            "sun": 3, "hover": 10, "egg": 4, "dead": 1, "poop": 6, "peck": 8
        },
        "sequences": {
            "idle":     ["idle_0", "idle_1", "idle_0", "idle_blink"],
            "walk":     ["walk_0", "walk_1", "walk_2", "walk_3"],
            "fly":      ["fly_1", "fly_2", "fly_3", "fly_2"],
            "hover":    ["fly_1", "fly_2", "fly_1", "fly_3"],
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
    with open(os.path.join(OUT_BASE, theme, "sprites.json"), "w") as f:
        json.dump(seq, f, indent=2)
    print(f"  wrote {theme}/sprites.json")

    # 检查图
    montage_for(theme, [
        ("idle", "idle_0"), ("walk", "walk_0"), ("fly", "fly_2"), ("happy", "happy_0"),
        ("dive", "dive_0"), ("fly_fish", "fly_fish_0"), ("eat0", "eat_0"), ("eat2", "eat_2"),
        ("sing", "sing_0"), ("watch", "watch_0"), ("sun", "sun_0"), ("peck", "peck_0"),
        ("egg0", "egg_0"), ("egg1", "egg_1"), ("egg2", "egg_2"), ("dead", "dead"),
        ("poop", "poop_0"), ("shadow", "shadow"), ("branch", "branch"),
    ])


def main():
    os.makedirs(OUT_BASE, exist_ok=True)
    for theme in THEME_NAMES:
        pal = palette_for(theme)
        post = POSTPROCESSORS[theme]
        render_all_frames(theme, pal, post)
    print("全部主题渲染完成。")


def gen_peep():
    """生成翠鸟叫声 wav(不随主题变):模仿普通翠鸟(Alcedo atthis)真实鸣声。

    声学特征(权威声谱分析 + 真实录音 FFT 验证):
    - 类型:尖锐"犬吠哨"声(downslurred 下扫)
    - 频率范围:4900–6600 Hz(权威资料 fssbirding);真实录音单声 5900→6300 起步
    - 频率轮廓:**下扫**——高频起,线性/指数降到低频(不是升-降,也不是稳定!)
      真实测量:单声 6300→5900(轻扫 -400Hz);连发声 5000→3400(大扫 -1600Hz)
    - 单声时长:80–160ms;连发时每声 70-120ms,间隔 50-100ms
    - 音色:基频为主 + 弱谐波 + 微气流噪声;有轻微颤动

    4 种变体:0 高频单声下扫 / 1 双连发下扫 / 2 长下扫 / 3 急促三连下扫
    输出到 ../Resources/peep_*.wav。"""
    import random as _rnd
    sr = 44100

    def write_wav(path, samples):
        with wave.open(path, "w") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(sr)
            w.writeframes(struct.pack("<" + "h" * len(samples), *samples))

    def synth_note(dur, f_start, f_end, amp=0.4, vibrato=120, noise=0.05,
                   harmonics=(1.0, 0.18, 0.06), seed=42):
        """合成单个翠鸟下扫叫声。
        f_start→f_end:从高频线性降到低频(downslurred)。
        vibrato:叠加的颤动幅度(Hz);noise:气流噪声比例;harmonics:基频+谐波。"""
        n = int(sr * dur)
        out = [0.0] * n
        rnd = _rnd.Random(seed)
        # 颤动序列(阻尼随机游走)
        vib_seq = []
        v = 0.0
        for i in range(n):
            v += rnd.uniform(-1, 1) * vibrato * 0.15
            v *= 0.85
            v = max(-vibrato, min(vibrato, v))
            vib_seq.append(v)
        for hi, hw in enumerate(harmonics, start=1):
            phase = 0.0
            for i in range(n):
                p = i / n
                # 下扫轮廓:线性从 f_start 降到 f_end(翠鸟特征)
                f = f_start + (f_end - f_start) * p
                f += vib_seq[i]        # 叠颤动
                f *= hi                # 谐波倍频
                phase += 2 * math.pi * f / sr
                # 包络:快速起 + 平顶 + 快速落
                if p < 0.06:
                    env = p / 0.06
                elif p > 0.88:
                    env = max(0, (1 - p) / 0.12)
                else:
                    env = 1.0
                out[i] += hw * env * math.sin(phase)
        # 气流噪声
        if noise > 0:
            prev = 0.0
            for i in range(n):
                p = i / n
                env = 1.0 if 0.06 <= p <= 0.88 else (p / 0.06 if p < 0.06 else max(0, (1 - p) / 0.12))
                white = rnd.uniform(-1, 1)
                out[i] += noise * env * (white - prev)
                prev = white
        return [int(max(-1, min(1, v * amp)) * 32767) for v in out]

    def silence(dur):
        return [0] * int(sr * dur)

    def concat(*chunks):
        r = []
        for c in chunks:
            r.extend(c)
        return r

    base = os.path.join(RES)

    # 0 高频单声下扫:6300→5900Hz(真实叫声2,经典 pee-eep)
    write_wav(os.path.join(base, "peep_0.wav"),
              synth_note(0.14, f_start=6300, f_end=5900, amp=0.42, vibrato=150, noise=0.05, seed=7))

    # 1 双连发下扫:两声,第二声起点更高(真实连发段)
    a = synth_note(0.10, f_start=5000, f_end=3400, amp=0.40, vibrato=140, noise=0.05, seed=11)
    b = synth_note(0.11, f_start=5300, f_end=3500, amp=0.40, vibrato=150, noise=0.05, seed=13)
    write_wav(os.path.join(base, "peep_1.wav"), concat(a, silence(0.08), b))

    # 2 长下扫:5000→3000Hz(大幅下滑,警告/兴奋)
    write_wav(os.path.join(base, "peep_2.wav"),
              synth_note(0.18, f_start=5000, f_end=3000, amp=0.44, vibrato=100, noise=0.06, seed=23))

    # 3 急促三连下扫(受惊/激动,每声短)
    x = synth_note(0.07, f_start=4900, f_end=3000, amp=0.38, vibrato=120, noise=0.06, seed=31)
    y = synth_note(0.07, f_start=5100, f_end=3200, amp=0.38, vibrato=120, noise=0.06, seed=37)
    z = synth_note(0.08, f_start=5300, f_end=3400, amp=0.38, vibrato=130, noise=0.06, seed=41)
    write_wav(os.path.join(base, "peep_3.wav"), concat(x, silence(0.06), y, silence(0.06), z))

    print("  wrote peep_0..3.wav (翠鸟下扫叫声, 基于真实声谱)")



if __name__ == "__main__":
    main()
    gen_peep()
