//
//  LabelRendererTests.swift
//  渲染引擎单元测试：PDF 生成合法、边界情况不崩溃。
//

import XCTest
@testable import ExpiryManager

final class LabelRendererTests: XCTestCase {

    private func makeData(title: String, maker: String = "四野") -> LabelData {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5,
                                                             hour: 15, minute: 30))!
        return LabelTemplate.buildGeneric(
            title: title, now: now,
            expireDate: now.addingTimeInterval(7 * 86400),
            bestBefore: now.addingTimeInterval(15 * 86400),
            maker: maker
        )
    }

    func testRenderPDFProducesValidPDF() {
        let data = makeData(title: "杨桃汁")
        let pdf = LabelRenderer.renderPDF(data,
                                          regular: FontProvider.regular(12),
                                          bold: FontProvider.bold(12))
        XCTAssertGreaterThan(pdf.count, 1000, "PDF 不应为空")
        // 合法 PDF 以 "%PDF" 开头
        let head = pdf.prefix(4).map { String(format: "%c", $0) }.joined()
        XCTAssertEqual(head, "%PDF")
    }

    func testRenderPDFHandlesEmptyTitle() {
        let data = makeData(title: "")
        let pdf = LabelRenderer.renderPDF(data,
                                          regular: FontProvider.regular(12),
                                          bold: FontProvider.bold(12))
        XCTAssertGreaterThan(pdf.count, 1000)
    }

    func testRenderPDFHandlesLongTitle() {
        let data = makeData(title: String(repeating: "超长标题", count: 20))
        let pdf = LabelRenderer.renderPDF(data,
                                          regular: FontProvider.regular(12),
                                          bold: FontProvider.bold(12))
        XCTAssertGreaterThan(pdf.count, 1000)
    }

    func testRenderPDFHandlesEmptyMaker() {
        let data = makeData(title: "杨桃汁", maker: "")
        let pdf = LabelRenderer.renderPDF(data,
                                          regular: FontProvider.regular(12),
                                          bold: FontProvider.bold(12))
        XCTAssertGreaterThan(pdf.count, 1000)
    }

    func testTextWidthPositive() {
        XCTAssertGreaterThan(LabelRenderer.textWidth("测试", font: FontProvider.regular(12), size: 12), 0)
    }
}
