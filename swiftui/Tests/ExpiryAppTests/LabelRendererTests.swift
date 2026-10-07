//
//  LabelRendererTests.swift
//  渲染引擎单元测试。
//
//  ★ 这一版是「真断言」，不再只是「PDF 非空」：
//    旧版只查 `pdf.count > 1000` 和 `%PDF` 头，结果画面全白、上下颠倒、
//    二维码被镜像，测试统统是绿的 —— 假通过。
//    现在把 PDF 栅格化成位图，按区域统计墨迹，直接验证**画面上真的有东西、
//    而且位置朝向是对的**。
//

import UIKit
import XCTest
@testable import ExpiryManager

final class LabelRendererTests: XCTestCase {

    // MARK: - 工具

    private func render(_ data: LabelData) -> Data {
        LabelRenderer.renderPDF(data,
                                regular: FontProvider.regular(12),
                                bold: FontProvider.bold(12))
    }

    private func raster(_ pdf: Data) -> UIImage {
        guard let image = PDFRasterizer.firstPageImage(from: pdf, maxPixel: 900) else {
            XCTFail("PDF 无法栅格化（文件损坏或页面尺寸为 0）")
            return UIImage()
        }
        return image
    }

    private func makeGeneric(title: String = "杨桃菠萝浓缩汁", maker: String = "四野") -> LabelData {
        let now = AppCalendar.shared.date(from: DateComponents(year: 2026, month: 10, day: 5,
                                                              hour: 15, minute: 30))!
        return LabelTemplate.buildGeneric(
            title: title, now: now,
            expireDate: now.addingTimeInterval(7 * 86400),
            bestBefore: now.addingTimeInterval(15 * 86400),
            maker: maker
        )
    }

    /// 只画一个标题的探针：用来判断「上下有没有颠倒」最干净。
    private func probe(title: String) -> LabelData {
        LabelData(title: title, rows: [],
                   weekdayCn: "", weekdayEn: "", rightText: "", maker: "")
    }

    // MARK: - 几何：毫米 → 归一化矩形

    /// 把 `LabelSpec` 的**毫米**几何换算成栅格图上的归一化矩形（原点左上）。
    ///
    /// ★ 为什么不直接写 0.04 / 0.90 这种数字：
    ///   左右留白从 1.5mm 改成 0.7mm 之后，原来手写的「右条 0.90~0.965」
    ///   就只剩 84% 的面积落在黑条上，离 `> 0.7` 的阈值只差一点 ——
    ///   换个字号就会莫名其妙变红。改成从 `LabelSpec` 推导后，
    ///   以后改版式时这些断言会跟着一起动，不会再出现「改版式改红测试」。
    ///
    /// - Parameter inset: 采样窗向内收（mm）。黑条边缘有抗锯齿过渡带，
    ///   贴着边缘取样会让墨迹比例飘，所以默认每条边收 0.4mm。
    private func norm(mmX: CGFloat, mmY: CGFloat, mmW: CGFloat, mmH: CGFloat,
                      inset: CGFloat = 0.4) -> CGRect {
        let pw = LabelSpec.pageW
        let ph = LabelSpec.pageH
        return CGRect(x: (mmX + inset) / pw,
                      y: (mmY + inset) / ph,
                      width: max(mmW - inset * 2, 0.02) / pw,
                      height: max(mmH - inset * 2, 0.02) / ph)
    }

    /// 左黑条（`padH` 起、宽 `barWL`，上下各留 `padV`）。
    private var leftBarRect: CGRect {
        norm(mmX: LabelSpec.padH, mmY: LabelSpec.padV,
             mmW: LabelSpec.barWL, mmH: LabelSpec.pageH - LabelSpec.padV * 2)
    }

    /// 右黑条（距右边 `padHR`、宽 `barWR`）。
    private var rightBarRect: CGRect {
        norm(mmX: LabelSpec.pageW - LabelSpec.padHR - LabelSpec.barWR,
             mmY: LabelSpec.padV,
             mmW: LabelSpec.barWR, mmH: LabelSpec.pageH - LabelSpec.padV * 2)
    }

