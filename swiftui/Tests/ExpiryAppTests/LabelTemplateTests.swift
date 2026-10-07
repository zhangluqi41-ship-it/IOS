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
        let firstBest = d(2026, 11, 4, 15, 30)
        let data = LabelTemplate.buildKombuchaSecond(
            firstTitle: "康普茶-红茶", fruit: "草莓", now: now,
            firstBestBefore: firstBest, maker: "四野"
        )
        XCTAssertEqual(data.title, "康普茶-红茶-草莓")
        XCTAssertEqual(data.rows[0].value, "2026/10/20 10:00") // 制备 = 扫码那刻
        XCTAssertEqual(data.rows[1].value, "2026/10/23 10:00") // 完成 = 制备 + 3 天
        XCTAssertEqual(data.rows[2].value, "2026/11/04 15:30") // 最佳沿用
    }

    /// ★★ 回归位：二发的完成时间必须**只比制备时间晚 3 天**。
    ///
    /// 曾经写成「一发完成时间 + 3 天」，而一发完成 = 一发制备 + 7 天，
    /// 于是标签上「制备时间 → 完成时间」的间隔变成了 +10 天（用户实测反馈）。
    /// 这条断言就是钉死「间隔恒为 3 天」，与扫码早晚无关。
    func testKombuchaSecondDoneIsExactlyThreeDaysAfterPrep() {
        for offsetHours in [0, 5, 30, 100, 500] {
            let now = d(2026, 10, 20, 10, 0).addingTimeInterval(Double(offsetHours) * 3600)
            let data = LabelTemplate.buildKombuchaSecond(
                firstTitle: "康普茶-红茶", fruit: "草莓", now: now,
                firstBestBefore: d(2026, 12, 31), maker: "四野"
            )
            let done = LabelTemplate.kombuchaSecondDone(after: now)
            let gap = AppCalendar.shared.dateComponents([.day], from: now, to: done).day
            XCTAssertEqual(gap, LabelTemplate.kombuchaSecondDoneDays,
                           "完成时间与制备时间必须正好差 \(LabelTemplate.kombuchaSecondDoneDays) 天")
            // 入库记录的 expireAt 与标签上印的必须是同一个值
            XCTAssertEqual(LabelTemplate.fmtDateTime(done), data.rows[1].value)
        }
    }

    // MARK: 二维码文本

    func testQrText() {
        let now = d(2026, 10, 5, 15, 30)
        let data = LabelTemplate.buildGeneric(
            title: "杨桃汁", now: now,
            expireDate: d(2026, 10, 12), bestBefore: d(2026, 10, 15), maker: "四野"
        )
        // 名称 + 后两组时间；**不含**第一组「开封时间」，也不含制作人
        XCTAssertEqual(
            data.qrText,
            "杨桃汁原始保质期：2026/10/12 15:30最佳使用时间：2026/10/15 23:59"
        )
    }

    /// ★ 三个模板的二维码都必须丢掉**第一组时间**和制作人 —— 四个页面统一实现，
    ///   但改 `qrText` 很容易顾此失彼，这里逐个钉住。
    func testQrTextDropsFirstRowAndMakerForEveryTemplate() {
        let now = d(2026, 10, 5, 15, 30)

        let samples: [(String, LabelData)] = [
            ("通用", LabelTemplate.buildGeneric(title: "杨桃汁", now: now,
                                              expireDate: d(2026, 10, 12),
                                              bestBefore: d(2026, 10, 15), maker: "四野")),
            ("奶制品", LabelTemplate.buildDairy(kindLabel: "牛奶", now: now,
                                              expireDate: d(2026, 10, 12),
                                              bestBefore: d(2026, 10, 8), maker: "四野")),
            ("康普茶一发", LabelTemplate.buildKombuchaFirst(variety: "红茶", now: now, maker: "四野")),
            ("康普茶二发", LabelTemplate.buildKombuchaSecond(
                firstTitle: "康普茶-红茶", fruit: "草莓", now: now,
                firstBestBefore: d(2026, 11, 4), maker: "四野")),
        ]

        for (name, data) in samples {
            XCTAssertFalse(data.qrText.contains(data.rows[0].label),
                           "\(name)：二维码里不该再有第一组时间「\(data.rows[0].label)」")
            XCTAssertFalse(data.qrText.contains(data.rows[0].value),
                           "\(name)：二维码里不该再有第一组时间的值")
            XCTAssertFalse(data.qrText.contains("制作人"),
                           "\(name)：二维码里不该再有制作人")
            XCTAssertTrue(data.qrText.hasPrefix(data.title),
                          "\(name)：二维码必须以名称开头")
            XCTAssertTrue(data.qrText.contains(data.rows[1].label),
                          "\(name)：后两组时间要保留")
            XCTAssertTrue(data.qrText.contains(data.rows[2].label),
                          "\(name)：后两组时间要保留")
        }
    }

    // MARK: 二维码解析

    func testParseKombuchaQr() {
        // 新格式：名称 + 后两组时间
        let raw = "康普茶-红茶完成时间：2026/10/12 15:30最佳使用时间：2026/11/04 15:30"
        let parsed = LabelTemplate.parseKombuchaQr(raw)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.title, "康普茶-红茶")
        XCTAssertEqual(parsed?.variety, "红茶")
        XCTAssertEqual(LabelTemplate.fmtDateTime(parsed!.finished), "2026/10/12 15:30")
        XCTAssertEqual(LabelTemplate.fmtDateTime(parsed!.bestBefore), "2026/11/04 15:30")
        XCTAssertEqual(parsed?.maker, "", "新格式里没有制作人")
    }

    /// ★★ 兼容性：v1.6.14 之前打印出去的**实物标签**（旧格式带制备时间与制作人）
    ///    必须照样能扫 —— 否则用户手里已经贴出去的码就废了。
    func testParseKombuchaQrLegacyFormat() {
        let raw = "康普茶-红茶制备时间：2026/10/05 15:30完成时间：2026/10/12 15:30"
            + "最佳使用时间：2026/11/04 15:30制作人：四野"
        let parsed = LabelTemplate.parseKombuchaQr(raw)
        XCTAssertNotNil(parsed, "旧格式实物标签必须仍然可解析")
        XCTAssertEqual(parsed?.title, "康普茶-红茶")
        XCTAssertEqual(parsed?.maker, "四野")
        XCTAssertEqual(LabelTemplate.fmtDateTime(parsed!.finished), "2026/10/12 15:30")
        XCTAssertEqual(LabelTemplate.fmtDateTime(parsed!.bestBefore), "2026/11/04 15:30")
    }

    /// 自己生成的二维码必须能自己解析回来（发 → 收 闭环）。
    func testKombuchaFirstQrRoundTrip() {
        let now = d(2026, 10, 5, 15, 30)
        let data = LabelTemplate.buildKombuchaFirst(variety: "红茶", now: now, maker: "四野")
        let parsed = LabelTemplate.parseKombuchaQr(data.qrText)
        XCTAssertNotNil(parsed, "一发标签的二维码内容必须能被二发流程解析")
        XCTAssertEqual(parsed?.title, "康普茶-红茶")
        XCTAssertEqual(parsed?.finished,
                       AppCalendar.shared.date(byAdding: .day,
                                               value: LabelTemplate.kombuchaDoneDays,
                                               to: now))
    }

    func testParseKombuchaQrRejectsNonKombucha() {
        // 标题不以「康普茶」开头 → nil
        XCTAssertNil(LabelTemplate.parseKombuchaQr(
            "奶制品完成时间：2026/10/12 15:30最佳使用时间：2026/11/04 15:30"))
        // 是康普茶、但缺「完成时间」→ nil（新格式必须有后两组时间）
        XCTAssertNil(LabelTemplate.parseKombuchaQr(
            "康普茶-红茶最佳使用时间：2026/11/04 15:30"))
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
