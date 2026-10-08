#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
verify_qr_local.py —— 在本机验证「整张标签渲染出来的二维码」够不够结实。

为什么要它：
  真机上 `QRCodeTests.testRenderedLabelQRDecodesBackToPayload` 会做同样的事
  （渲染整张标签 → CIDetector 解码 → 比对原文），但那要云端构建 5 分钟 +
  下载 6 分钟 + 装机才能跑一次。改二维码内容的迭代成本太高了。

  ⚠️ 本机只有 OpenCV 的解码器，它在**真实打印分辨率**（8 dots/mm = 203dpi）下
  对「非整数模块宽度」的码一律解不出 —— 实测旧内容和新内容都解不出。
  所以**不能**拿「8 dots/mm 能不能解出」当通过判据（那会全红，毫无分辨力）。
  改用**相对判据**：扫描出「能稳定解出的最低 dots/mm」，新旧对比。
  这个数越低越好，且它能直接换算成「打印头上的余量」。

用法:
  python verify_qr_local.py

退出码 0 = 全部通过（新版的最低可解分辨率不高于旧版）。
"""

import os
import sys
import traceback

import cv2
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import render_label_preview as R  # noqa: E402

OUTDIR = os.path.join(HERE, "label_preview")
REAL_DOTS_PER_MM = 8.0          # 203dpi 热敏头
SCAN_LO, SCAN_HI, SCAN_STEP = 6.0, 18.0, 0.25


def decode(img):
    """用 OpenCV 的解码器读二维码；读不到 / 抛异常一律返回 None。

    ★ 必须 try：低分辨率下 cv2 会抛
      `Invalid QR code source points (contourArea == 0)`
      —— 那是把噪点当成定位图案了，属于「读不出来」，不是程序错误。
    """
    try:
        arr = np.array(img.convert("L"))
        text, _pts, _straight = cv2.QRCodeDetector().detectAndDecode(arr)
        return text or None
    except cv2.error:
        return None


def qr_text_old(d):
    """旧规则：名称 + 三组时间 + 制作人（v1.6.14 之前的 `LabelData.qrText`）。"""
    s = d["title"]
    for lab, val in d["rows"]:
        s += lab + val
    return s + d["maker"]


def min_decodable_dots_per_mm(data, qr_text_fn):
    """扫描出能稳定解出的最低 dots/mm；解不出返回 None。

    「稳定」= 原始点阵和放大 2 倍后**都能**解出，避免偶然命中。
    """
    original = R.qr_text_of
    try:
        R.qr_text_of = qr_text_fn
        expect = qr_text_fn(data)
        k = SCAN_LO
        while k <= SCAN_HI + 1e-9:
            img = R.render_label(R.NEW, data, k)
            binary = img.point(lambda v: 0 if v < 128 else 255)
            big = binary.resize((binary.width * 2, binary.height * 2), Image.NEAREST)
            if decode(binary) == expect and decode(big) == expect:
                return k
            k = round(k + SCAN_STEP, 2)
        return None
    finally:
        R.qr_text_of = original


def module_count(text):
    import qrcode
    q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,
                      box_size=1, border=1)
    q.add_data(text)
    q.make(fit=True)
    return q.modules_count


def main():
    os.makedirs(OUTDIR, exist_ok=True)

    samples = [
        ("通用效期", R.sample_generic()),
        ("康普茶一发", R.sample_kombucha()),
        ("奶制品", R.sample_dairy()),
        ("康普茶二发", dict(
            title="康普茶-茉莉绿茶-草莓",
            rows=[("制备时间：", "2026/10/20 10:00"),
                  ("完成时间：", "2026/10/23 10:00"),
                  ("最佳使用时间：", "2026/11/06 18:40")],
            weekday_cn="二", weekday_en="Tue", right_text="10:00",
            maker="制作人：张皓")),
    ]

    print("=" * 78)
    print("二维码结实度验证（本机 · 相对判据）")
    print("  判据：能稳定解出的最低打印分辨率，越低越好")
    print("=" * 78)
    print()
    print("%-12s %8s %8s %9s %10s" % ("模板", "旧模块", "新模块", "旧最低", "新最低"))
    print("-" * 78)

    failures = []
    for name, data in samples:
        try:
            old_text = qr_text_old(data)
            new_text = R.qr_text_of(data)
            old_m, new_m = module_count(old_text), module_count(new_text)
            old_k = min_decodable_dots_per_mm(data, qr_text_old)
            new_k = min_decodable_dots_per_mm(data, R.qr_text_of)
        except Exception:
            traceback.print_exc()
            failures.append("%s（脚本异常）" % name)
            continue

        print("%-12s %8d %8d %9s %10s" % (
            name, old_m, new_m,
            ("%.2f" % old_k) if old_k else ">18",
            ("%.2f" % new_k) if new_k else ">18"))

        if new_m > old_m:
            failures.append("%s：模块数反而变多了" % name)
        elif old_k and new_k and new_k > old_k:
            failures.append("%s：最低可解分辨率变高了（%.2f > %.2f）" % (name, new_k, old_k))
        elif new_k is None:
            failures.append("%s：新版在 18 dots/mm 以内都解不出" % name)

    print()
    print("-" * 78)
    print("各模板在新规则下的每模块打印点数（%g dots/mm 硬上限）：" % REAL_DOTS_PER_MM)
    for name, data in samples:
        text = R.qr_text_of(data)
        n = module_count(text) + 2          # +2 = 两侧静默边
        print("  %-12s %2d 模块 · 二维码 %gmm → %5.2f 点/模块"
              % (name, n, 14.0, 14.0 * REAL_DOTS_PER_MM / n))

    print()
    print("=" * 78)
    if failures:
        print("❌ 有问题：")
        for f in failures:
            print("   · %s" % f)
        return 1
    print("✅ 全部通过：新内容的二维码模块数更少、可解分辨率更低（更抗打印失真）")
    print("   ⚠️ cv2 在真实的 %g dots/mm 下对两种内容都解不出 —— 那是本机解码器的"
          % REAL_DOTS_PER_MM)
    print("      能力上限，不是版式问题；真机用 Apple 的 CIDetector，由单测覆盖。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