    /// 内容列几何 —— 与 `LabelRenderer.paint` 里那几行**保持一致**。
    /// （`cx` 内容起点 / `barRight` 右黑条左缘 / `maxTextW` 最长一行宽度）
    private func contentGeometry(_ data: LabelData, regular: UIFont, bold: UIFont)
        -> (cx: CGFloat, barRight: CGFloat, maxTextW: CGFloat) {
        let mm = LabelSpec.kMm
        let cx = (LabelSpec.padH + LabelSpec.barWL + LabelSpec.gapBar) * mm
        let barRight = (LabelSpec.pageW - LabelSpec.padHR - LabelSpec.barWR) * mm
        var maxTextW: CGFloat = 0
        for r in data.rows {
            maxTextW = max(maxTextW, LabelRenderer.textWidth(r.label, font: regular,
                                                            size: LabelSpec.labSz * mm))
            maxTextW = max(maxTextW, LabelRenderer.textWidth(r.value, font: bold,
                                                             size: LabelSpec.rowSz * mm))
        }
        return (cx, barRight, maxTextW)
    }

    /// 三个模板各来一张，避免只测「通用效期」漏掉别的行文案。
    private func allSamples() -> [(String, LabelData)] {
        [
            ("通用效期", makeGeneric()),
            ("奶制品", LabelTemplate.buildDairy(
                kindLabel: DairyKind.oatMilk.label, now: Date(),
                expireDate: Date().addingTimeInterval(45 * 86400),
                bestBefore: Date().addingTimeInterval(5 * 86400), maker: "四野")),
            ("康普茶", LabelTemplate.buildKombuchaFirst(variety: "红茶", now: Date(), maker: "四野")),
        ]
    }

    // MARK: - 字体（版式数值的前提）

    /// ★★ 这条是「版式断言的前提」：**必须真的用上包内的 Noto Sans SC**。
    ///
    /// 依赖 Info.plist 的 `UIAppFonts` 时，测试宿主进程可能还没走完字体注册，
    /// `UIFont(name:)` 静默返回 nil → 回落到系统字体。同一串
    /// `"2026/10/07 18:40"` @2.7mm：真字体 22.696mm，回落字体 25.210mm。
    /// 差 2.5mm 足以把「放得下」翻转成「放不下」。
    /// 所以先把字体身份钉死，后面所有宽度/余量断言才有意义。
    func testBundledFontsAreActuallyUsed() {
        let b = FontProvider.bold(12)
        let r = FontProvider.regular(12)
        print("[diag] bold.fontName = \(b.fontName)   regular.fontName = \(r.fontName)")
        XCTAssertEqual(b.fontName, "NotoSansSC-Bold",
                       "粗体回落到了系统字体（\(b.fontName)），版式宽度会整体算错")
        XCTAssertEqual(r.fontName, "NotoSansSC-Regular",
                       "常规体回落到了系统字体（\(r.fontName)）")
    }

    /// 最长一行的宽度必须等于字体自己的 advance 之和 —— 钉死「量出来的宽度」。
    ///
    /// Noto Sans SC 的数字是**等宽**的（0.59 em），斜杠 0.387 / 空格 0.227 /
    /// 冒号 0.325 → 「yyyy/MM/dd HH:mm」恒为 **8.406 em**，与具体日期无关。
    /// 所以这条断言对任何日期都成立，不用挑样本。
    func testLongestRowWidthMatchesFontMetrics() {
        let mm = LabelSpec.kMm
        let size = LabelSpec.rowSz * mm
        for s in ["2026/10/07 18:40", "2026/10/22 23:59", "2026/11/21 23:59"] {
            let w = LabelRenderer.textWidth(s, font: FontProvider.bold(12), size: size) / mm
            print("[diag] \"\(s)\" @ \(LabelSpec.rowSz)mm = \(w)mm")
            XCTAssertEqual(w, 8.406 * LabelSpec.rowSz, accuracy: 0.05,
                           "「\(s)」实测 \(w)mm，与字体 advance（\(8.406 * LabelSpec.rowSz)mm）不符")
        }
    }

    // MARK: - 基本合法性

    func testRenderPDFProducesValidPDF() {
        let pdf = render(makeGeneric())
        XCTAssertGreaterThan(pdf.count, 1000, "PDF 不应为空")
        let head = pdf.prefix(4).map { String(format: "%c", $0) }.joined()
        XCTAssertEqual(head, "%PDF")
    }

    // MARK: - 画面真的有内容

