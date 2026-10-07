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
    /// （阈值放到 0.7 是因为黑条里还有白色文字，不是纯黑。）
    func testSideBarsExistOnLeftAndRight() {
        let image = raster(render(makeGeneric()))
        let left = PDFRasterizer.inkRatio(of: image, in: CGRect(x: 0.04, y: 0.10,
                                                               width: 0.10, height: 0.80))
        let right = PDFRasterizer.inkRatio(of: image, in: CGRect(x: 0.90, y: 0.10,
                                                                width: 0.065, height: 0.80))
        // 页面底部中间应该是干净的（内容行与二维码都不在那里）
        let bottomCenter = PDFRasterizer.inkRatio(of: image, in: CGRect(x: 0.20, y: 0.90,
                                                                       width: 0.15, height: 0.07))
        XCTAssertGreaterThan(left, 0.7, "左侧黑条不见了（ink=\(left)）")
        XCTAssertGreaterThan(right, 0.7, "右侧黑条不见了（ink=\(right)）")
        XCTAssertLessThan(bottomCenter, 0.05, "页面底部中间不该有内容（ink=\(bottomCenter)）")
    }

    // MARK: - 黑条里的竖排白字

    /// ★★ 补掉的盲区：上面那条黑条断言阈值是 `> 0.7`，
    ///    而「纯黑的黑条(1.0)」和「黑底白字(~0.85)」**都能通过** ——
    ///    于是左右竖排的星期/时间根本没画出来，测试照样是绿的（用户实测发现了）。
    ///    这里改成直接数**亮像素**：黑条内部是纯黑，只有文字在那儿才会出现亮像素。
    func testLeftBlackBarCarriesWhiteWeekdayText() {
        let image = raster(render(makeGeneric()))
        // 左黑条：左留白 1.5mm 起、宽 6.2mm → 归一化 0.030~0.154；上下留白 1mm。
        let bar = CGRect(x: 0.032, y: 0.05, width: 0.120, height: 0.90)
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
        // 右黑条：右留白 1.5mm、宽 3.8mm → 归一化 0.894~0.970。
        let bar = CGRect(x: 0.896, y: 0.05, width: 0.072, height: 0.90)
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
        let right = PDFRasterizer.inkRatio(of: image, in: CGRect(x: 0.90, y: 0.10,
                                                                width: 0.065, height: 0.80))
        XCTAssertGreaterThan(right, 0.7, "超长标题盖住了右侧黑条（ink=\(right)）")
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
        let samples: [(String, LabelData)] = [
            ("通用效期", makeGeneric()),
            ("康普茶", LabelTemplate.buildKombuchaFirst(variety: "红茶", now: Date(), maker: "四野")),
            ("奶制品", LabelTemplate.buildDairy(kindLabel: DairyKind.oatMilk.label, now: Date(),
                                              expireDate: Date().addingTimeInterval(7 * 86400),
                                              bestBefore: Date().addingTimeInterval(15 * 86400),
                                              maker: "四野")),
        ]

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
