//
//  LabelRenderer.swift
//  标签渲染引擎 —— 精确迁移 Flutter `label_renderer.dart` 的 paintLabel。
//
//  坐标约定（★ 全文件统一，改之前先读懂这一段）：
//    `paint(...)` 里的所有数学都按 **原点左下、y 向上**（标准 PDF/CoreGraphics）
//    来写：`h - y` 就是把「距顶部的距离」换算成「距底部的距离」。
//
//  但 `UIGraphicsPDFRenderer` 交给我们的 `cgContext` 是 **UIKit 朝向**
//  （原点左上、y 向下）——苹果文档明确写过它内部的 PDF 目标空间与
//  CGContext 用户空间 y 轴方向相反。所以 `renderPDF` 里必须先把 CTM
//  翻成 y 向上，`paint` 才是对的。
//
//  ⚠️ 不翻转的后果（曾经发生过）：
//    整张标签**上下镜像** —— 标题跑到最底下、所有文字倒立、
//    二维码被垂直镜像后扫码器读不出来。
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

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: data.title,
            kCGPDFContextCreator as String: "效期管理系统",
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let c = ctx.cgContext

            // ★★ 把 UIKit 朝向（左上原点、y 向下）翻成绘图数学假设的
            //    「左下原点、y 向上」。翻完之后：
            //      · 文字正立（CoreText 在 y 向上空间里才不镜像）
            //      · CGContext.draw(image:) 图片正立（二维码才扫得出来）
            c.saveGState()
            c.translateBy(x: 0, y: h)
            c.scaleBy(x: 1, y: -1)
            paint(data, in: c, regular: regular, bold: bold)
            c.restoreGState()
        }
    }

    /// 在 CoreGraphics context 里绘制整张标签。
    /// 前置条件：context 的坐标系必须是 y 向上（见 `renderPDF`）。
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
        // ★ 黑底白字：颜色必须**同时**写进属性串（见 `drawText` 的说明），
        //   只 setFillColor 会让字变成黑色、跟黑条糊在一起。
        let lcx = (lx0 + lx1) / 2
        let seg = barH / 3
        c.setFillColor(UIColor.white.cgColor)
        drawCentered(c, bold, "星期", mm(LabelSpec.weekCnSz), lcx, top + seg * 0.5, color: .white)
        drawCentered(c, bold, d.weekdayCn, mm(LabelSpec.weekDaySz), lcx, top + seg * 1.5, color: .white)
        drawCentered(c, bold, d.weekdayEn, mm(LabelSpec.weekEnSz), lcx, top + seg * 2.5, color: .white)

        // ---- 右黑条：竖排时间 HH:MM，每字符居中等分整条 ----
        let rc = d.rightText
        let n = rc.isEmpty ? 1 : rc.count
        let cell = barH / CGFloat(n)
        let fz = cell * LabelSpec.rightSzRatio
        let rcx = (rx0 + rx1) / 2
        c.setFillColor(UIColor.white.cgColor)
        for (i, ch) in rc.enumerated() {
            drawCentered(c, bold, String(ch), fz, rcx,
                         top + cell * CGFloat(i) + cell / 2, color: .white)
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
        // 二维码：在「文字右端 → 右黑条左缘」之间居中；放不下会自动收小。
        // 见 `qrBox` 的说明 —— 这里是**结构性**保证不压文字、不进黑条。
        let qr = qrBox(textRight: textRight, barRight: barRight,
                       desired: mm(LabelSpec.qrSize), gap: mm(LabelSpec.qrGap))
        let qrLeft = qr.left
        let qs = qr.size

        // ---- 标题：顶部与黑条顶端齐平，超宽自动缩小 ----
        c.setFillColor(UIColor.black.cgColor)
        var fittedTitleSize = titleSize
        let titleMaxW = barRight - cx - mm(LabelSpec.titleGapRight)
        let naturalTitleW = textWidth(d.title, font: bold, size: titleSize)
        if naturalTitleW > titleMaxW && naturalTitleW > 0 {
            fittedTitleSize = max(titleSize * titleMaxW / naturalTitleW, 1)
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

        // ---- 制作人：贴底一条页脚，与二维码左缘对齐 ----
        // ★ 字号放大到 1.8mm 后，名字长一点就会横着顶到右黑条上
        //   （「制作人：」+ 20 字姓名 = 24 个汉字 ≈ 43mm，可用只有十几毫米）。
        //   所以跟标题一样做一次「超宽自动缩字号」，宁可小一点也不要压坏版式。
        //
        // ★ 两个细节，都是「不这么写就会画到黑条上」：
        //   ① `makerMaxW` 要和标题一样**再让出一个 `titleGapRight`**。
        //      否则缩字号是「缩到刚好等于可用宽度」，长名字会精确地贴在
        //      `barRight` 上 —— 黑字压在黑条边缘，既是毛边又难看。
        //   ② 下限 0.8mm 太高：最坏情况是 24 个汉字（「制作人：」+ 20 字上限），
        //      0.8mm 时总宽 19.2mm > 14.0mm 可用宽 → **照样戳进右黑条 4mm**。
        //      压到 0.5mm 后 24 × 0.5 = 12.0mm，才真正保证任何输入都不会越界。
        var makerSize = mm(LabelSpec.makerSz)
        let makerMaxW = barRight - qrLeft - mm(LabelSpec.titleGapRight)
        let naturalMakerW = textWidth(d.maker, font: bold, size: makerSize)
        if naturalMakerW > makerMaxW && naturalMakerW > 0 {
            makerSize = max(makerSize * makerMaxW / naturalMakerW, mm(0.5))
        }
        drawText(c, bold, d.maker, makerSize, qrLeft,
                 mm(LabelSpec.makerBottom) - ascender(bold, makerSize))

        // ---- 二维码 ----
        drawQR(c, d.qrText, qrLeft, mm(LabelSpec.qrTop), qs)
    }

    // MARK: - 文字测量与绘制

    /// 二维码在「文字右端 `textRight` → 右黑条左缘 `barRight`」之间居中，
    /// 两侧各留至少 `gap`；**放不下就等比收小**。
    ///
    /// 返回 `(左缘, 边长)`，并且**恒定满足**：
    ///   · `left ≥ textRight`        —— 绝不压到文字上
    ///   · `left + size ≤ barRight`  —— 绝不进右黑条
    ///   · 左右两侧留白相等           —— 视觉居中
    /// （`free ≤ 0` 时 `size` 会退化成 0，`drawQR` 有不变量保护直接不画；
    ///   实际上内容列最多 23mm、可用 38mm，走不到那个分支。）
    ///
    /// ★★ 为什么不再用「居中 + 夹取」：
    ///   旧写法 `qrLeft = min(max(居中值, textRight), max(barRight − qs, textRight))`
    ///   在「压根放不下」时**两个约束互相矛盾** —— 上界退化成 `textRight`，
    ///   于是二维码右缘 = `textRight + 14mm`，**直接越过右黑条**画到黑条上。
    ///   CI 上实测炸的就是这个：`testLongMakerNameDoesNotReachRightBar`
    ///   在右黑条左侧那条空白带里量到 45% 墨迹 —— 那就是溢出去的二维码。
    ///   把「放得下多大」先算出来再摆位，不变量才是结构性的、不靠参数凑巧。
    static func qrBox(textRight: CGFloat, barRight: CGFloat,
                      desired: CGFloat, gap: CGFloat) -> (left: CGFloat, size: CGFloat) {
        let free = barRight - textRight
        var size = desired
        if free < size + gap * 2 {
            size = max(free - gap * 2, 0)
        }
        let left = textRight + max((free - size) / 2, 0)
        return (left, size)
    }

    /// 测量文字在给定字号下的宽度（pt）。
    static func textWidth(_ text: String, font: UIFont, size: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let f = font.withSize(size)
        let attr = NSAttributedString(string: text, attributes: [.font: f])
        let line = CTLineCreateWithAttributedString(attr)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// 基线到顶的距离（pt）。`UIFont.ascender` 本身就是「点」，不要再乘字号。
    static func ascender(_ font: UIFont, _ size: CGFloat) -> CGFloat {
        font.withSize(size).ascender
    }

    /// 基线到底的距离（pt）。
    static func descenderDepth(_ font: UIFont, _ size: CGFloat) -> CGFloat {
        -font.withSize(size).descender
    }

    /// 在基线 (x, baselineY) 处绘制文字（要求 y 向上坐标系）。
    ///
    /// ★★ `color` 必须写进属性串里，**不能只靠 `CGContext.setFillColor`**：
    ///    CoreText 只有在属性串**没有前景色**时才会回退去用上下文的 fill color，
    ///    而 `UIGraphicsPDFRenderer` 包装过的上下文里这条回退并不可靠 ——
    ///    实测结果是：黑条上的白字全被画成了**黑色**，和黑条糊在一起，
    ///    一个亮像素都没有（用户肉眼反馈「左右两侧黑竖条里的字不见了」，
    ///    由 `brightRatio` 断言精确定位）。写进 `.foregroundColor` 才是
    ///    CoreText 的主路径，稳定可靠。
    static func drawText(_ c: CGContext, _ font: UIFont, _ text: String,
                         _ size: CGFloat, _ x: CGFloat, _ baselineY: CGFloat,
                         color: UIColor = .black) {
        guard !text.isEmpty, size > 0 else { return }
        let f = font.withSize(size)
        let attr = NSAttributedString(string: text, attributes: [
            .font: f,
            .foregroundColor: color,
        ])
        let line = CTLineCreateWithAttributedString(attr)
        // ★ 显式置为单位矩阵：UIGraphicsPDFRenderer 的上下文本身带翻转，
        //   继承下来的 text matrix 不确定，不显式设定就有镜像风险。
        c.textMatrix = .identity
        c.textPosition = CGPoint(x: x, y: baselineY)
        CTLineDraw(line, c)
    }

    /// 在水平中心 (cx, cyTop) 处居中绘制（cyTop 为视觉中心的 top-down y）。
    static func drawCentered(_ c: CGContext, _ font: UIFont, _ text: String,
                             _ size: CGFloat, _ cx: CGFloat, _ cyTop: CGFloat,
                             color: UIColor = .black) {
        guard !text.isEmpty, size > 0 else { return }
        let h = LabelSpec.pageH * LabelSpec.kMm
        let tw = textWidth(text, font: font, size: size)
        // 视觉中心 cyTop（top-down）→ 基线（y 向上）
        // 行高 = ascender + |descender|，两个量都已经是「点」，不再乘 size。
        let lineHalf = (ascender(font, size) + descenderDepth(font, size)) / 2
        let baseline = h - (cyTop + lineHalf)
        drawText(c, font, text, size, cx - tw / 2, baseline, color: color)
    }

    // MARK: - 二维码

    /// 每边静默边宽度（单位：模块）。与 Flutter 版一致。
    static let qrQuietModules = 1

    /// 在 (x, yTop) 处绘制边长为 size 的二维码（yTop 为顶边的 top-down y）。
    ///
    /// ★★ 逐模块**矢量**绘制，不是把一张小位图放大。
    /// 位图放大的两个恶果（实机上肉眼可见）：
    ///   · 源图只有「1 像素 = 1 模块」（二十来像素），放大到 600dpi 是十几倍插值 → 糊；
    ///   · 块与块之间会出现大小不一的接缝，看起来发乱。
    /// 这里每个模块就是一个实心方块，打印是纯黑、预览缩放也不糊，
    /// 而且静默边由 `qrQuietModules` 精确控制，不会出现多余的黑框。
    static func drawQR(_ c: CGContext, _ data: String,
                       _ x: CGFloat, _ yTop: CGFloat, _ size: CGFloat) {
        guard !data.isEmpty, size > 0,
              let m = QRCodeGenerator.matrix(for: data) else { return }

        let h = LabelSpec.pageH * LabelSpec.kMm
        let quiet = qrQuietModules
        let total = CGFloat(m.size + quiet * 2)
        let pitch = size / total

        // size 是**含静默边**的整体尺寸（与 Flutter 版一致）。
        let boxBottom = h - yTop - size          // y 向上的坐标系里，框的下边
        let originX = x + pitch * CGFloat(quiet)
        let originY = boxBottom + pitch * CGFloat(quiet)

        c.saveGState()

        // 先铺一层白：静默边永远是干净的白。页面本来就是白的，这里是双保险，
        // 也顺手把「四周多出一圈黑框」这种历史问题彻底堵死。
        c.setFillColor(UIColor.white.cgColor)
        c.fill(CGRect(x: x, y: boxBottom, width: size, height: size))

        c.setFillColor(UIColor.black.cgColor)
        // 相邻方块之间多画 0.01mm，避免 PDF 光栅化时出现发丝级白缝。
        let bleed = pitch * 0.02
        for row in 0..<m.size {
            // row 0 是符号最上面一行，而 y 向上 → 要翻过来算。
            let y = originY + CGFloat(m.size - 1 - row) * pitch
            for col in 0..<m.size where m.isDark(row, col) {
                c.fill(CGRect(x: originX + CGFloat(col) * pitch,
                              y: y,
                              width: pitch + bleed,
                              height: pitch + bleed))
            }
        }
        c.restoreGState()
    }
}