    func testRenderedLabelActuallyHasInk() {
        let image = raster(render(makeGeneric()))
        let ink = PDFRasterizer.inkRatio(of: image)
        XCTAssertGreaterThan(ink, 0.15,
                             "整页墨迹过少，画面基本是白的（ink=\(ink)）")
        XCTAssertLessThan(ink, 0.85,
                          "整页墨迹过多，绘制异常（ink=\(ink)）")
    }

    /// 左右两条黑竖条是位置最稳的特征：用来确认页面没被裁掉、也没整体偏移。
    /// 归一化坐标由 LabelSpec 直接算出来（见 `leftBarRect` / `rightBarRect`），
    /// **不要再手写死数字**。
    /// （阈值只要 0.7 而不是 0.95，是因为黑条里还有白色竖排文字，不是纯黑。）
    func testSideBarsExistOnLeftAndRight() {
        let image = raster(render(makeGeneric()))
        let left = PDFRasterizer.inkRatio(of: image, in: leftBarRect)
        let right = PDFRasterizer.inkRatio(of: image, in: rightBarRect)
        // 页面底部中间应该是干净的（内容行、二维码、制作人都不在那里）
        let bottomCenter = PDFRasterizer.inkRatio(of: image,
                                                  in: norm(mmX: 9.5, mmY: 27.0,
                                                           mmW: 6.5, mmH: 2.0))
        XCTAssertGreaterThan(left, 0.7, "左侧黑条不见了（ink=\(left)）")
        XCTAssertGreaterThan(right, 0.7, "右侧黑条不见了（ink=\(right)）")
        XCTAssertLessThan(bottomCenter, 0.05, "页面底部中间不该有内容（ink=\(bottomCenter)）")
    }

    /// ★ 版式硬约束的回归测试（纯几何，不栅格化）：
    ///   「最长的一行文字」+「二维码」必须能**同时**塞进内容区。
    ///    可用内容宽度 = 50 − padH(0.7) − barWL(6.2) − gapBar(0.45)
    ///                    − barWR(3.8) − padHR(0.7) = 38.15mm
    ///    最长行「yyyy/MM/dd HH:mm」@ rowSz = 8.406em × 2.7 = 22.696mm
    ///    二维码 = qrSize = 14.0mm → 余 1.45mm（两侧各 0.73）
    ///
    /// ★ 断言直接调 `LabelRenderer.qrBox`（渲染层实际用的那个纯函数），
    ///   而不是在测试里再手写一遍居中公式 —— 否则测试和实现会各错各的。
    ///   两条不变量（不压文字 / 不进黑条）是结构性的，任何参数下都必须成立；
    ///   第三条（尺寸未被收小）才是「版式还放得下」的真正判据。
    func testContentColumnPlusQRCodeFitsBetweenBars() {
        let regular = FontProvider.regular(12)
        let bold = FontProvider.bold(12)
        let mm = LabelSpec.kMm

        for (name, data) in allSamples() {
            let g = contentGeometry(data, regular: regular, bold: bold)
            let textRight = g.cx + g.maxTextW
            let box = LabelRenderer.qrBox(textRight: textRight, barRight: g.barRight,
                                          desired: LabelSpec.qrSize * mm,
                                          gap: LabelSpec.qrGap * mm)
            let slack = (g.barRight - textRight - box.size) / mm
            print("[diag] \(name)：最长行 \(g.maxTextW / mm)mm，文字右端 \(textRight / mm)mm，"
                  + "二维码 \(box.size / mm)mm @ \((box.left) / mm)mm，剩余 \(slack)mm")

            // 不变量 1/2：不压文字、不进右黑条（恒成立，与参数无关）
            XCTAssertGreaterThanOrEqual(box.left, textRight - 0.01,
                                        "\(name) 的二维码压到了文字上")
            XCTAssertLessThanOrEqual(box.left + box.size, g.barRight + 0.01,
                                     "\(name) 的二维码越过了右黑条左缘")

            // 判据：二维码**没有被收小**，说明版式真的放得下
            XCTAssertEqual(box.size, LabelSpec.qrSize * mm, accuracy: 0.01,
                           "\(name) 放不下 \(LabelSpec.qrSize)mm 的二维码，被自动收小到 "
                           + "\(box.size / mm)mm（最长行 \(g.maxTextW / mm)mm）"
                           + " —— rowSz/qrSize/barWL 该往回退一点了")
            XCTAssertGreaterThanOrEqual(slack, 0.4,
                                        "\(name) 文字与二维码之间只剩 \(slack)mm，太挤")
        }
    }

