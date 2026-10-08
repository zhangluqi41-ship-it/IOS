#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
render_label_preview.py —— 在本机（Windows）出标签「效果图」。

为什么要单独写一个：
  真机渲染在 Swift 里（CoreGraphics + CoreText），本机没有 Xcode，
  跑不了。而每改一次版式就往云端构建、下载、装机、打印一遍才能看到效果，
  一轮二十多分钟 —— 调版式根本受不了。
  所以这里把 `LabelRenderer.paint` 的几何**逐句复刻**成 Python，
  用同一套 LabelSpec 数值 + 同一份 NotoSansSC 字体出图，
  改版式时先在本地看效果，定了再写回 Swift。

⚠️ 与 Swift 的一致性约定（改这里的时候必须同步改那边，反之亦然）：
  · 坐标一律用「顶向下 y」（单位 mm），和 Swift 里 `h - y` 反推出来的值一致
  · 文字位置统一按 **字形顶 = y**（Swift 是 baseline = h - y - ascender，等价）
  · 黑条内居中文字：baseline = cyTop + (ascender + |descender|)/2
  · 二维码：size 含 1 模块静默边，逐模块矢量画

用法:
  python render_label_preview.py           # 出 <脚本目录>/label_preview/*.png
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
# ★ 2026-10-08：脚本随工程走，路径改成「相对脚本自身」，换台电脑也能直接跑。
RES = os.path.normpath(os.path.join(HERE, "..", "Resources"))
FONT_REG = os.path.join(RES, "NotoSansSC-Regular.ttf")
FONT_BOLD = os.path.join(RES, "NotoSansSC-Bold.ttf")
OUTDIR = os.path.join(HERE, "label_preview")

PAGE_W, PAGE_H = 50.0, 30.0        # mm

# ------------------------------------------------------------------ 版式常量
# ★★ 下面两套数值必须与 swiftui/Sources/ExpiryApp/Models/LabelData.swift
#    里的 `enum LabelSpec` 保持一致。
OLD = dict(
    padV=1.0, padH=1.5, padHR=1.5, barWL=6.2, barWR=3.8, gapBar=0.45,
    titleSz=3.35, titleGapRight=0.6, makerGapRight=0.8,
    labSz=2.2, rowSz=2.3, rowStep=5.65, rowGap=2.9, makerSz=1.4,
    qrSize=12.8, qrGap=0.3, qrTop=7.5, firstRow=7.0, makerBottom=5.0,
    weekCnSz=2.40, weekDaySz=3.50, weekEnSz=2.25, rightSzRatio=0.55,
)

NEW = dict(
    # ① 黑条向外侧移：左右留白 1.5 → 0.7mm
    padV=1.0, padH=0.7, padHR=0.7, barWL=6.2, barWR=3.8, gapBar=0.45,
    # ② 标题放大 3.35 → 4.2（超宽仍会自动缩字号）
    titleSz=4.2, titleGapRight=0.6, makerGapRight=0.8,
    # ③ 三组时间信息同步放大（标签 2.2→2.5，值 2.3→2.7），行距随之撑开
    #    ★ 值字号受「必须给二维码留出宽度」硬约束：2.85 时文字宽 23.44mm，
    #      可用宽度只有 38.15mm，给 14mm 的码只剩 0.36mm 缝隙 → 定在 2.7
    #      （文字 23.01mm，码两侧各留 0.57mm）。
    labSz=2.5, rowSz=2.7, rowStep=6.7, rowGap=3.28,
    # ④ 制作人放大 1.4 → 1.8（超出可用宽度会自动缩，不会压到右黑条）
    #    ★ 字号放大后三行文字会一直排到 26.3mm 高，把「距底 5.0mm」的制作人
    #      挤成和第三行数值并排（看起来像第三行的一部分）。
    #      所以改成「先把制作人在底部留出一条独立页脚」再排三行：
    #      标题 1.0~5.9 → 三行 6.5~26.3 → 制作人 26.5~29.0。
    makerSz=1.8,
    # ⑤ 二维码放大 12.8 → 14.0（12.8mm 时只有 2.0 点/模块，是之前发糊的主因）
    qrSize=14.0, qrGap=0.3, qrTop=7.5, firstRow=6.5, makerBottom=3.7,
    weekCnSz=2.40, weekDaySz=3.50, weekEnSz=2.25, rightSzRatio=0.55,
)

