#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
qr_preview.py —— 出一张「改前 / 改后」的二维码对比图。

左边 = 旧规则（名称 + 三组时间 + 制作人），右边 = 新规则（名称 + 后两组时间）。
两张都是同一条标签、同样的 14mm 二维码尺寸，只差内容 —— 所以模块数不同，
每个模块能分到的打印点数也不同（203dpi 热敏头只有 8 点/mm）。

用法:
  python qr_preview.py     # → <脚本目录>/label_preview/qr_density.png
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import render_label_preview as R  # noqa: E402

OUTDIR = os.path.join(HERE, "label_preview")
REAL_DOTS_PER_MM = 8.0


def qr_text_old(d):
    s = d["title"]
    for lab, val in d["rows"]:
        s += lab + val
    return s + d["maker"]


def modules_of(text, border=1):
    import qrcode
    q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,
                      box_size=1, border=border)
    q.add_data(text)
    q.make(fit=True)
    return q.modules_count


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    K = 20.0
    data = R.sample_generic()

    old_text = qr_text_old(data)
    new_text = R.qr_text_of(data)
    old_m = modules_of(old_text)
    new_m = modules_of(new_text)

    # 只画二维码本身（同尺寸、同静默边），模拟在标签上的样子
    def qr_tile(text, size_px):
        import qrcode
        q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,
                          border=1, box_size=10)
        q.add_data(text)
        q.make(fit=True)
        img = q.make_image(fill_color="black", back_color="white").convert("L")
        return img.resize((size_px, size_px), Image.NEAREST)

    qr_px = int(round(14.0 * K))          # 14mm @20px/mm
    left = qr_tile(old_text, qr_px)
    right = qr_tile(new_text, qr_px)

    PAD, CAP, GAP = 30, 34, 40
    sheet_w = PAD * 2 + qr_px * 2 + GAP
    sheet_h = PAD + CAP + qr_px + 26 + CAP + 120
    sheet = Image.new("L", (sheet_w, sheet_h), 245)
    dr = ImageDraw.Draw(sheet)
    f_cap = ImageFont.truetype(R.FONT_BOLD, 19)
    f_small = ImageFont.truetype(R.FONT_REG, 15)
    f_mono = ImageFont.truetype(R.FONT_REG, 14)

    def cap(x, y, t, font=f_cap, fill=20):
        dr.text((x, y), t, font=font, fill=fill)

    cap(PAD, PAD, "改前：名称 + 三组时间 + 制作人")
    cap(PAD + qr_px + GAP, PAD, "改后：名称 + 后两组时间")
    sheet.paste(left, (PAD, PAD + CAP))
    sheet.paste(right, (PAD + qr_px + GAP, PAD + CAP))
    dr.rectangle([PAD - 1, PAD + CAP - 1, PAD + qr_px, PAD + CAP + qr_px], outline=180)
    dr.rectangle([PAD + qr_px + GAP - 1, PAD + CAP - 1,
                  PAD + qr_px + GAP + qr_px, PAD + CAP + qr_px], outline=180)

    y = PAD + CAP + qr_px + 12
    for x, (label, text, n) in ((PAD, ("改前", old_text, old_m)),
                                (PAD + qr_px + GAP, ("改后", new_text, new_m))):
        cap(x, y, "%s：%d 字节 · %d 模块（含静默边 %d）"
            % (label, len(text.encode("utf-8")), n, n + 2), f_small)
        cap(x, y + 22, "每模块仅 %.2f 个打印点" % (14.0 * REAL_DOTS_PER_MM / (n + 2)),
            f_small, 60)

    cap(PAD, sheet_h - 96, "二维码物理尺寸同为 14mm，打印头 203dpi = 8 点/mm。", f_mono, 70)
    cap(PAD, sheet_h - 76, "内容越短 → 模块越少 → 每个模块分到的点越多 → 越不容易糊。", f_mono, 70)
    cap(PAD, sheet_h - 52, "模块 %d → %d（-%d%%）；每模块 %.2f → %.2f 点（+%.0f%%）"
        % (old_m, new_m, round((old_m - new_m) / old_m * 100),
           14.0 * REAL_DOTS_PER_MM / (old_m + 2),
           14.0 * REAL_DOTS_PER_MM / (new_m + 2),
           (new_m + 2) / (old_m + 2) * 100 - 100), f_mono, 20)

    out = os.path.join(OUTDIR, "qr_density.png")
    sheet.save(out)
    print("[+] %s  (%d x %d)" % (out, sheet.width, sheet.height))


if __name__ == "__main__":
    main()
