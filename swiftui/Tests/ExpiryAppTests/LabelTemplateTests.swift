//
//  LabelTemplateTests.swift
//  业务规则单元测试：日期格式化、阈值、三模板装配、二维码解析、文件名。
//

import XCTest
@testable import ExpiryManager

final class LabelTemplateTests: XCTestCase {

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 15, _ mi: Int = 30) -> Date {
        AppCalendar.shared.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: mi))!
    }

    // MARK: 日期格式化

    func testFmtDate() {
        XCTAssertEqual(LabelTemplate.fmtDate(d(2026, 10, 5)), "2026/10/05")
        XCTAssertEqual(LabelTemplate.fmtDate(d(2026, 1, 3)), "2026/01/03")
    }

    func testFmtDateTime() {
        XCTAssertEqual(LabelTemplate.fmtDateTime(d(2026, 10, 5, 15, 30)), "2026/10/05 15:30")
        XCTAssertEqual(LabelTemplate.fmtDateTime(d(2026, 10, 5, 9, 5)), "2026/10/05 09:05")
    }

    func testFmtTime() {
        XCTAssertEqual(LabelTemplate.fmtTime(d(2026, 10, 5, 15, 30)), "15:30")
        XCTAssertEqual(LabelTemplate.fmtTime(d(2026, 10, 5, 9, 5)), "09:05")
    }

    // MARK: 阈值规则

    func testIsWithinThreshold() {
        let now = d(2026, 10, 5)
        XCTAssertTrue(LabelTemplate.isWithinThreshold(now, d(2026, 10, 5)))   // 当天
        XCTAssertTrue(LabelTemplate.isWithinThreshold(now, d(2026, 10, 12)))  // +7 天
        XCTAssertFalse(LabelTemplate.isWithinThreshold(now, d(2026, 10, 13))) // +8 天
    }

    func testFmtDateByThreshold() {
        let now = d(2026, 10, 5, 15, 30)
        // ≤7 天 → 当前时刻
        XCTAssertEqual(LabelTemplate.fmtDateByThreshold(now, d(2026, 10, 12)), "2026/10/12 15:30")
        // >7 天 → 23:59
        XCTAssertEqual(LabelTemplate.fmtDateByThreshold(now, d(2026, 10, 15)), "2026/10/15 23:59")
    }

    // MARK: 通用效期

    func testBuildGeneric() {
        let now = d(2026, 10, 5, 15, 30)
        let data = LabelTemplate.buildGeneric(
            title: "杨桃汁", now: now,
            expireDate: d(2026, 10, 12), bestBefore: d(2026, 10, 15), maker: "四野"
        )
        XCTAssertEqual(data.title, "杨桃汁")
        XCTAssertEqual(data.rows.count, 3)
        XCTAssertEqual(data.rows[0].label, "开封时间：")
        XCTAssertEqual(data.rows[0].value, "2026/10/05 15:30")
        XCTAssertEqual(data.rows[1].label, "原始保质期：")
        XCTAssertEqual(data.rows[1].value, "2026/10/12 15:30") // ≤7 天
        XCTAssertEqual(data.rows[2].label, "最佳使用时间：")
        XCTAssertEqual(data.rows[2].value, "2026/10/15 23:59") // >7 天
        XCTAssertEqual(data.maker, "制作人：四野")
        XCTAssertEqual(data.rightText, "15:30")
    }

    // MARK: 康普茶

    func testKombuchaTitle() {
        XCTAssertEqual(LabelTemplate.kombuchaTitle("红茶"), "康普茶-红茶")
        XCTAssertEqual(LabelTemplate.kombuchaTitle("康普茶-红茶"), "康普茶-红茶")
    }

    func testBuildKombuchaFirst() {
        let now = d(2026, 10, 5, 15, 30)
        let data = LabelTemplate.buildKombuchaFirst(variety: "红茶", now: now, maker: "四野")
        XCTAssertEqual(data.title, "康普茶-红茶")
        XCTAssertEqual(data.rows[0].value, "2026/10/05 15:30") // 制备 = now
        XCTAssertEqual(data.rows[1].value, "2026/10/12 15:30") // 完成 = +7 天
        XCTAssertEqual(data.rows[2].value, "2026/11/04 15:30") // 最佳 = +30 天
    }

    func testBuildKombuchaSecond() {
        let now = d(2026, 10, 20, 10, 0)
        let firstFinished = d(2026, 10, 12, 15, 30)
        let firstBest = d(2026, 11, 4, 15, 30)
        let data = LabelTemplate.buildKombuchaSecond(
            firstTitle: "康普茶-红茶", fruit: "草莓", now: now,
            firstFinished: firstFinished, firstBestBefore: firstBest, maker: "四野"
        )
        XCTAssertEqual(data.title, "康普茶-红茶-草莓")
        XCTAssertEqual(data.rows[0].value, "2026/10/20 10:00") // 制备 = 扫码那刻
        XCTAssertEqual(data.rows[1].value, "2026/10/15 15:30") // 完成 = 一发完成 + 3 天
        XCTAssertEqual(data.rows[2].value, "2026/11/04 15:30") // 最佳沿用
    }

    // MARK: 二维码文本

    func testQrText() {
        let now = d(2026, 10, 5, 15, 30)
        let data = LabelTemplate.buildGeneric(
            title: "杨桃汁", now: now,
            expireDate: d(2026, 10, 12), bestBefore: d(2026, 10, 15), maker: "四野"
        )
        XCTAssertEqual(
            data.qrText,
            "杨桃汁开封时间：2026/10/05 15:30原始保质期：2026/10/12 15:30最佳使用时间：2026/10/15 23:59制作人：四野"
        )
    }

    // MARK: 二维码解析

    func testParseKombuchaQr() {
        let raw = "康普茶-红茶制备时间：2026/10/05 15:30完成时间：2026/10/12 15:30最佳使用时间：2026/11/04 15:30制作人：四野"
        let parsed = LabelTemplate.parseKombuchaQr(raw)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.title, "康普茶-红茶")
        XCTAssertEqual(parsed?.variety, "红茶")
        XCTAssertEqual(parsed?.maker, "四野")
        XCTAssertEqual(LabelTemplate.fmtDateTime(parsed!.prepared), "2026/10/05 15:30")
    }

    func testParseKombuchaQrRejectsNonKombucha() {
        // 标题不以「康普茶」开头 → nil
        let raw = "奶制品开封时间：2026/10/05 15:30完成时间：2026/10/12 15:30最佳使用时间：2026/11/04 15:30制作人：四野"
        XCTAssertNil(LabelTemplate.parseKombuchaQr(raw))
        // 乱码 → nil
        XCTAssertNil(LabelTemplate.parseKombuchaQr("随便一段文字"))
    }

    // MARK: 文件名

    func testLabelFileName() {
        let now = d(2026, 10, 5, 15, 30)
        XCTAssertEqual(LabelTemplate.labelFileName("杨桃汁", now), "杨桃汁_20261005_1530.pdf")
        // 非法字符替换
        XCTAssertEqual(LabelTemplate.labelFileName("a/b:c", now), "a_b_c_20261005_1530.pdf")
    }

    // MARK: 奶制品类型

    func testDairyKindDays() {
        XCTAssertEqual(DairyKind.milk.expireDays, 7)
        XCTAssertEqual(DairyKind.milk.bestDays, 3)
        XCTAssertEqual(DairyKind.oatMilk.expireDays, 45)
        XCTAssertEqual(DairyKind.almondMilk.expireDays, 60)
        XCTAssertEqual(DairyKind.almondMilk.bestDays, 7)
    }
}