QR_QUIET = 1                      # 静默边（模块数），与 Swift qrQuietModules 一致


# ------------------------------------------------------------------ 数据
def sample_generic():
    return dict(
        title="蓝莓果酱",
        rows=[("开封时间：", "2026/10/07 18:40"),
              ("原始保质期：", "2026/10/14 18:40"),
              ("最佳使用时间：", "2026/10/22 23:59")],
        weekday_cn="三", weekday_en="Wed", right_text="18:40",
        maker="制作人：张皓",
    )


def sample_kombucha():
    return dict(
        title="康普茶-茉莉绿茶",
        rows=[("制备时间：", "2026/10/07 18:40"),
              ("完成时间：", "2026/10/14 18:40"),
              ("最佳使用时间：", "2026/11/06 18:40")],
        weekday_cn="三", weekday_en="Wed", right_text="18:40",
        maker="制作人：张皓",
    )


def sample_dairy():
    return dict(
        title="燕麦奶",
        rows=[("开封时间：", "2026/10/07 18:40"),
              ("原始保质期：", "2026/11/21 23:59"),
              ("最佳使用时间：", "2026/10/12 18:40")],
        weekday_cn="三", weekday_en="Wed", right_text="18:40",
        maker="制作人：张皓",
    )


def qr_text_of(d):
    """二维码内容 = 名称 + **后两组**时间（第一组时间和制作人都已去掉）。

    ★ 必须与 `LabelData.qrText` 逐字一致（2026-10-07 用户要求收紧）。
    """
    s = d["title"]
    for lab, val in d["rows"][1:]:
        s += lab + val
    return s


