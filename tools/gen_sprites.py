#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
翠鸟(翡)桌面宠物 sprite 生成器
扁平卡通风,侧视朝左,4x 超采样后缩到 256x256 抗锯齿,透明背景。
输出到 ../Resources/Sprites/*.png 以及 sprites.json。
"""
import math, os, json, wave, struct
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Sprites")
SS = 4            # 超采样倍数
SIZE = 256        # 输出尺寸

# ---- 配色 ----
TEAL   = (22, 166, 179, 255)   # 背/头/翅膀
TEAL_D = (15, 120, 132, 255)   # 翅膀暗部
ORANGE = (240, 145, 59, 255)   # 胸/腹
ORANGE_D = (214, 110, 36, 255)
WHITE  = (253, 246, 230, 255)  # 颊/喉斑
BEAK   = (26, 26, 26, 255)     # 喙
EYE    = (24, 28, 32, 255)     # 眼
LEG    = (224, 96, 48, 255)    # 爪
BLUSH  = (244, 122, 142, 180)  # 害羞红晕
HEART  = (235, 84, 110, 255)
ZCOLOR = (150, 196, 206, 255)
SHADOW = (0, 0, 0, 55)


def heart(d, cx, cy, r, color):
    pts = []
    for t in (0.0, 0.2, 0.4, 0.6, 0.8):
        pass
    # 用参数方程画心形
    poly = []
    for deg in range(0, 360, 8):
        t = math.radians(deg)
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t))
        poly.append((cx + x * r / 16.0, cy + y * r / 16.0))
    d.polygon(poly, fill=color)


def draw_kingfisher(W, H, *, wing="folded", leg_phase=0.0, eye_closed=False,
                   body_dy=0, blush=False, heart_eye=False, zzz=False):
    """画一只翠鸟,返回 RGBA Image。wing: folded / midup / up / middown"""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = W / 256.0  # 缩放因子

    def E(cx, cy, rx, ry, fill):
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill)

    cx, cy = W * 0.54, H * 0.58 + body_dy * s

    # 脚下软阴影
    d.ellipse([cx - 60*s, H*0.90, cx + 60*s, H*0.90 + 14*s], fill=SHADOW)

    # ---- 身体(橙腹)----
    E(cx, cy + 6*s, 62*s, 52*s, ORANGE)
    # 腹部高光
    E(cx - 10*s, cy + 16*s, 30*s, 26*s, (255, 196, 120, 255))

    # ---- 背/披风(青)----
    d.pieslice([cx-72*s, cy-44*s, cx+74*s, cy+34*s], 180, 360, fill=TEAL)
    # 背部羽毛暗纹
    d.pieslice([cx-10*s, cy-44*s, cx+74*s, cy+10*s], 180, 360, fill=TEAL_D)

    # ---- 尾巴(青,右后)----
    tail = [(cx+58*s, cy-2*s), (cx+96*s, cy-22*s),
            (cx+98*s, cy-4*s), (cx+64*s, cy+14*s)]
    d.polygon(tail, fill=TEAL)
    d.polygon([(cx+74*s, cy-6*s), (cx+92*s, cy-18*s),
               (cx+84*s, cy-4*s)], fill=TEAL_D)

    # ---- 翅膀 ----
    wcx, wcy = cx + 4*s, cy + 2*s
    if wing == "folded":
        # 收拢的翅膀:斜椭圆
        d.ellipse([wcx-40*s, wcy-22*s, wcx+40*s, wcy+22*s], fill=TEAL_D)
        d.ellipse([wcx-30*s, wcy-14*s, wcx+34*s, wcy+16*s], fill=TEAL)
        # 飞羽分隔线
        d.line([(wcx-20*s, wcy+10*s), (wcx+30*s, wcy-6*s)], fill=TEAL_D, width=max(2, int(3*s)))
    else:
        # 扑翅:上展的弧形
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
    hx, hy = cx - 46*s, cy - 30*s
    E(hx, hy, 38*s, 36*s, TEAL)
    # 头顶小撮冠羽
    d.polygon([(hx-8*s, hy-32*s), (hx-2*s, hy-46*s), (hx+6*s, hy-30*s)], fill=TEAL_D)

    # ---- 白颊/耳斑 ----
    E(hx + 10*s, hy + 6*s, 16*s, 13*s, WHITE)
    # 喉部白斑
    E(hx - 4*s, hy + 26*s, 16*s, 10*s, WHITE)

    # ---- 喙(黑色长锥,朝左)----
    by = hy + 6*s
    d.polygon([(hx-30*s, by-5*s), (hx-72*s, by+2*s),
               (hx-72*s, by+8*s), (hx-30*s, by+12*s)], fill=BEAK)
    # 喙基高光
    d.polygon([(hx-34*s, by-3*s), (hx-50*s, by), (hx-40*s, by+3*s)], fill=(70,70,70,255))

    # ---- 眼睛 ----
    ex, ey = hx - 6*s, hy - 4*s
    if heart_eye:
        heart(d, ex, ey, 13*s, HEART)
    elif eye_closed:
        # 闭眼:一道弯线
        d.arc([ex-10*s, ey-5*s, ex+10*s, ey+9*s], 200, 340, fill=EYE, width=max(2, int(4*s)))
    else:
        E(ex, ey, 8*s, 8*s, WHITE)
        E(ex + 1*s, ey + 1*s, 6*s, 6*s, EYE)
        d.ellipse([ex-1*s, ey-4*s, ex+4*s, ey+1*s], fill=WHITE)

    # ---- 爪(橙)----
    def leg(x_top, x_bot, lift=False):
        y_top = cy + 40*s
        y_bot = (cy + 58*s) if not lift else (cy + 46*s)
        d.line([(x_top, y_top), (x_bot, y_bot)], fill=LEG, width=max(2, int(4*s)))
        # 脚趾
        for dx in (-6*s, 0, 6*s):
            d.line([(x_bot, y_bot), (x_bot+dx, y_bot+7*s)], fill=LEG, width=max(2, int(3*s)))
    # walk: leg_phase 0..1 控制左右脚前后
    left_x  = cx - 16*s + math.cos(leg_phase*math.pi) * 8*s
    right_x = cx + 16*s - math.cos(leg_phase*math.pi) * 8*s
    left_lift  = math.sin(leg_phase*math.pi*2) > 0.3
    right_lift = math.sin(leg_phase*math.pi*2 + math.pi) > 0.3
    if wing in ("up", "midup", "middown"):
        # 飞行:爪收起贴腹
        for x_top in (cx-14*s, cx+12*s):
            d.line([(x_top, cy+34*s), (x_top+2*s, cy+44*s)], fill=LEG, width=max(2,int(4*s)))
    else:
        leg(left_x, left_x, lift=left_lift)
        leg(right_x, right_x, lift=right_lift)

    # ---- 红晕 ----
    if blush:
        E(hx + 14*s, hy + 14*s, 8*s, 6*s, BLUSH)

    # ---- Zzz ----
    if zzz:
        for i, (tx, ty, ts) in enumerate([(hx+40*s, hy-30*s, 16),
                                           (hx+54*s, hy-46*s, 22),
                                           (hx+70*s, hy-66*s, 30)]):
            d.text((tx-6*s, ty-12*s), "Z", fill=ZCOLOR)

    return img


def render(name, **kw):
    big = draw_kingfisher(SIZE*SS, SIZE*SS, **kw)
    small = big.resize((SIZE, SIZE), Image.LANCZOS)
    small.save(os.path.join(OUT, name + ".png"))
    print("  wrote", name + ".png")


def main():
    os.makedirs(OUT, exist_ok=True)
    # idle:轻微上下浮动
    render("idle_0", wing="folded", body_dy=0)
    render("idle_1", wing="folded", body_dy=-3)
    render("idle_blink", wing="folded", eye_closed=True)
    # walk: 4 帧,腿前后交替
    render("walk_0", wing="folded", leg_phase=0.0)
    render("walk_1", wing="folded", leg_phase=0.25)
    render("walk_2", wing="folded", leg_phase=0.5)
    render("walk_3", wing="folded", leg_phase=0.75)
    # fly: 4 帧扑翅
    render("fly_0", wing="folded")
    render("fly_1", wing="midup")
    render("fly_2", wing="up")
    render("fly_3", wing="middown")
    # happy(被点):心眼+红晕+小跳
    render("happy_0", wing="folded", heart_eye=True, blush=True, body_dy=-2)
    render("happy_1", wing="midup",  heart_eye=True, blush=True, body_dy=-8)
    # sleep:闭眼+Zzz+呼吸
    render("sleep_0", wing="folded", eye_closed=True, zzz=True, body_dy=0)
    render("sleep_1", wing="folded", eye_closed=True, zzz=True, body_dy=-2)

    seq = {
        "fps": {"idle": 4, "walk": 8, "fly": 10, "happy": 6, "sleep": 2},
        "sequences": {
            "idle":  ["idle_0", "idle_1", "idle_0", "idle_blink"],
            "walk":  ["walk_0", "walk_1", "walk_2", "walk_3"],
            "fly":   ["fly_0", "fly_1", "fly_2", "fly_3"],
            "happy": ["happy_0", "happy_1", "happy_0", "happy_1"],
            "sleep": ["sleep_0", "sleep_1"]
        }
    }
    with open(os.path.join(OUT, "sprites.json"), "w") as f:
        json.dump(seq, f, indent=2)
    print("  wrote sprites.json")


def gen_peep():
    """生成一个短促的‘啾’声(频率上扫+淡入淡出),16-bit PCM wav。"""
    out = os.path.join(os.path.dirname(__file__), "..", "Resources", "peep.wav")
    sr = 22050
    dur = 0.16
    n = int(sr * dur)
    frames = []
    for i in range(n):
        t = i / sr
        # 频率从 1700Hz 扫到 2600Hz
        f = 1700 + (2600 - 1700) * (i / n)
        # 加一点颤音
        f += 40 * math.sin(2 * math.pi * 18 * t)
        env = math.sin(math.pi * i / n)            # 正弦包络(淡入淡出)
        amp = 0.35 * env
        # 累积相位
        if i == 0:
            phase = 0.0
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
