//
//  ExpiryRulesTests.swift
//  业务规则 + 加固措施（输入上限、文件名、二维码解析、到期分组）的单元测试。
//
//  这些都是「看不见但会出事」的地方：目录穿越、超长输入拖慢渲染、
//  外部二维码内容、历法差异导致日期算错。
//

import XCTest
@testable import ExpiryManager

final class ExpiryRulesTests: XCTestCase {

    private var now: Date {
        AppCalendar.shared.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
    }

    // MARK: - 输入上限

    func testClampTrimsAndTruncates() {
        XCTAssertEqual(LabelTemplate.clamp("  abc  "), "abc")
        XCTAssertEqual(LabelTemplate.clamp(String(repeating: "字", count: 100)).count,
                       LabelTemplate.maxTitleLength)
        XCTAssertEqual(LabelTemplate.clamp(String(repeating: "字", count: 100), 5).count, 5)
        XCTAssertEqual(LabelTemplate.clamp("   "), "")
    }

    func testOversizedInputIsClampedInsideLabel() {
        let data = LabelTemplate.buildKombuchaFirst(
            variety: String(repeating: "茶", count: 500),
            now: now,
            maker: String(repeating: "人", count: 500)
        )
        // 「康普茶-」4 字前缀 + 品种上限
        XCTAssertLessThanOrEqual(data.title.count, 4 + LabelTemplate.maxNameLength)
        XCTAssertLessThanOrEqual(data.maker.count, 4 + LabelTemplate.maxNameLength)
        // 二维码原文也不能无限长
        XCTAssertLessThanOrEqual(data.qrText.utf8.count, LabelTemplate.maxQrBytes)
    }

    // MARK: - 文件名（防目录穿越）

    func testLabelFileNameRejectsPathTraversal() {
        for bad in ["../../etc/passwd", "..", ".", "a/b", "C:\\evil", "  ..  ", "....//x"] {
            let name = LabelTemplate.labelFileName(bad, now)
            XCTAssertFalse(name.contains("/"), "文件名不该含路径分隔符：\(name)")
            XCTAssertFalse(name.contains("\\"), "文件名不该含反斜杠：\(name)")
            XCTAssertFalse(name.contains(".."), "文件名不该含 ..：\(name)")
            XCTAssertTrue(name.hasSuffix(".pdf"), "文件名应以 .pdf 结尾：\(name)")
            XCTAssertFalse(name.hasPrefix("."), "文件名不该以点开头：\(name)")
        }
    }

    func testPdfSaverSanitizeStripsPathAndDots() {
        XCTAssertEqual(PdfSaver.sanitize("../../evil.pdf"), "evil.pdf")
        XCTAssertEqual(PdfSaver.sanitize("/etc/passwd"), "passwd.pdf")
        XCTAssertEqual(PdfSaver.sanitize(".."), "标签.pdf")
        XCTAssertEqual(PdfSaver.sanitize(""), "标签.pdf")
        XCTAssertEqual(PdfSaver.sanitize("标签_20261005_1530.pdf"), "标签_20261005_1530.pdf")
        XCTAssertTrue(PdfSaver.sanitize(String(repeating: "x", count: 500)).count <= 64)
    }

    // MARK: - 二维码解析

    func testQRParseRejectsOverlongInput() {
        XCTAssertNil(LabelTemplate.parseKombuchaQr(String(repeating: "康", count: 5000)))
        XCTAssertNil(LabelTemplate.parseKombuchaQr(""))
    }

    func testQRParseRoundTripsGeneratedLabel() {
        let data = LabelTemplate.buildKombuchaFirst(variety: "红茶", now: now, maker: "四野")
        let parsed = LabelTemplate.parseKombuchaQr(data.qrText)
        XCTAssertNotNil(parsed, "自己生成的二维码内容应该能解析回来")
        XCTAssertEqual(parsed?.title, "康普茶-红茶")
        // 新格式二维码里已经没有制作人 → 扫回来是空串
        XCTAssertEqual(parsed?.maker, "")
        XCTAssertEqual(parsed?.finished,
                       AppCalendar.shared.date(byAdding: .day,
                                                value: LabelTemplate.kombuchaDoneDays,
                                                to: now))
        XCTAssertEqual(parsed?.bestBefore,
                       AppCalendar.shared.date(byAdding: .day,
                                                value: LabelTemplate.kombuchaBestDays,
                                                to: now))
    }

    func testQRParseRejectsNonKombuchaLabel() {
        let generic = LabelTemplate.buildGeneric(title: "杨桃汁", now: now,
                                                 expireDate: now, bestBefore: now,
                                                 maker: "四野")
        XCTAssertNil(LabelTemplate.parseKombuchaQr(generic.qrText))
    }

    // MARK: - 到期分组

    private func record(daysFromNow: Int, used: Bool = false) -> LabelRecord {
        let due = AppCalendar.shared.date(byAdding: .day, value: daysFromNow, to: now)!
        return LabelRecord(title: "样本",
                           kind: .generic,
                           maker: "四野",
                           createdAt: now,
                           printedAt: now,
                           expireAt: due,
                           bestBefore: due,
                           usedAt: used ? now : nil,
                           qrText: UUID().uuidString,
                           source: .printed)
    }

    func testExpiryStatusBuckets() {
        XCTAssertEqual(ExpiryStatus.of(record(daysFromNow: -2), now: now).stage, .expired)
        XCTAssertEqual(ExpiryStatus.of(record(daysFromNow: 0), now: now).stage, .today)
        XCTAssertEqual(ExpiryStatus.of(record(daysFromNow: 1), now: now).stage, .within3)
        XCTAssertEqual(ExpiryStatus.of(record(daysFromNow: 3), now: now).stage, .within3)
        XCTAssertEqual(ExpiryStatus.of(record(daysFromNow: 5), now: now).stage, .within7)
        XCTAssertEqual(ExpiryStatus.of(record(daysFromNow: 30), now: now).stage, .later)
        XCTAssertEqual(ExpiryStatus.of(record(daysFromNow: -9, used: true), now: now).stage, .used)
    }

    func testAlertingCountOnlyCoversExpiredTodayAndThreeDays() {
        XCTAssertTrue(ExpiryStatus.of(record(daysFromNow: -1), now: now).isAlerting)
        XCTAssertTrue(ExpiryStatus.of(record(daysFromNow: 0), now: now).isAlerting)
        XCTAssertTrue(ExpiryStatus.of(record(daysFromNow: 3), now: now).isAlerting)
        XCTAssertFalse(ExpiryStatus.of(record(daysFromNow: 4), now: now).isAlerting)
        XCTAssertFalse(ExpiryStatus.of(record(daysFromNow: -1, used: true), now: now).isAlerting)
    }

    // MARK: - 历法

    /// 无论设备把「日历」设成什么，标签上的日期都必须按公历算。
    func testGregorianCalendarIsUsed() {
        XCTAssertEqual(AppCalendar.shared.identifier, .gregorian)
        let stamp = AppCalendar.shared.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        XCTAssertEqual(LabelTemplate.fmtDate(stamp), "2026/10/05")
        let plusSeven = AppCalendar.shared.date(byAdding: .day, value: 7, to: stamp)!
        XCTAssertEqual(LabelTemplate.fmtDate(plusSeven), "2026/10/12")
    }
}