# ------------------------------------------------------------------ 渲染
class Render:
    """把 mm 换算成 px 后逐条复刻 LabelRenderer.paint。"""

    def __init__(self, spec, px_per_mm):
        self.s = spec
        self.k = float(px_per_mm)
        self._font_cache = {}

    # --- 基础换算 ---
    def X(self, mm):
        return mm * self.k

    def font(self, bold, size_mm):
        key = (bold, round(size_mm, 4))
        if key not in self._font_cache:
            path = FONT_BOLD if bold else FONT_REG
            px = max(1, int(round(size_mm * self.k)))
            self._font_cache[key] = ImageFont.truetype(path, px)
        return self._font_cache[key]

    def text_w_mm(self, text, bold, size_mm):
        if not text:
            return 0.0
        return self.font(bold, size_mm).getlength(text) / self.k

    def metrics(self, bold, size_mm):
        return self.font(bold, size_mm).getmetrics()   # (ascent, descent)

    def draw_text(self, dr, x_mm, y_top_mm, text, bold, size_mm, fill=0):
        """字形顶 = y_top（等价 Swift 的 baseline = h - y - ascender）。"""
        if not text or size_mm <= 0:
            return
        dr.text((self.X(x_mm), self.X(y_top_mm)), text,
                font=self.font(bold, size_mm), fill=fill, anchor="la")

    def draw_centered(self, dr, cx_mm, cy_top_mm, text, bold, size_mm, fill=0):
        """黑条内居中：baseline = cyTop + (ascender + |descender|) / 2。"""
        if not text or size_mm <= 0:
            return
        asc, desc = self.metrics(bold, size_mm)
        baseline_mm = cy_top_mm + (asc + desc) / 2.0 / self.k
        dr.text((self.X(cx_mm), self.X(baseline_mm)), text,
                font=self.font(bold, size_mm), fill=fill, anchor="ms")

    # --- 整张标签 ---
    def paint(self, data):
        w = int(round(self.X(PAGE_W)))
        hpx = int(round(self.X(PAGE_H)))
        img = Image.new("L", (w, hpx), 255)
        dr = ImageDraw.Draw(img)
        s = self.s

        def R(x0, y0, x1, y1, fill):
            dr.rectangle([self.X(x0), self.X(y0), self.X(x1), self.X(y1)], fill=fill)

        # ---- 左右黑条 ----
        top = s["padV"]
        bar_h = PAGE_H - top * 2
        lx0, lx1 = s["padH"], s["padH"] + s["barWL"]
        rx1 = PAGE_W - s["padHR"]
        rx0 = rx1 - s["barWR"]
        R(lx0, top, lx1, top + bar_h, 0)
        R(rx0, top, rx1, top + bar_h, 0)

        # ---- 左黑条三排（黑底白字）----
        lcx = (lx0 + lx1) / 2
        seg = bar_h / 3
        self.draw_centered(dr, lcx, top + seg * 0.5, "星期", True, s["weekCnSz"], fill=255)
        self.draw_centered(dr, lcx, top + seg * 1.5, data["weekday_cn"], True, s["weekDaySz"], fill=255)
        self.draw_centered(dr, lcx, top + seg * 2.5, data["weekday_en"], True, s["weekEnSz"], fill=255)

        # ---- 右黑条竖排时间 ----
        rc = data["right_text"]
        n = len(rc) or 1
        cell = bar_h / n
        fz = cell * s["rightSzRatio"]
        rcx = (rx0 + rx1) / 2
        for i, ch in enumerate(rc):
            self.draw_centered(dr, rcx, top + cell * i + cell / 2, ch, True, fz, fill=255)

        # ---- 内容区 ----
        cx = s["padH"] + s["barWL"] + s["gapBar"]
        bar_right = PAGE_W - s["padHR"] - s["barWR"]
        lab_sz, row_sz = s["labSz"], s["rowSz"]

        max_text_w = 0.0
        for lab, val in data["rows"]:
            max_text_w = max(max_text_w, self.text_w_mm(lab, False, lab_sz))
            max_text_w = max(max_text_w, self.text_w_mm(val, True, row_sz))
        text_right = cx + max_text_w

        qs = s["qrSize"]
        # 与 Swift 的 LabelRenderer.qrBox 同一套逻辑：居中，放不下就等比收小。
        # ★ 别再退回「纯居中 + 夹取」—— 放不下时两个约束会互相矛盾，
        #   二维码会被推到右黑条外面去（CI 上量到过 45% 的溢出错位）。
        gap = s["qrGap"]
        free_w = bar_right - text_right
        if free_w < qs + gap * 2:
            qs = max(free_w - gap * 2, 0.0)
        qr_left = text_right + max((free_w - qs) / 2.0, 0.0)

        # ---- 标题（超宽自动缩字号）----
        title_sz = s["titleSz"]
        title_max_w = bar_right - cx - s["titleGapRight"]
        natural = self.text_w_mm(data["title"], True, title_sz)
        if natural > title_max_w > 0:
            title_sz = max(title_sz * title_max_w / natural, 1.0)
        self.draw_text(dr, cx, top, data["title"], True, title_sz)

        # ---- 三组「标签行 + 值行」----
        y = s["firstRow"]
        for lab, val in data["rows"]:
            self.draw_text(dr, cx, y, lab, False, lab_sz)
            self.draw_text(dr, cx, y + s["rowGap"], val, True, row_sz)
            y += s["rowStep"]

        # ---- 制作人（放大后若超出可用宽度自动缩，防止压到右黑条）----
        # 与 LabelRenderer.makerFit 同步：
        #   ① 可用宽要让出 makerGapRight(0.8)，否则缩完会精确贴在右黑条边缘；
        #   ② **不设可读性下限** —— 宁可小到看不清，也不许越界。
        #      （给过 0.8mm 的下限，24 字 × 0.8 = 19.2mm > 14mm 可用 → 照样戳进黑条 4mm。）
        maker_sz = s["makerSz"]
        maker_max_w = bar_right - qr_left - s["makerGapRight"]
        mw = self.text_w_mm(data["maker"], True, maker_sz)
        if mw > maker_max_w > 0:
            maker_sz = maker_sz * maker_max_w / mw
        self.draw_text(dr, qr_left, PAGE_H - s["makerBottom"], data["maker"], True, maker_sz)

        # ---- 二维码 ----
        self.draw_qr(dr, qr_text_of(data), qr_left, s["qrTop"], qs)
        return img

    def draw_qr(self, dr, text, x_mm, y_top_mm, size_mm):
        import qrcode
        q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,
                          border=0, box_size=1)
        q.add_data(text)
        q.make(fit=True)
        m = q.get_matrix()               # 含 border=0，纯模块
        n = len(m)
        total = n + QR_QUIET * 2
        pitch_mm = size_mm / total
        px = pitch_mm * self.k
        origin_x = x_mm + pitch_mm * QR_QUIET
        origin_y = y_top_mm + pitch_mm * QR_QUIET
        bleed = px * 0.02
        for r in range(n):
            for c in range(n):
                if not m[r][c]:
                    continue
                x0 = self.X(origin_x + c * pitch_mm)
                y0 = self.X(origin_y + r * pitch_mm)
                dr.rectangle([x0, y0, x0 + px + bleed, y0 + px + bleed], fill=0)
        return n


