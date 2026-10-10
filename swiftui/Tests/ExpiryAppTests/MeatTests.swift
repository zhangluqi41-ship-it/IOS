//
//  MeatTests.swift
//  肉类模板 + 解冻流程的回归测试（2026-10-09 优化清单「一、模板二级菜单」第 4 条）。
//
//  重点钉住四件事：
//    1. 规则数值：冷藏两个日期都 +5 天；冷冻都 +3 个月；解冻后完成 +1 天、最佳 +3 天；
//    2. 部位清单与用户给的原文**逐字一致**（少一个 / 多一个都会红）；
//    3. 二维码闭环：自己印的码必须能自己解析回来，并且**扫冷冻码 = 解冻、
//       扫解冻码 = 不再解冻、扫冷藏码 = 只入库**；
//    4. 「重新打印」对肉类 / 解冻标签也必须逐字一致（解冻标签是
//       「解冻时间 / 完成时间 / 最佳使用时间」—— 靠标题前缀反推）。
//

import XCTest
@testable import ExpiryManager

final class MeatTests: XCTestCase {

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 15, _ mi: Int = 30) -> Date {
        AppCalendar.shared.date(from: DateComponents(year: y, month: m, day: day,
                                                     hour: h, minute: mi))!
    }

    private var now: Date { d(2026, 10, 8, 12, 0) }

    private func day(_ n: Int, from base: Date? = nil) -> Date {
        AppCalendar.shared.date(byAdding: .day, value: n, to: base ?? now)!
    }

    private func month(_ n: Int, from base: Date? = nil) -> Date {
        AppCalendar.shared.date(byAdding: .month, value: n, to: base ?? now)!
    }

    // MARK: - 规则数值

    func testChilledDatesAreBothPlus5Days() {
        let (expire, best) = MeatRule.dates(storage: .chilled, from: now)
        // 规则从「当天 0 点」起算，避免同一张标签因下半天打印而差一天。
        XCTAssertEqual(expire, AppCalendar.shared.date(byAdding: .day, value: 5,
                                                       to: AppCalendar.shared.startOfDay(for: now)))
        XCTAssertEqual(best, expire, "冷藏的原始保质期与最佳使用时间都 +5 天，两者相同")
    }

    func testFrozenDatesAreBothPlus3Months() {
        let (expire, best) = MeatRule.dates(storage: .frozen, from: now)
        XCTAssertEqual(expire, AppCalendar.shared.date(byAdding: .month, value: 3,
                                                       to: AppCalendar.shared.startOfDay(for: now)))
        XCTAssertEqual(best, expire, "冷冻的两个日期都 +3 个月，两者相同")
    }

    func testThawedBestIsPlus3Days() {
        XCTAssertEqual(MeatRule.thawedBest(from: now), day(3))
    }

    /// 2026-10-10 第十五轮：解冻的「完成时间」= 解冻那一刻 + 1 天。
    func testThawedCompleteIsPlus1Day() {
        XCTAssertEqual(MeatRule.thawedComplete(from: now), day(1))
    }

    // MARK: - 部位清单（照抄用户原文，逐字比对）

    func testAnimalCutsMatchSpec() {
        XCTAssertEqual(MeatAnimal.chicken.cuts, ["鸡胸", "鸡腿"])
        XCTAssertEqual(MeatAnimal.pork.cuts,
                       ["梅花肉", "五花肉", "后腿肉", "排骨", "筒骨", "猪颈肉"])
        XCTAssertEqual(MeatAnimal.beef.cuts,
                       ["牛腩", "牛肋条", "牛腱", "菲力（里脊）", "眼肉",
                        "西冷（外脊）", "板腱", "上脑"])
        XCTAssertEqual(MeatAnimal.lamb.cuts,
                       ["上脑", "里脊", "羊肋排", "羊前腿", "羊后腿", "羊腩", "羊腱子"])
    }

    func testTitleCarriesStoragePrefix() {
        XCTAssertEqual(MeatRule.title(storage: .frozen, animal: .beef, cut: "眼肉"),
                       "冷冻-牛肉-眼肉")
        XCTAssertEqual(MeatRule.title(storage: .chilled, animal: .pork, cut: "五花肉"),
                       "冷藏-猪肉-五花肉")
        XCTAssertEqual(MeatRule.thawTitle(baseName: "牛肉-眼肉"), "解冻-牛肉-眼肉")
    }

    // MARK: - 二维码闭环

    func testFrozenLabelQrRoundTrip() {
        let expire = month(3)
        let data = LabelTemplate.buildMeat(animal: .beef, cut: "眼肉", storage: .frozen,
                                           now: now, expireDate: expire, bestBefore: expire,
                                           maker: "四野")
        XCTAssertEqual(data.title, "冷冻-牛肉-眼肉")

        let parsed = LabelTemplate.parseMeatQr(data.qrText)
        XCTAssertNotNil(parsed, "自己印的肉类码必须能自己解析回来：\(data.qrText)")
        XCTAssertEqual(parsed?.storage, MeatStorage.frozen)
        XCTAssertEqual(parsed?.alreadyThawed, false)
        XCTAssertEqual(parsed?.baseName, "牛肉-眼肉")
        XCTAssertEqual(parsed?.title, "冷冻-牛肉-眼肉")
        // ★ 原始保质期那一行的**原文**必须原样带回来（解冻时要照搬）。
        XCTAssertEqual(parsed?.expireRaw, LabelTemplate.fmtDateByThreshold(now, expire))
    }

    func testChilledLabelQrRoundTrip() {
        let expire = day(5)
        let data = LabelTemplate.buildMeat(animal: .chicken, cut: "鸡腿", storage: .chilled,
                                           now: now, expireDate: expire, bestBefore: expire,
                                           maker: "四野")
        let parsed = LabelTemplate.parseMeatQr(data.qrText)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.storage, MeatStorage.chilled)
        XCTAssertEqual(parsed?.alreadyThawed, false, "冷藏标签不是「已解冻」")
        XCTAssertEqual(parsed?.baseName, "鸡肉-鸡腿")
    }

    /// 解冻标签再被扫：必须认得出「已经解冻过」，否则会无限套娃。
    func testThawLabelQrIsMarkedAlreadyThawed() {
        let stamp = d(2026, 10, 9, 10, 0)
        let data = LabelTemplate.buildMeatThaw(baseName: "牛肉-眼肉", now: stamp, maker: "四野")
        XCTAssertEqual(data.title, "解冻-牛肉-眼肉")
        XCTAssertEqual(data.rows[0].label, "解冻时间：", "解冻标签第一行要改成「解冻时间」")
        // ★ 2026-10-10 第十五轮：第二行由「原始保质期」改成「完成时间 = 解冻 + 1 天」。
        XCTAssertEqual(data.rows[1].label, "完成时间：", "解冻标签第二行要改成「完成时间」")
        XCTAssertEqual(data.rows[1].value,
                       LabelTemplate.fmtDateByThreshold(stamp, MeatRule.thawedComplete(from: stamp)),
                       "完成时间 = 解冻时间 + 1 天")
        XCTAssertEqual(data.rows[2].label, "最佳使用时间：")

        let parsed = LabelTemplate.parseMeatQr(data.qrText)
        XCTAssertNotNil(parsed, "解冻标签（第二行是「完成时间」）自己印的码必须仍能解析：\(data.qrText)")
        XCTAssertEqual(parsed?.alreadyThawed, true)
        XCTAssertEqual(parsed?.baseName, "牛肉-眼肉", "解冻标签的 baseName 要去掉「解冻-」前缀")
    }

    /// ★ 存量旧解冻标签（第二行仍是「原始保质期」）也必须还能扫得出来。
    func testLegacyThawLabelQrStillParses() {
        let raw = "解冻-牛肉-眼肉原始保质期：2027/01/08 23:59最佳使用时间：2026/10/12 10:00"
        let parsed = LabelTemplate.parseMeatQr(raw)
        XCTAssertNotNil(parsed, "旧格式（「原始保质期」锚点）的解冻标签要继续可解析")
        XCTAssertEqual(parsed?.alreadyThawed, true)
        XCTAssertEqual(parsed?.baseName, "牛肉-眼肉")
    }

    func testParseMeatQrRejectsNonMeat() {
        // 奶制品 / 通用：版式一样、但没有保存类型前缀 → 不是肉类标签
        XCTAssertNil(LabelTemplate.parseMeatQr(
            "燕麦奶原始保质期：2026/11/22 23:59最佳使用时间：2026/11/15 23:59"))
        // 康普茶：没有「原始保质期」
        XCTAssertNil(LabelTemplate.parseMeatQr(
            "康普茶-红茶完成时间：2026/10/12 15:30最佳使用时间：2026/11/04 15:30"))
        // 前缀不对
        XCTAssertNil(LabelTemplate.parseMeatQr(
            "急冻-牛肉-眼肉原始保质期：2026/11/22 23:59最佳使用时间：2026/11/15 23:59"))
        // 乱码
        XCTAssertNil(LabelTemplate.parseMeatQr("随便一段文字"))
        XCTAssertNil(LabelTemplate.parseMeatQr(""))
    }

    /// 肉类码不能被康普茶解析器吃掉（扫码页是先试康普茶、再试肉类）。
    func testMeatQrIsNotParsedAsKombucha() {
        let expire = month(3)
        let data = LabelTemplate.buildMeat(animal: .lamb, cut: "羊腩", storage: .frozen,
                                           now: now, expireDate: expire, bestBefore: expire,
                                           maker: "四野")
        XCTAssertNil(LabelTemplate.parseKombuchaQr(data.qrText))
    }

    /// 反过来：康普茶码也不能被肉类解析器吃掉。
    func testKombuchaQrIsNotParsedAsMeat() {
        let data = LabelTemplate.buildKombuchaFirst(variety: "红茶", now: now, maker: "四野")
        XCTAssertNil(LabelTemplate.parseMeatQr(data.qrText))
    }

    // MARK: - 重新打印（rebuild）对肉类也必须逐字一致

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
        XCTAssertEqual(rebuilt.rightText, original.rightText,
                       "右黑条 —— \(message)", file: file, line: line)
        XCTAssertEqual(rebuilt.qrText, original.qrText,
                       "二维码原文 —— \(message)", file: file, line: line)
        XCTAssertEqual(rebuilt.qrText, record.qrText,
                       "二维码原文 vs 记录 —— \(message)", file: file, line: line)
    }

    func testRebuildFrozenMeatMatchesOriginal() {
        // ★ 用「超过 7 天阈值」的日期：原始保质期那一行走 23:59 分支，
        //   如果 rebuild 里的 now 传错，这里立刻会红。
        let expire = month(3)
        let data = LabelTemplate.buildMeat(animal: .beef, cut: "西冷（外脊）", storage: .frozen,
                                           now: now, expireDate: expire, bestBefore: expire,
                                           maker: "四野")
        let record = LabelTemplate.makeRecord(kind: .meat, data: data, createdAt: now,
                                              expireAt: expire, bestBefore: expire,
                                              maker: "四野")
        assertRebuildMatches(record, data, "冷冻肉类")
    }

    func testRebuildChilledMeatMatchesOriginal() {
        let expire = day(5)
        let data = LabelTemplate.buildMeat(animal: .pork, cut: "五花肉", storage: .chilled,
                                           now: now, expireDate: expire, bestBefore: expire,
                                           maker: "四野")
        let record = LabelTemplate.makeRecord(kind: .meat, data: data, createdAt: now,
                                              expireAt: expire, bestBefore: expire,
                                              maker: "四野")
        assertRebuildMatches(record, data, "冷藏肉类")
    }

    func testRebuildThawLabelKeepsThawTimeRow() {
        let stamp = d(2026, 10, 9, 10, 0)
        // 记录里仍存冷冻标签的「原始保质期」当 expireAt —— 它只服务于提醒，
        // 不参与标签第二行的排版（第二行按 createdAt 现算「完成时间」）。
        let expireAt = d(2027, 1, 8, 23, 59)
        let best = MeatRule.thawedBest(from: stamp)
        let data = LabelTemplate.buildMeatThaw(baseName: "牛肉-眼肉", now: stamp, maker: "四野")
        let record = LabelTemplate.makeRecord(kind: .meat, data: data, createdAt: stamp,
                                              expireAt: expireAt, bestBefore: best,
                                              maker: "四野")
        assertRebuildMatches(record, data, "解冻标签")
        let rebuilt = LabelTemplate.rebuild(from: record)
        XCTAssertEqual(rebuilt.rows[0].label, "解冻时间：",
                       "解冻标签重打时第一行必须还是「解冻时间」，不能变成「开封时间」")
        XCTAssertEqual(rebuilt.rows[1].label, "完成时间：",
                       "解冻标签重打时第二行必须还是「完成时间」")
    }

    // MARK: - 到期提醒

    private func makeMeatRecord(expireAt: Date, bestBefore: Date) -> LabelRecord {
        LabelRecord(title: "冷冻-牛肉-眼肉",
                    kind: .meat,
                    maker: "四野",
                    createdAt: now,
                    printedAt: now,
                    expireAt: expireAt,
                    bestBefore: bestBefore,
                    usedAt: nil,
                    qrText: "test",
                    source: .printed)
    }

    /// ★ 肉类两个日期按规则相同 → 提醒要去重成一条，否则同一时刻会收到两条几乎一样的通知。
    func testMeatMilestonesDedupeWhenDatesEqual() {
        let same = day(5)
        let milestones = ExpiryStore.milestones(of: makeMeatRecord(expireAt: same,
                                                                   bestBefore: same))
        XCTAssertEqual(milestones.count, 1, "两个日期相同就只提醒一次")
        XCTAssertEqual(milestones[0].date, same)
        XCTAssertEqual(milestones[0].label, "原始保质期")
        XCTAssertTrue(milestones[0].todayTitle.contains("原始保质期"))
    }

    /// 用户手动改掉其中一个日期时，两条都要提醒（与通用模板一致）。
    func testMeatMilestonesKeepsBothWhenDatesDiffer() {
        let milestones = ExpiryStore.milestones(of: makeMeatRecord(expireAt: day(30),
                                                                   bestBefore: day(5)))
        XCTAssertEqual(milestones.count, 2)
        XCTAssertEqual(milestones[0].date, day(30))
        XCTAssertEqual(milestones[1].date, day(5))
    }

    /// 五档提醒都要有文案（前一天 / 当天 / 提前 1 小时 / 到时间）。
    func testMilestoneHasAllFiveTiers() {
        let milestones = ExpiryStore.milestones(of: makeMeatRecord(expireAt: day(30),
                                                                   bestBefore: day(5)))
        for m in milestones {
            XCTAssertFalse(m.label.isEmpty)
            XCTAssertFalse(m.tomorrowTitle.isEmpty)
            XCTAssertFalse(m.tomorrowBody.isEmpty)
            XCTAssertFalse(m.todayTitle.isEmpty)
            XCTAssertFalse(m.todayBody.isEmpty)
            XCTAssertFalse(m.soonTitle.isEmpty)
            XCTAssertFalse(m.soonBody.isEmpty)
            XCTAssertFalse(m.dueTitle.isEmpty)
            XCTAssertFalse(m.dueBody.isEmpty)
        }
    }

    // MARK: - 扫码路由判据

    /// 「只有冷冻 + 未解冻」才进解冻流程 —— 这是扫码页 `handleMeat` 的判据，
    /// 用纯数据的角度把它钉住（UI 层没法单测）。
    func testOnlyFrozenUnthawedEntersThawFlow() {
        func shouldThaw(_ storage: MeatStorage, _ alreadyThawed: Bool) -> Bool {
            storage.isFrozen && !alreadyThawed
        }
        XCTAssertTrue(shouldThaw(.frozen, false), "冷冻 + 未解冻 → 进解冻")
        XCTAssertFalse(shouldThaw(.frozen, true), "解冻标签再扫 → 不再解冻（防套娃）")
        XCTAssertFalse(shouldThaw(.chilled, false), "冷藏肉不需要解冻")
    }
}