    /// `qrBox` 的两条不变量必须在**任何**输入下成立 —— 包括文字宽到二维码放不下。
    ///
    /// 这是对「旧写法在放不下时把二维码推到黑条上」那个真 bug 的直接回归：
    /// 旧实现在 textRight > barRight − qs 时，上界 `max(barRight − qs, textRight)`
    /// 退化成 textRight，等于放弃了「不进黑条」这条约束。
    func testQRBoxNeverOverlapsEvenWhenTextIsTooWide() {
        let mm = LabelSpec.kMm
        let barRight = 45.5 * mm
        var shrunk = 0
        for w in stride(from: 0.0, through: 36.0, by: 2.0) {
            let textRight = (7.35 + w) * mm
            let box = LabelRenderer.qrBox(textRight: textRight, barRight: barRight,
                                          desired: LabelSpec.qrSize * mm,
                                          gap: LabelSpec.qrGap * mm)
            XCTAssertGreaterThanOrEqual(box.left, textRight - 0.01,
                                        "文字宽 \(w)mm：二维码压到文字上（left=\(box.left / mm)）")
            XCTAssertLessThanOrEqual(box.left + box.size, barRight + 0.01,
                                     "文字宽 \(w)mm：二维码越过右黑条（右缘=\((box.left + box.size) / mm)）")
            XCTAssertGreaterThanOrEqual(box.size, 0, "文字宽 \(w)mm：二维码边长为负")
            if box.size < LabelSpec.qrSize * mm - 0.01 { shrunk += 1 }
        }
        XCTAssertGreaterThan(shrunk, 0,
                             "探针没覆盖到「放不下」的分支，这条测试等于没测")
    }

    /// ★ 纵向硬约束（纯几何）：制作人页脚必须和第三行数值**拉开距离**。
    ///   字号从 2.3 放大到 2.7 之后三行一路排到 25.7mm，
    ///   而当时制作人「距底 5.0mm」（= 字形顶 25.0mm）—— 正好落在第三行的
    ///   行盒里，预览里看着像是第三行数值的尾巴。现在靠 `makerBottom 3.7`
    ///   把它压到 26.3mm 以下。
    ///
    /// ★ 判据不用 `ascender + |descender|` 去算「内容底」：
    ///   那是字体的**行盒**高度，比汉字/数字的实际字形高一截（CJK 几乎没有下伸部），
    ///   拿它做上界会让断言随字体度量浮动、动不动就红。这里只比
    ///   「制作人字形顶」和「最后一行数值的字形顶 + 一个 em」，语义清楚且稳定。
    func testMakerFooterIsSeparatedFromLastRow() {
        let data = makeGeneric()
        let lastValueTop = LabelSpec.firstRow
            + CGFloat(data.rows.count - 1) * LabelSpec.rowStep + LabelSpec.rowGap
        let makerTop = LabelSpec.pageH - LabelSpec.makerBottom
        let barBottom = LabelSpec.pageH - LabelSpec.padV

        print("[diag] 制作人字形顶 \(makerTop)mm，最后一行数值顶 \(lastValueTop)mm，"
              + "黑条下缘 \(barBottom)mm")

        XCTAssertGreaterThan(makerTop, lastValueTop + LabelSpec.rowSz,
                             "制作人和最后一行数值挨得太近，看起来会像同一行"
                             + "（制作人顶 \(makerTop)mm，最后一行顶 \(lastValueTop)mm）")
        XCTAssertLessThanOrEqual(makerTop + LabelSpec.makerSz, barBottom,
                                 "制作人字形底部越过了黑条下缘"
                                 + "（\(makerTop + LabelSpec.makerSz)mm > \(barBottom)mm）")
    }

    // MARK: - 黑条里的竖排白字