# ------------------------------------------------------------------ 出图
SHEET_BG = 245
GAP = 26
PAD = 30


def render_label(spec, data, px_per_mm, dpi1bit=False):
    r = Render(spec, px_per_mm)
    if not dpi1bit:
        return r.paint(data)
    # 模拟 203dpi(8 dots/mm) 实际打印点阵
    r8 = Render(spec, 8.0)
    img = r8.paint(data).point(lambda v: 0 if v < 128 else 255)
    return img.resize((img.width * 2, img.height * 2), Image.NEAREST)


def annotate(dr, x, y, text, size=17, fill=20, bold=True):
    f = ImageFont.truetype(FONT_BOLD if bold else FONT_REG, size)
    dr.text((x, y), text, font=f, fill=fill)


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    # ★ 20 px/mm：PIL 的字号只能取整数像素，14 px/mm 时 2.7mm 会被取整成 2.71，
    #   量出来的文字宽度比真机（连续字号）窄一截，看版式会误判余量。
    K = 20.0
    lw = int(round(PAGE_W * K))
    lh = int(round(PAGE_H * K))
    cap_h = 30

    panels = [
        ("通用效期 · 改前（当前线上版）", render_label(OLD, sample_generic(), K)),
        ("通用效期 · 改后", render_label(NEW, sample_generic(), K)),
        ("康普茶一发 · 改后", render_label(NEW, sample_kombucha(), K)),
        ("奶制品 · 改后", render_label(NEW, sample_dairy(), K)),
    ]

    # 一行两个，最后一行单独放 203dpi 点阵
    rows = [(panels[0], panels[1]), (panels[2], panels[3])]
    cols = 2
    sheet_w = PAD * 2 + cols * lw + (cols - 1) * GAP
    sheet_h = PAD * 2 + len(rows) * (cap_h + lh) + (len(rows) - 1) * (GAP + 10)
    sheet_h += cap_h + lh + GAP + 60      # 再留一行给 203dpi

    sheet = Image.new("L", (sheet_w, sheet_h), SHEET_BG)
    dr = ImageDraw.Draw(sheet)

    y = PAD
    for row in rows:
        x = PAD
        for cap, img in row:
            annotate(dr, x, y, cap)
            sheet.paste(img, (x, y + cap_h))
            dr.rectangle([x - 1, y + cap_h - 1, x + lw, y + cap_h + lh], outline=170)
            x += lw + GAP
        y += cap_h + lh + GAP + 10

    annotate(dr, PAD, y, "通用效期 · 改后 · 模拟 203dpi 实际打印点阵（放大 2 倍查看）")
    dot = render_label(NEW, sample_generic(), K, dpi1bit=True)
    sheet.paste(dot, (PAD, y + cap_h))
    dr.rectangle([PAD - 1, y + cap_h - 1, PAD + dot.width, y + cap_h + dot.height], outline=170)

    out = os.path.join(OUTDIR, "label_preview.png")
    sheet.save(out)
    print("[+] %s  (%d x %d)" % (out, sheet.width, sheet.height))

    # 单独一张：只放改进前后的 1:1 对比，方便看细节
    single = Image.new("L", (lw + 20, 2 * (cap_h + lh) + 40), SHEET_BG)
    d2 = ImageDraw.Draw(single)
    annotate(d2, 10, 8, "改前 / 改后（1:1）")
    single.paste(panels[0][1], (10, 8 + cap_h))
    single.paste(panels[1][1], (10, 8 + cap_h + lh + 28))
    out2 = os.path.join(OUTDIR, "label_before_after.png")
    single.save(out2)
    print("[+] %s  (%d x %d)" % (out2, single.width, single.height))


if __name__ == "__main__":
    main()
