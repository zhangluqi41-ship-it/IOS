//
//  OptimizationTests.swift
//  2026-10-08 优化清单对应的回归测试。
//
//  覆盖三件**容易悄悄坏掉**的事：
//    1. 「重新打印」用的 `LabelTemplate.rebuild(from:)` 必须与原标签**逐字一致**
//       —— 它是从记录反推的，不是重新算的，一旦有人改回去就会印出错标签；
//    2. 康普茶的「到期日」不许早于「完成时间」（发酵没完成谈不上过期）；
//    3. 提醒必须覆盖两个里程碑，「康普茶完成」的文案要按语义出。
//

import XCTest
@testable import ExpiryManager

final class OptimizationTests: XCTestCase {

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 15, _ mi: Int = 30) -> Date {
        AppCalendar.shared.date(from: DateComponents(year: y, month: m, day: day,
                                                     hour: h, minute: mi))!
    }

    private var now: Date { d(2026, 10, 8, 12, 0) }

    private func day(_ n: Int, from base: Date? = nil) -> Date {
        AppCalendar.shared.date(byAdding: .day, value: n, to: base ?? now)!
    }

    // MARK: - 重新打印：rebuild 必须与原标签逐字一致

    private func assertRebuildMatches(_ record: LabelRecord,
                                      _ original: LabelData,
                                      _ message: String,
                                      file: StaticString = #filePath,
                                      line: UInt = #line) {
        let rebuilt = LabelTemplate.rebuild(from: record)
        XCTAssertEqual(rebuilt.title, original.title, "标题 —— \(message)", file: file, line: line)
        XCTAssertEqual(rebuilt.rows.map(\.label), original.rows.map(\.label),
                       "行标签 —— \(message)", file: file, line: line)
        XCTAssertEqual(rebuilt.rows.map(\.value), original.rows.map(\.value),
                       "行内容 —— \(message)", file: file, line: line)
        XCTAssertEqual(rebuilt.maker, original.maker, "制作人 —— \(message)", file: file, line: line)
        XCTAssertEqual(rebuilt.rightText, original.rightText, "右黑条 —— \(message)", file: file, line: line)
        // ★ 最关键的一条：二维码原文一致 = 重打后按 qrText 去重能合并回同一条记录，
        //   而且康普茶二发扫这张码还能正常续做。
        XCTAssertEqual(rebuilt.qrText, original.qrText, "二维码原文 —— \(message)", file: file, line: line)
        XCTAssertEqual(rebuilt.qrText, record.qrText, "二维码原文 vs 记录 —— \(message)",
                       file: file, line: line)
    }

    func testRebuildGenericMatchesOriginalLabel() {
        let expire = d(2026, 10, 12)
        let best = d(2026, 10, 15)
        let data = LabelTemplate.buildGeneric(title: "巴旦木奶", now: now,
                                              expireDate: expire, bestBefore: best, maker: "四野")
        let record = LabelTemplate.makeRecord(kind: .generic, data: data, createdAt: now,
                                              expireAt: expire, bestBefore: best, maker: "四野")
        assertRebuildMatches(record, data, "通用效期")
    }

    func testRebuildDairyMatchesOriginalLabel() {
        // ★ 用「超过 7 天阈值」的日期：那一档会走 23:59 的分支，
        //   如果 rebuild 里的 now 传错，这里立刻会红。
        let expire = d(2026, 11, 22)
        let best = d(2026, 11, 15)
        let data = LabelTemplate.buildDairy(kindLabel: "燕麦奶", now: now,
                                            expireDate: expire, bestBefore: best, maker: "四野")
        let record = LabelTemplate.makeRecord(kind: .dairy, data: data, createdAt: now,
                                              expireAt: expire, bestBefore: best, maker: "四野")
        assertRebuildMatches(record, data, "奶制品")
    }

    func testRebuildKombuchaFirstMatchesOriginalLabel() {
        let data = LabelTemplate.buildKombuchaFirst(variety: "红茶", now: now, maker: "四野")
        let record = LabelTemplate.makeRecord(kind: .kombucha, data: data, createdAt: now,
                                              expireAt: day(LabelTemplate.kombuchaDoneDays),
                                              bestBefore: day(LabelTemplate.kombuchaBestDays),
                                              maker: "四野")
        assertRebuildMatches(record, data, "康普茶一发")
    }

    func testRebuildKombuchaSecondMatchesOriginalLabel() {
        // ★ 二发是「最佳使用时间沿用一发」的那种，**不能**用 now + 30 重建 ——
        //   如果哪天有人把 rebuild 改回调 builder，这条会红。
        let firstBest = d(2026, 10, 20)
        let data = LabelTemplate.buildKombuchaSecond(firstTitle: "康普茶-红茶", fruit: "草莓",
                                                     now: now, firstBestBefore: firstBest,
                                                     maker: "四野")
        let record = LabelTemplate.makeRecord(
            kind: .kombucha, data: data, createdAt: now,
            expireAt: LabelTemplate.kombuchaSecondDone(after: now),
            bestBefore: firstBest, maker: "四野")
        assertRebuildMatches(record, data, "康普茶二发")
    }

    // MARK: - 到期日 = 最佳使用时间（康普茶不早于完成时间）

    func testGenericDueDateIsBestBefore() {
        let data = LabelTemplate.buildGeneric(title: "牛奶", now: now,
                                              expireDate: day(7), bestBefore: day(3), maker: "四野")
        let record = LabelTemplate.makeRecord(kind: .generic, data: data, createdAt: now,
                                              expireAt: day(7), bestBefore: day(3), maker: "四野")
        XCTAssertEqual(record.dueDate, day(3))
        XCTAssertEqual(record.dueLabel, "最佳使用")
    }

    func testKombuchaFirstDueDateIsBestBefore() {
        let data = LabelTemplate.buildKombuchaFirst(variety: "红茶", now: now, maker: "四野")
        let record = LabelTemplate.makeRecord(kind: .kombucha, data: data, createdAt: now,
                                              expireAt: day(7), bestBefore: day(30), maker: "四野")
        XCTAssertEqual(record.dueDate, day(30))
        XCTAssertEqual(record.dueLabel, "最佳使用")
    }

    func testKombuchaSecondDueDateNeverEarlierThanFinish() {
        // 一发已经放了 29 天，最佳使用只剩 1 天；二发完成还要 3 天。
        // 此时「最佳使用时间」早于「完成时间」—— 不能判成已过期。
        let firstBest = day(1)
        let done = LabelTemplate.kombuchaSecondDone(after: now)
        let data = LabelTemplate.buildKombuchaSecond(firstTitle: "康普茶-红茶", fruit: "草莓",
                                                     now: now, firstBestBefore: firstBest,
                                                     maker: "四野")
        let record = LabelTemplate.makeRecord(kind: .kombucha, data: data, createdAt: now,
                                              expireAt: done, bestBefore: firstBest, maker: "四野")
        XCTAssertEqual(record.dueDate, done, "到期日不能早于完成时间")
        XCTAssertEqual(record.dueLabel, "完成")
    }

    // MARK: - 提醒覆盖两个里程碑

    private func makeRecord(kind: LabelKind, expireAt: Date, bestBefore: Date) -> LabelRecord {
        LabelRecord(title: kind == .kombucha ? "康普茶-红茶" : "牛奶",
                    kind: kind,
                    maker: "四野",
                    createdAt: now,
                    printedAt: now,
                    expireAt: expireAt,
                    bestBefore: bestBefore,
                    usedAt: nil,
                    qrText: "test",
                    source: .printed)
    }

    func testGenericHasBothMilestones() {
        let expire = day(20)
        let best = day(15)
        let milestones = ExpiryStore.milestones(of: makeRecord(kind: .generic,
                                                                expireAt: expire,
                                                                bestBefore: best))
        XCTAssertEqual(milestones.count, 2, "最佳使用时间 + 原始保质期，两个都要提醒")
        // 下标顺序是通知 identifier 的计算依据，不能变。
        XCTAssertEqual(milestones[0].date, expire)
        XCTAssertEqual(milestones[1].date, best)
        XCTAssertTrue(milestones[0].todayTitle.contains("原始保质期"))
        XCTAssertTrue(milestones[1].todayTitle.contains("最佳使用时间"))
        XCTAssertFalse(milestones[0].tomorrowTitle.isEmpty)
        XCTAssertFalse(milestones[1].tomorrowBody.isEmpty)
    }

    func testDairyHasBothMilestones() {
        let milestones = ExpiryStore.milestones(of: makeRecord(kind: .dairy,
                                                                expireAt: day(45),
                                                                bestBefore: day(5)))
        XCTAssertEqual(milestones.count, 2)
        XCTAssertEqual(milestones[0].date, day(45))
        XCTAssertEqual(milestones[1].date, day(5))
    }

    func testKombuchaSecondGroupIsFinishTimeNotShelfLife() {
        // 康普茶没有原始保质期：第二组时间是「完成时间」= 可以喝 / 可以做二发。
        let milestones = ExpiryStore.milestones(of: makeRecord(kind: .kombucha,
                                                                expireAt: day(3),
                                                                bestBefore: day(20)))
        XCTAssertEqual(milestones.count, 2)
        XCTAssertEqual(milestones[0].date, day(3))
        let text = milestones[0].todayTitle + milestones[0].todayBody
            + milestones[0].tomorrowTitle + milestones[0].tomorrowBody
        XCTAssertTrue(text.contains("完成"), "第二组提醒要按「完成时间」的语义出：\(text)")
        XCTAssertTrue(text.contains("饮用") || text.contains("二发"),
                      "要告诉用户这时候能喝 / 能做二发：\(text)")
        XCTAssertFalse(text.contains("原始保质期"), "康普茶不该出现「原始保质期」：\(text)")
    }
}
