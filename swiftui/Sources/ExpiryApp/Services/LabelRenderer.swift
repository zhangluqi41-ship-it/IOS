//
//  LabelRenderer.swift
//  标签渲染引擎 —— 精确迁移 Flutter `label_renderer.dart` 的 paintLabel。
//
//  坐标：CoreGraphics PDF 坐标（原点左下、y 向上），与 Flutter 版
//  「原点左上、y 向下再翻」的结果完全一致。
//  文字用 CoreText（CTLineDraw），基线精确控制，等效 Flutter 的 drawString。
//

import CoreText
import UIKit

enum LabelRenderer {
    /// 生成 50×30mm 标签 PDF（矢量绘制，可直接打印）。
    static func renderPDF(_ data: LabelData,
                          regular: UIFont,
                          bold: UIFont) -> Data {
        let w = LabelSpec.pageW * LabelSpec.kMm
        let h = LabelSpec.pageH * LabelSpec.kMm
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            paint(data, in: ctx.cgContext, regular: regular, bold: bold)
        }
    }

    /// 在 CoreGraphics context 里绘制整张标签。
    static func paint(_ d: LabelData,
                      in c: CGContext,
                      regular: UIFont,
                      bold: UIFont) {
        let w = LabelSpec.pageW * LabelSpec.kMm
        let h = LabelSpec.pageH * LabelSpec.kMm
        func mm(_ v: CGFloat) -> CGFloat { v * LabelSpec.kMm }

        // ---- 左右黑条（连续整条）----
        let top = mm(LabelSpec.padV)
        let barH = h - top * 2
        let lx0 = mm(LabelSpec.padH)
        let lx1 = mm(LabelSpec.padH + LabelSpec.barWL)
        let rx1 = w - mm(LabelSpec.padHR)
        let rx0 = rx1 - mm(LabelSpec.barWR)

        c.setFillColor(UIColor.black.cgColor)
        c.fill(CGRect(x: lx0, y: top, width: lx1 - lx0, height: barH))
        c.fill(CGRect(x: rx0, y: top, width: rx1 - rx0, height: barH))

        // ---- 左黑条三排（星期 / 中文日 / 英文缩写）----
        let lcx = (lx0 + lx1) / 2
        let seg = barH / 3
        c.setFillColor(UIColor.white.cgColor)
        drawCentered(c, bold, "星期", mm(LabelSpec.weekCnSz), lcx, top + seg * 0.5)
        drawCentered(c, bold, d.weekdayCn, mm(LabelSpec.weekDaySz), lcx, top + seg * 1.5)
        drawCentered(c, bold, d.weekdayEn, mm(LabelSpec.weekEnSz), lcx, top + seg * 2.5)

        // ---- 右黑条：竖排时间 HH:MM，每字符居中等分整条 ----
        let rc = d.rightText
        let n = rc.isEmpty ? 1 : rc.count
        let cell = barH / CGFloat(n)
        let fz = cell * LabelSpec.rightSzRatio
        let rcx = (rx0 + rx1) / 2
        c.setFillColor(UIColor.white.cgColor)
        for (i, ch) in rc.enumerated() {
            drawCentered(c, bold, String(ch), fz, rcx, top + cell * CGFloat(i) + cell / 2)
        }

        // ---- 内容区 ----
        let cx = mm(LabelSpec.padH + LabelSpec.barWL + LabelSpec.gapBar)
        let barRight = w - mm(LabelSpec.padHR + LabelSpec.barWR)
        let titleSize = mm(LabelSpec.titleSz)
        let labSize = mm(LabelSpec.labSz)
        let rowSize = mm(LabelSpec.rowSz)

        // 量出文字实际最大宽度，二维码在「文字右端 ~ 右黑条左缘」区间居中
        var maxTextW: CGFloat = 0
        for r in d.rows {
            maxTextW = max(maxTextW, textWidth(r.label, font: regular, size: labSize))
            maxTextW = max(maxTextW, textWidth(r.value, font: bold, size: rowSize))
        }
        let textRight = cx + maxTextW
        let qs = mm(LabelSpec.qrSize)
        let freeW = barRight - textRight
        let qrLeft = textRight + (freeW - qs) / 2

        // ---- 标题：顶部与黑条顶端齐平，超宽自动缩小 ----
        c.setFillColor(UIColor.black.cgColor)
        var fittedTitleSize = titleSize
        let titleMaxW = barRight - cx - mm(LabelSpec.titleGapRight)
        let naturalTitleW = textWidth(d.title, font: bold, size: titleSize)
        if naturalTitleW > titleMaxW && naturalTitleW > 0 {
            fittedTitleSize = titleSize * titleMaxW / naturalTitleW
        }
        drawText(c, bold, d.title, fittedTitleSize, cx, h - top - ascender(bold, fittedTitleSize))

        // ---- 三组「标签行 + 值行」----
        var y = mm(LabelSpec.firstRow)
        for r in d.rows {
            drawText(c, regular, r.label, labSize, cx, h - y - ascender(regular, labSize))
            let vy = y + mm(LabelSpec.rowGap)
            drawText(c, bold, r.value, rowSize, cx, h - vy - ascender(bold, rowSize))
            y += mm(LabelSpec.rowStep)
        }

        // ---- 制作人：距底 5.0mm，与二维码左缘对齐 ----
        let mSize = mm(LabelSpec.makerSz)
        drawText(c, bold, d.maker, mSize, qrLeft, mm(LabelSpec.makerBottom) - ascender(bold, mSize))

        // ---- 二维码 ----
        drawQR(c, d.qrText, qrLeft, mm(LabelSpec.qrTop), qs)
    }

    // MARK: - 文字测量与绘制

    /// 测量文字在给定字号下的宽度（pt）。
    static func textWidth(_ text: String, font: UIFont, size: CGFloat) -> CGFloat {
        let f = font.withSize(size)
        let attr = NSAttributedString(string: text, attributes: [.font: f])
        let line = CTLineCreateWithAttributedString(attr)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// 基线到顶的距离（pt），对应 Flutter 的 font.ascent * size。
    static func ascender(_ font: UIFont, _ size: CGFloat) -> CGFloat {
        font.withSize(size).ascender
    }

    /// 基线到底的距离（pt），对应 Flutter 的 font.descent * size。
    static func descenderDepth(_ font: UIFont, _ size: CGFloat) -> CGFloat {
        -font.withSize(size).descender
    }

    /// 在基线 (x, baselineY) 处绘制文字（CoreGraphics PDF 坐标）。
    static func drawText(_ c: CGContext, _ font: UIFont, _ text: String,
                         _ size: CGFloat, _ x: CGFloat, _ baselineY: CGFloat) {
        let f = font.withSize(size)
        let attr = NSAttributedString(string: text, attributes: [.font: f])
        let line = CTLineCreateWithAttributedString(attr)
        c.textPosition = CGPoint(x: x, y: baselineY)
        CTLineDraw(line, c)
    }

    /// 在水平中心 (cx, cyTop) 处居中绘制（cyTop 为视觉中心的 top-down y）。
    static func drawCentered(_ c: CGContext, _ font: UIFont, _ text: String,
                             _ size: CGFloat, _ cx: CGFloat, _ cyTop: CGFloat) {
        guard !text.isEmpty else { return }
        let h = LabelSpec.pageH * LabelSpec.kMm
        let tw = textWidth(text, font: font, size: size)
        // Flutter: baseline = cy + (ascent + descent) * size / 2，再翻到 PDF 坐标
        let baseline = h - (cyTop + (ascender(font, size) + descenderDepth(font, size)) * size / 2)
        drawText(c, font, text, size, cx - tw / 2, baseline)
    }

    // MARK: - 二维码

    /// 在 (x, yTop) 处绘制边长为 size 的二维码（yTop 为顶边的 top-down y）。
    /// 含 1 模块静默边，与 Flutter 版一致。
    static func drawQR(_ c: CGContext, _ data: String,
                       _ x: CGFloat, _ yTop: CGFloat, _ size: CGFloat) {
        guard let img = QRCodeGenerator.qrImage(for: data) else { return }
        let h = LabelSpec.pageH * LabelSpec.kMm
        let modules = img.width
        let border = 1
        let total = CGFloat(modules + border * 2)
        let inset = size * CGFloat(border) / total // 每边静默边
        let rect = CGRect(
            x: x + inset,
            y: h - yTop - size + inset,
            width: size - inset * 2,
            height: size - inset * 2
        )
        c.saveGState()
        c.interpolationQuality = .none // 最近邻，保持方块锐利
        c.draw(img, in: rect)
        c.restoreGState()
    }
}