    /// ★★ 补掉的盲区：上面那条黑条断言阈值是 `> 0.7`，
    ///    而「纯黑的黑条(1.0)」和「黑底白字(~0.85)」**都能通过** ——
    ///    于是左右竖排的星期/时间根本没画出来，测试照样是绿的（用户实测发现了）。
    ///    这里改成直接数**亮像素**：黑条内部是纯黑，只有文字在那儿才会出现亮像素。
    func testLeftBlackBarCarriesWhiteWeekdayText() {
        let image = raster(render(makeGeneric()))
        // 左黑条：左留白 0.7mm 起、宽 6.2mm（坐标由 LabelSpec 推导，别再写死）
        let bar = leftBarRect
        let bright = PDFRasterizer.brightRatio(of: image, in: bar)
        let peak = PDFRasterizer.maxLuma(of: image, in: bar)
        print("[diag] 左黑条：亮像素比例 = \(bright)，最大灰度 = \(peak)")
        if bright <= 0.008 { dump(bar, of: image) }
        XCTAssertGreaterThan(bright, 0.008,
                             "左侧黑条里没有白色文字 —— 竖排的星期/中文日/英文缩写没画出来（bright=\(bright) peak=\(peak)）")
        XCTAssertLessThan(bright, 0.6, "左黑条几乎全白，黑条本身可能没画（bright=\(bright)）")
    }

    func testRightBlackBarCarriesWhiteTimeText() {
        let image = raster(render(makeGeneric()))
        // 右黑条：右留白 0.7mm、宽 3.8mm → 45.5~49.3mm（同样由 LabelSpec 推导）
        let bar = rightBarRect
        let bright = PDFRasterizer.brightRatio(of: image, in: bar)
        let peak = PDFRasterizer.maxLuma(of: image, in: bar)
        print("[diag] 右黑条：亮像素比例 = \(bright)，最大灰度 = \(peak)")
        if bright <= 0.008 { dump(bar, of: image) }
        XCTAssertGreaterThan(bright, 0.008,
                             "右侧黑条里没有白色文字 —— 竖排的时间没画出来（bright=\(bright) peak=\(peak)）")
        XCTAssertLessThan(bright, 0.6, "右黑条几乎全白，黑条本身可能没画（bright=\(bright)）")
    }

    /// 断言要挂的时候把该区域打成 ASCII 图（黑底白字会显示成 `#` 里的 `.`），
    /// 这样一条 CI 日志就能看出「字到底有没有画、画在哪」，不用再来回猜。
    private func dump(_ rect: CGRect, of image: UIImage) {
        print("[diag] ---- 区域 ASCII（. 为亮像素）----")
        for line in PDFRasterizer.asciiArt(of: image, in: rect, columns: 28, rows: 34) {
            print("[diag] \(line)")
        }
    }

    // MARK: - 朝向（防上下镜像）

    /// ★★ 关键回归测试：绘制坐标系一旦少一次翻转，整张标签会上下镜像 ——
    ///    标题跑到最底、文字倒立、二维码被镜像后扫不出来。
    func testTitleIsDrawnAtTopNotBottom() {
        let image = raster(render(probe(title: "顶部标题")))

        // 只取中间纵向带，避开左右黑条
        let top = PDFRasterizer.inkRatio(of: image, in: CGRect(x: 0.20, y: 0.03,
                                                              width: 0.65, height: 0.18))
        let bottom = PDFRasterizer.inkRatio(of: image, in: CGRect(x: 0.20, y: 0.80,
                                                                 width: 0.65, height: 0.17))

        XCTAssertGreaterThan(top, 0.005,
                             "标签顶部没有墨迹，标题可能画到了别处（top=\(top)）")
        XCTAssertLessThan(bottom, 0.002,
                          "标签底部不该有内容，画面疑似上下颠倒（bottom=\(bottom)）")
        XCTAssertGreaterThan(top, bottom * 3,
                             "顶部墨迹并不明显多于底部，朝向存疑")
    }

    /// 标题 + 三组内容时，第一组文字必须落在标题下方（而不是跑到页面外或反序）。
    func testContentRowsSitBelowTitle() {
        let image = raster(render(makeGeneric()))
        let titleBand = PDFRasterizer.inkRatio(of: image, in: CGRect(x: 0.16, y: 0.03,
                                                                    width: 0.70, height: 0.12))
        let rowBand = PDFRasterizer.inkRatio(of: image, in: CGRect(x: 0.16, y: 0.22,
                                                                  width: 0.45, height: 0.60))
        XCTAssertGreaterThan(titleBand, 0.01, "标题带没有内容")
        XCTAssertGreaterThan(rowBand, 0.01, "内容行带没有内容")
    }

    // MARK: - 二维码

    func testQRCodeIsActuallyDrawn() {
        let image = raster(render(makeGeneric()))
        // 二维码落在页面右半的中部区域（含 1 模块静默边，尺寸会随文字宽度微移）
        let qr = PDFRasterizer.inkRatio(of: image, in: CGRect(x: 0.30, y: 0.22,
                                                             width: 0.60, height: 0.50))
        XCTAssertGreaterThan(qr, 0.05, "二维码区域几乎没有墨迹，二维码可能生成失败（ink=\(qr)）")
    }

