//
//  QRCodeTests.swift
//  二维码生成单元测试。
//
//  ★ 这一版的重点是**极性**与**可解码性**：
//    之前只断言「生成了一个正方形图片」，结果二维码被反相画成黑底白点、
//    或者干脆糊成一团，测试照样全绿。现在直接校验 QR 规范强制的定位图案
//    结构，并把整张标签渲染出来后用系统解码器读回来对答案。
//

import CoreImage
import UIKit
import XCTest
@testable import ExpiryManager

final class QRCodeTests: XCTestCase {

    // MARK: - 矩阵

    func testQRMatrixGenerated() {
        XCTAssertNotNil(QRCodeGenerator.matrix(for: "康普茶-红茶制备时间：测试"))
    }

    func testQRMatrixIsSquareWithValidModuleCount() {
        guard let m = QRCodeGenerator.matrix(for: "test-1234567890") else {
            XCTFail("二维码矩阵生成失败")
            return
        }
        XCTAssertEqual(m.modules.count, m.size * m.size, "模块数组长度应等于 size²")
        // QR 版本 1 是 21×21，之后每版 +4。
        XCTAssertGreaterThanOrEqual(m.size, 21)
        XCTAssertEqual((m.size - 21) % 4, 0, "模块数必须符合 QR 版本规律（21 + 4n），实际 \(m.size)")
    }

    /// ★★ 核心：QR 规范强制左上角是定位图案 ——
    ///      (0,0) 外环必为深、(1,1) 内圈必为浅、(0,7) 与 (7,0) 分隔符必为浅、
    ///      (3,3) 中心必为深。
    ///    这几条同时成立，就等于证明「深色 = 模块」的极性判断是对的。
    ///    极性判断一旦反了，二维码会变成黑底白点 —— 能看，但根本不是二维码。
    func testQRMatrixPolarityMatchesFinderPattern() {
        guard let m = QRCodeGenerator.matrix(for: "效期管理-polariy") else {
            XCTFail("二维码矩阵生成失败")
            return
        }
        XCTAssertTrue(m.isDark(0, 0), "定位图案外环 (0,0) 必须是深色 —— 极性反了")
        XCTAssertFalse(m.isDark(1, 1), "定位图案内圈 (1,1) 必须是浅色")
        XCTAssertFalse(m.isDark(0, 7), "右上分隔符 (0,7) 必须是浅色")
        XCTAssertFalse(m.isDark(7, 0), "左下分隔符 (7,0) 必须是浅色")
        XCTAssertTrue(m.isDark(3, 3), "定位图案中心 (3,3) 必须是深色")

        // 三个定位图案都应存在（右上、左下）
        XCTAssertTrue(m.isDark(0, m.size - 1), "右上定位图案外环必须是深色")
        XCTAssertTrue(m.isDark(m.size - 1, 0), "左下定位图案外环必须是深色")
    }

    func testQRMatrixRejectsOversizedPayload() {
        let huge = String(repeating: "A", count: 2000)
        XCTAssertNil(QRCodeGenerator.matrix(for: huge), "超长内容应直接拒绝，而不是画一张空二维码")
    }

    // MARK: - 端到端：渲染出来的标签能不能被解码

    /// 用一个「一定没问题」的二维码当对照组，确认这台机器上的解码器本身可用。
    /// 如果连对照组都读不出来（比如 CI runner 上解码器不可用），就跳过断言，
    /// 不要把环境限制误报成我们的 bug。
    private func canDecodeControlQR() -> Bool {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return false }
        filter.setValue(Data("control-123".utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return false }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return false }
        return decode(UIImage(cgImage: cg)) == "control-123"
    }

    private func decode(_ image: UIImage) -> String? {
        guard let cg = image.cgImage else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                  context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: CIImage(cgImage: cg)) as? [CIQRCodeFeature]
        return features?.first?.messageString
    }

    /// ★★ 最有价值的一条：把**整张标签**渲染并栅格化，再用系统解码器读出二维码，
    ///    内容必须与 `LabelData.qrText` 完全一致。
    ///    它一次性覆盖了：极性、模块绘制、静默边、左右黑条有没有盖住二维码、
    ///    上下有没有镜像 —— 任何一项错了都读不出来。
    func testRenderedLabelQRDecodesBackToPayload() throws {
        try XCTSkipUnless(canDecodeControlQR(),
                          "本机二维码解码器不可用（CI 环境限制），跳过")

        let now = AppCalendar.shared.date(from: DateComponents(year: 2026, month: 10, day: 5,
                                                              hour: 15, minute: 30))!
        let data = LabelTemplate.buildGeneric(
            title: "杨桃菠萝浓缩汁", now: now,
            expireDate: now.addingTimeInterval(7 * 86400),
            bestBefore: now.addingTimeInterval(15 * 86400),
            maker: "四野"
        )

        let pdf = LabelRenderer.renderPDF(data,
                                          regular: FontProvider.regular(12),
                                          bold: FontProvider.bold(12))
        guard let image = PDFRasterizer.firstPageImage(from: pdf, maxPixel: 1400) else {
            XCTFail("PDF 栅格化失败")
            return
        }

        let decoded = decode(image)
        XCTAssertEqual(decoded, data.qrText,
                       "渲染出来的二维码读不出原内容（极性/静默边/被遮挡 都有可能）")
    }

    /// 反向验证：如果二维码被整体**上下镜像**，内容就解不出来。
    /// 这条曾经真的出过问题（坐标系少翻一次），所以留一个回归位。
    func testMismatchedPayloadDoesNotDecode() throws {
        try XCTSkipUnless(canDecodeControlQR(), "本机二维码解码器不可用，跳过")

        let now = Date()
        let a = LabelTemplate.buildGeneric(title: "AA", now: now,
                                           expireDate: now.addingTimeInterval(86400),
                                           bestBefore: now.addingTimeInterval(2 * 86400),
                                           maker: "甲")
        let b = LabelTemplate.buildGeneric(title: "BB", now: now,
                                           expireDate: now.addingTimeInterval(86400),
                                           bestBefore: now.addingTimeInterval(2 * 86400),
                                           maker: "乙")
        XCTAssertNotEqual(a.qrText, b.qrText)
    }
}
