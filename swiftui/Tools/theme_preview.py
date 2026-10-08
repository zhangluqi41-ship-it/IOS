#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
theme_preview.py —— 配色改动效果图（纯本地渲染，不用装 App 就能看）。

左列 = 旧配色（安卓端沿用过来的墨绿 #00695C），右列 = 新配色（App Store 蓝 #007AFF）。
用包内同一套 Noto Sans SC 字体，所以文字观感与真机一致。
"""

import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIR = os.path.normpath(os.path.join(HERE, "..", "Resources"))
OUT_DIR = os.path.join(HERE, "theme_preview")
# 改造前的绿色图标备份（随脚本一起走）
ICON_BEFORE = os.path.join(HERE, "AppIcon-green-backup.png")
F_BOLD = os.path.join(FONT_DIR, "NotoSansSC-Bold.ttf")
F_REG = os.path.join(FONT_DIR, "NotoSansSC-Regular.ttf")

S = 2  # 超采样倍数，最后缩回去做抗锯齿


def font(path, px):
    return ImageFont.truetype(path, px * S)


OLD = dict(
    name="旧 · 墨绿 #00695C",
    brand=(0x00, 0x69, 0x5C),
    brand_light=(0x4D, 0xB6, 0xAC),
    chips=[("通用效期", (0x18, 0x5F, 0xA5), (0xE6, 0xF1, 0xFB)),
           ("康普茶", (0x0F, 0x6E, 0x56), (0xE1, 0xF5, 0xEE)),
           ("奶制品", (0x85, 0x4F, 0x0B), (0xFA, 0xEE, 0xDA))],
)
NEW = dict(
    name="新 · App Store 蓝 #007AFF",
    brand=(0x00, 0x7A, 0xFF),
    brand_light=(0x5A, 0xAA, 0xFF),
    chips=[("通用效期", (0x0A, 0x7A, 0xFF), (0xE6, 0xF1, 0xFF)),
           ("康普茶", (0x5E, 0x5C, 0xE6), (0xED, 0xEC, 0xFF)),
           ("奶制品", (0x85, 0x4F, 0x0B), (0xFA, 0xEE, 0xDA))],
)

BG = (242, 242, 247)
CARD = (255, 255, 255)
TEXT = (28, 28, 30)
TEXT2 = (120, 120, 128)


def rounded(dr, box, r, fill=None, outline=None, width=1):
    dr.rounded_rectangle([box[0] * S, box[1] * S, box[2] * S, box[3] * S],
                         radius=r * S, fill=fill, outline=outline, width=width * S)


def text(dr, xy, s, f, fill, anchor="la"):
    dr.text((xy[0] * S, xy[1] * S), s, font=f, fill=fill, anchor=anchor)


def icon_printer(dr, cx, cy, size, color, w=2):
    """用几何图形近似一个「打印机」图标。"""
    hw, hh = size / 2, size / 2
    rounded(dr, (cx - hw, cy - hh * 0.35, cx + hw, cy + hh * 0.45), 3,
            fill=None, outline=color, width=w)
    dr.rectangle([(cx - hw * 0.55) * S, (cy - hh) * S,
                  (cx + hw * 0.55) * S, (cy - hh * 0.35) * S], fill=color)
    dr.rectangle([(cx - hw * 0.55) * S, (cy + hh * 0.15) * S,
                  (cx + hw * 0.55) * S, (cy + hh * 0.95) * S], fill=color)


def icon_grid(dr, cx, cy, size, color, w=2):
    s = size / 2
    for dx in (-1, 1):
        for dy in (-1, 1):
            rounded(dr, (cx + dx * s * 0.5 - s * 0.42, cy + dy * s * 0.5 - s * 0.42,
                         cx + dx * s * 0.5 + s * 0.42, cy + dy * s * 0.5 + s * 0.42),
                    2, outline=color, width=w)


def icon_qr(dr, cx, cy, size, color, w=2):
    s = size / 2
    rounded(dr, (cx - s, cy - s, cx - s * 0.25, cy - s * 0.25), 2, outline=color, width=w)
    rounded(dr, (cx + s * 0.25, cy - s, cx + s, cy - s * 0.25), 2, outline=color, width=w)
    rounded(dr, (cx - s, cy + s * 0.25, cx - s * 0.25, cy + s), 2, outline=color, width=w)
    rounded(dr, (cx + s * 0.25, cy + s * 0.25, cx + s, cy + s), 2, outline=color, width=w)


def icon_cal(dr, cx, cy, size, color, w=2):
    s = size / 2
    rounded(dr, (cx - s, cy - s * 0.8, cx + s, cy + s), 3, outline=color, width=w)
    dr.rectangle([(cx - s) * S, (cy - s * 0.8) * S, (cx + s) * S, (cy - s * 0.35) * S],
                 fill=color)


def icon_clock(dr, cx, cy, size, color, w=2):
    s = size / 2
    dr.ellipse([(cx - s) * S, (cy - s) * S, (cx + s) * S, (cy + s) * S],
               outline=color, width=w * S)
    dr.line([cx * S, cy * S, cx * S, (cy - s * 0.55) * S], fill=color, width=w * S)
    dr.line([cx * S, cy * S, (cx + s * 0.45) * S, cy * S], fill=color, width=w * S)


def draw_tabbar(dr, x0, y0, w, spec):
    """底部 Tab 栏（选中项用品牌色）。"""
    h = 66
    rounded(dr, (x0, y0, x0 + w, y0 + h), 0, fill=(249, 249, 249))
    dr.line([x0 * S, y0 * S, (x0 + w) * S, y0 * S], fill=(210, 210, 215), width=S)
    tabs = [("效期打印", icon_grid, True), ("扫码", icon_qr, False),
            ("效期管理", icon_cal, False), ("打印机", icon_printer, False)]
    step = w / len(tabs)
    f = font(F_REG, 9)
    for i, (label, drawer, selected) in enumerate(tabs):
        cx = x0 + step * (i + 0.5)
        color = spec["brand"] if selected else (160, 160, 168)
        drawer(dr, cx, y0 + 20, 18, color)
        text(dr, (cx, y0 + 36), label, f, color, anchor="ma")
        if label == "效期管理":
            # 角标也用品牌色
            dr.ellipse([(cx + 9) * S, (y0 + 8) * S, (cx + 22) * S, (y0 + 21) * S],
                       fill=(255, 59, 48))
            text(dr, (cx + 15.5, y0 + 10), "2", font(F_REG, 9), (255, 255, 255),
                 anchor="ma")


def draw_column(img, dr, x0, width, spec):
    y = 96

    # ---- 标题 ----
    text(dr, (x0, 16), spec["name"], font(F_BOLD, 20), TEXT)
    text(dr, (x0, 46), "Tab 栏 / 按钮 / 图标高亮 / 卡片标识色 / App 图标",
         font(F_REG, 11), TEXT2)

    # ---- App 图标 ----
    text(dr, (x0, y), "App 图标", font(F_BOLD, 13), TEXT)
    y += 24
    # 贴**真实图标**：左列用改色前的备份，右列用仓库里改色后的那张
    icon_path = (ICON_BEFORE if spec is OLD
                 else os.path.normpath(os.path.join(HERE, "..")) + "/"
                      r"Sources/ExpiryApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    try:
        src = Image.open(icon_path).convert("RGB").resize((84 * S, 84 * S), Image.LANCZOS)
        mask = Image.new("L", (84 * S, 84 * S), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, 84 * S - 1, 84 * S - 1],
                                               radius=19 * S, fill=255)
        img.paste(src, (int(x0 * S), int(y * S)), mask)
    except Exception as e:   # 备份不在就退回纯色块
        print("[!] 图标读取失败（%s），改用纯色块" % e)
        rounded(dr, (x0, y, x0 + 84, y + 84), 19, fill=spec["brand"])
    y += 100

    # ---- Tab 栏 ----
    text(dr, (x0, y), "底部 Tab 栏（选中色）", font(F_BOLD, 13), TEXT)
    y += 24
    draw_tabbar(dr, x0, y, width, spec)
    y += 82

    # ---- 按钮 ----
    text(dr, (x0, y), "按钮 / 高亮", font(F_BOLD, 13), TEXT)
    y += 24
    rounded(dr, (x0, y, x0 + width * 0.48, y + 44), 22, fill=spec["brand"])
    text(dr, (x0 + width * 0.24, y + 12), "预览标签", font(F_BOLD, 13),
         (255, 255, 255), anchor="ma")

    rounded(dr, (x0 + width * 0.54, y, x0 + width, y + 44), 22,
            fill=(118, 118, 128, 30), outline=(200, 200, 205), width=1)
    y2 = y
    # 次按钮：图标 + 文字用品牌色
    icon_printer(dr, x0 + width * 0.60, y2 + 22, 17, spec["brand"])
    text(dr, (x0 + width * 0.66, y2 + 14), "打印", font(F_BOLD, 13), spec["brand"])
    y += 62

    # ---- 快捷档位 chip ----
    text(dr, (x0, y), "快捷档位 chip（选中态）", font(F_BOLD, 13), TEXT)
    y += 22
    cx = x0
    for label in ("+7 天", "+15 天", "+1 个月"):
        w = 74
        rounded(dr, (cx, y, cx + w, y + 32), 16, fill=spec["brand"])
        text(dr, (cx + w / 2, y + 8), label, font(F_REG, 12), (255, 255, 255), anchor="ma")
        cx += w + 10
    y += 52

    # ---- 模板卡片 ----
    text(dr, (x0, y), "模板卡片标识色", font(F_BOLD, 13), TEXT)
    y += 22
    cw = (width - 2 * 10) / 3
    for i, (name, tint, fill) in enumerate(spec["chips"]):
        bx = x0 + i * (cw + 10)
        rounded(dr, (bx, y, bx + cw, y + 78), 13, fill=CARD)
        rounded(dr, (bx + cw / 2 - 17, y + 10, bx + cw / 2 + 17, y + 44), 8, fill=fill)
        icon_clock(dr, bx + cw / 2, y + 27, 16, tint)
        text(dr, (bx + cw / 2, y + 50), name, font(F_BOLD, 12), TEXT, anchor="ma")
    y += 96

    # ---- 扫码取景框 ----
    text(dr, (x0, y), "扫码取景框（深底上的强调色）", font(F_BOLD, 13), TEXT)
    y += 22
    boxw = min(width, 190)
    rounded(dr, (x0, y, x0 + boxw, y + 110), 13, fill=(18, 18, 20))
    cx0, cy0 = x0 + boxw / 2, y + 55
    half = 44
    ln = 16
    for (sx, sy, ex, ey) in (
        (-half, -half + ln, -half, -half), (-half, -half, -half + ln, -half),
        (half - ln, -half, half, -half), (half, -half, half, -half + ln),
        (-half, half - ln, -half, half), (-half, half, -half + ln, half),
        (half - ln, half, half, half), (half, half - ln, half, half),
    ):
        dr.line([(cx0 + sx) * S, (cy0 + sy) * S, (cx0 + ex) * S, (cy0 + ey) * S],
                fill=spec["brand_light"], width=4 * S)
    dr.line([(cx0 - half + 6) * S, cy0 * S, (cx0 + half - 6) * S, cy0 * S],
            fill=spec["brand_light"], width=2 * S)
    text(dr, (cx0, y + 92), "将二维码放入框内", font(F_REG, 10), (235, 235, 240), anchor="ma")
    return y + 122


def hexs(c):
    return "#%02X%02X%02X" % c


def main():
    W, H = 880, 840
    img = Image.new("RGB", (W * S, H * S), BG)
    dr = ImageDraw.Draw(img)

    colw = (W - 24 * 2 - 20) / 2
    x_left = 24
    x_right = 24 + colw + 20

    draw_column(img, dr, x_left, colw, OLD)
    draw_column(img, dr, x_right, colw, NEW)

    # 中缝
    dr.line([(x_left + colw + 10) * S, 20 * S, (x_left + colw + 10) * S, (H - 20) * S],
            fill=(210, 210, 215), width=S)

    # 底部结论条
    text(dr, (24, H - 62),
         "品牌色：#00695C（墨绿，色相 173°）  →  #007AFF（App Store 蓝，色相 211°）",
         font(F_REG, 12), TEXT)
    text(dr, (24, H - 42),
         "康普茶标识色：#0F6E56（品牌绿）→ #5E5CE6（靛蓝）    奶制品保留琥珀色（本来就不是绿，三卡需区分）",
         font(F_REG, 12), TEXT2)
    text(dr, (24, H - 22),
         "App 图标底色同步改为 #007AFF（白字形不变；原图备份见 Tools/AppIcon-green-backup.png）",
         font(F_REG, 12), TEXT2)

    out = img.resize((W, H), Image.LANCZOS)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, "theme_before_after.png")
    out.save(path)
    print("[+] 已生成", path, out.size)

    # 顺带出一张「新旧色板」便于快速核对
    sw = Image.new("RGB", (760, 210), (255, 255, 255))
    d2 = ImageDraw.Draw(sw)
    items = [
        ("品牌色", OLD["brand"], NEW["brand"]),
        ("品牌亮色", OLD["brand_light"], NEW["brand_light"]),
        ("通用效期 tint", OLD["chips"][0][1], NEW["chips"][0][1]),
        ("康普茶 tint", OLD["chips"][1][1], NEW["chips"][1][1]),
        ("奶制品 tint", OLD["chips"][2][1], NEW["chips"][2][1]),
    ]
    f1 = ImageFont.truetype(F_BOLD, 13)
    f2 = ImageFont.truetype(F_REG, 12)
    d2.text((16, 12), "配色对照", font=f1, fill=TEXT)
    d2.text((16, 34), "（每行：左 = 旧，右 = 新）", font=f2, fill=TEXT2)
    yy = 60
    for name, o, n in items:
        d2.text((16, yy + 8), name, font=f2, fill=TEXT)
        d2.rounded_rectangle([150, yy, 300, yy + 30], radius=6, fill=o)
        d2.text((310, yy + 8), hexs(o), font=f2, fill=TEXT2)
        d2.rounded_rectangle([420, yy, 570, yy + 30], radius=6, fill=n)
        d2.text((580, yy + 8), hexs(n), font=f2, fill=TEXT2)
        yy += 30 + 6
    p2 = os.path.join(OUT_DIR, "theme_swatches.png")
    sw.save(p2)
    print("[+] 已生成", p2, sw.size)


if __name__ == "__main__":
    main()