    // MARK: - 边界情况

    func testRenderHandlesEmptyTitle() {
        let image = raster(render(makeGeneric(title: "")))
        XCTAssertGreaterThan(PDFRasterizer.inkRatio(of: image), 0.05)
    }

    func testRenderHandlesLongTitle() {
        let long = String(repeating: "超长标题", count: 20)
        let image = raster(render(makeGeneric(title: long)))
        // 标题超宽时应该缩字号，而不是溢出把右黑条盖掉
        let right = PDFRasterizer.inkRatio(of: image, in: rightBarRect)
        XCTAssertGreaterThan(right, 0.7, "超长标题盖住了右侧黑条（ink=\(right)）")
    }

    // MARK: - 制作人页脚（字号放大后新增的边界）

    /// 制作人是**独立页脚**，不能空着，也不能跑到别处去。
    func testMakerFooterBandHasInk() {
        let image = raster(render(makeGeneric()))
        let band = norm(mmX: 30.0, mmY: 26.2, mmW: 15.0, mmH: 3.0)
        let ink = PDFRasterizer.inkRatio(of: image, in: band)
        print("[diag] 制作人页脚带：ink = \(ink)")
        XCTAssertGreaterThan(ink, 0.01, "制作人页脚带没有墨迹，制作人没画出来（ink=\(ink)）")
        XCTAssertLessThan(ink, 0.5, "制作人页脚带墨迹过多，可能压上了别的内容（ink=\(ink)）")
    }

    /// ★ 回归：**超长制作人名字不许戳进右黑条**。
    ///   字号放大到 1.8mm 后，「制作人：」+ 20 字上限 = 24 个汉字 ≈ 43mm，
    ///   而二维码左缘到右黑条之间只有约 14mm —— 全靠 `paint` 里绘制前那次
    ///   「超宽自动缩字号」兜住。这里放一个 19 字的名字，并检查
    ///   右黑条左侧那条 0.3mm 宽的空白带是不是干净的。
    ///   （旧实现把 `makerMaxW` 取成整段可用宽、字号下限又给到 0.8mm，
    ///     文字会精确地贴在 45.5mm 上/甚至戳进去 4mm —— 这条断言会红。）
    func testLongMakerNameDoesNotReachRightBar() {
        let long = String(repeating: "欧阳", count: 8)   // 16 字 → 制作人：+16 = 19 字
        let image = raster(render(makeGeneric(maker: long)))
        let strip = norm(mmX: 45.0, mmY: 26.0, mmW: 0.4, mmH: 3.2, inset: 0.05)
        let ink = PDFRasterizer.inkRatio(of: image, in: strip)
        print("[diag] 超长制作人 右黑条左缘空白带：ink = \(ink)")
        XCTAssertLessThan(ink, 0.02,
                          "超长制作人名字压到了右黑条左边（ink=\(ink)）")
    }

    func testRenderHandlesEmptyMaker() {
        let image = raster(render(makeGeneric(maker: "")))
        XCTAssertGreaterThan(PDFRasterizer.inkRatio(of: image), 0.05)
    }

    func testTextWidthIsZeroForEmptyString() {
        XCTAssertEqual(LabelRenderer.textWidth("", font: FontProvider.regular(12), size: 12), 0)
    }

    func testTextWidthPositive() {
        XCTAssertGreaterThan(LabelRenderer.textWidth("测试", font: FontProvider.regular(12), size: 12), 0)
    }

    /// 排障用：把三个模板的版式打成 ASCII 图并打印到 CI 日志里，
    /// 方便不进 Xcode 也能肉眼确认「标题在顶部、三行内容在中部、二维码在右中」。
    func testDumpAsciiLayout() {
        let samples = allSamples()

        for (name, data) in samples {
            let image = raster(render(data))
            let art = PDFRasterizer.asciiArt(of: image, columns: 64, rows: 24)
            print("=== 版式预览：\(name)（# 有墨 / . 空白；第一行 = 画面顶部）===")
            for line in art { print(line) }
            XCTAssertEqual(art.count, 24)
            XCTAssertTrue(art.contains { $0.contains("#") }, "\(name) 的 ASCII 墨迹图里没有任何内容")
        }
    }
}
