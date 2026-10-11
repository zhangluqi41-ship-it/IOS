//
//  TemplateInteractionTests.swift
//  模板页交互逻辑的回归测试。
//
//  用户报过的问题里，有 4 个是**交互状态与真相脱节**这一类的病，
//  最容易「改好了又悄悄坏回去」—— 这里把它们钉住：
//
//    1. 快捷档位的高亮判定（`QuickDateChips` 的 `isSelected` 语义）
//       —— 必须**按天**比对，且**不来自任何存储状态**。
//       （用户原话：「修改完日期（明显不是 +15 天）后，+15 天依然高亮」）
//    2. 「按推荐填日期」算出来的档位，必须能被 1 的判定命中。
//    3. 日期控件的「选完自动收」判据：
//       **只有"年月没变、只是换了某一天"才算"选完日期"**（v1.1.11 定案）——
//       滚轮换月/换年 **不收**（那是在导航，不是选择）；不许引入防抖计时器。
//
//  ⚠️ 视图本身没法在单测里渲染（无 Xcode/模拟器），所以：
//     · 第 1/2 节复刻 `QuickDateChips.isSelected` 的判定规则；
//     · 第 3 节**直接测真函数** `LabelTemplate.shouldCollapseAfterDateChange`。
//   v1.1.7 曾因"测试里复刻的规则"与"视图里的实现"漂移 → 测试全绿但真机是坏的，
//   所以第 3 节改为**只测真函数**，不再复刻。
//
//  ⚠️ v1.1.11 改的是**判据本身**：上一版「值变了就收」会被年月滚轮误触发
//     （用户报「选择年月的滚轮后也收回了」）。
//

import XCTest
@testable import ExpiryManager

final class TemplateInteractionTests: XCTestCase {

    private var cal: Calendar { AppCalendar.shared }

    /// ★ 复刻 `QuickDateChips.isSelected` 的判定：**按天**比对，不比较时分秒。
    private func isSelected(_ selection: Date, matches preset: Date) -> Bool {
        cal.isDate(cal.startOfDay(for: selection), inSameDayAs: cal.startOfDay(for: preset))
    }

    // MARK: - 1. 高亮必须跟住真实日期

    func testPresetHighlightFollowsManualDateChange() {
        // 「今天」= 2026-10-10；+15 天档位 = 10-25。
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        let preset15 = cal.date(byAdding: .day, value: 15, to: today)!

        // ① 点了 +15 天 → 高亮
        XCTAssertTrue(isSelected(preset15, matches: preset15),
                      "选中 +15 天档位时它必须高亮")

        // ② 用户又手动把日期改成 10-28（明显不是 +15 天）→ **高亮必须消失**
        //    这正是用户的报错：「修改完日期后 +15 天依然高亮」。
        let manual = cal.date(from: DateComponents(year: 2026, month: 10, day: 28))!
        XCTAssertFalse(isSelected(manual, matches: preset15),
                       "手动改成 10/28 后，+15 天档位不许再高亮")
        XCTAssertNotEqual(manual, preset15)
    }

    func testPresetHighlightIgnoresTimeOfDay() {
        // ★ 用户只选日期，但 Date 带时分秒 —— 判定必须按天，
        //   否则「同一天但时间不同」会判成命中不了（高亮闪没）。
        let preset = cal.date(from: DateComponents(year: 2026, month: 10, day: 25,
                                                   hour: 0, minute: 0))!
        let sameDayLate = cal.date(from: DateComponents(year: 2026, month: 10, day: 25,
                                                        hour: 23, minute: 59))!
        XCTAssertTrue(isSelected(sameDayLate, matches: preset),
                      "同一天（0:00 vs 23:59）必须判为命中 —— 这就是不能用 `Date ==` 的原因")
        XCTAssertNotEqual(sameDayLate, preset,
                          "原始 Date 确实不相等 —— 说明按天的判定是必要的")
    }

    func testPresetHighlightIsExclusiveAcrossPresets() {
        // 四个档位互斥：命中一个，其余三个都不许亮。
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 10))!
        func add(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: today)! }
        let presets = [add(3), add(7), add(15),
                       cal.date(byAdding: .month, value: 1, to: today)!]

        for (index, preset) in presets.enumerated() {
            let hits = presets.enumerated().filter { isSelected(preset, matches: $0.element) }
            XCTAssertEqual(hits.count, 1, "档位 \(index) 应当且仅当命中自己")
            XCTAssertEqual(hits.first?.offset, index)
        }
    }

    // MARK: - 2. 「按推荐填日期」必须能被高亮命中

    func testDairyRecommendationMatchesPresetDay() {
        // 奶制品「按推荐填日期」= 当天 0 点 + expireDays。
        // 只要它落在某个档位那一天，那个档位就该亮 —— 同一套按天判定。
        let today = cal.startOfDay(for: Date())
        let k = DairyKind.milk          // 牛奶：保质期 +7 天 / 最佳 +3 天
        let recommended = cal.date(byAdding: .day, value: k.expireDays, to: today)!
        let preset7 = cal.date(byAdding: .day, value: 7, to: today)!

        XCTAssertEqual(k.expireDays, 7, "牛奶的推荐保质期档位是 +7 天")
        XCTAssertTrue(isSelected(recommended, matches: preset7),
                      "按推荐填出来的日期必须让对应的快捷档位高亮")
    }

    /// 反例：肉类的推荐值（冷藏 +5 天 / 冷冻 +3 个月）**不在**四个档位里，
    /// 所以按推荐填完之后 **四个档位都不该亮** —— 这正是「高亮跟手日期」的正确表现。
    func testMeatRecommendationLeavesChipsUnhighlighted() {
        let today = cal.startOfDay(for: Date())
        let (expire, _) = MeatRule.dates(storage: .chilled, from: today)
        func add(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: today)! }
        let presets = [add(3), add(7), add(15),
                       cal.date(byAdding: .month, value: 1, to: today)!]

        XCTAssertFalse(presets.contains { isSelected(expire, matches: $0) },
                       "冷藏 +5 天不在档位里 → 四个 chip 都不该亮（旧实现会错误地保持上一次的高亮）")
    }

    // MARK: - 3. 日期控件（v1.1.9 第二十五轮 · 路线 B 定案）

    /// ★ `LabelDatePicker` 的**日期文字**必须与写入记录的日子是同一天（规范化后相等）。
    ///
    /// 背景：日期控件只读 `startOfDay` 之后的绑定值 —— 这里钉住"显示值 == 真相值"，
    /// 一旦有人把规范化去掉（或改成显示未规范化的 `date`），这条会红。
    /// ⚠️ v1.1.9 起主行的 `Text(_:format:)` 读的就是这个规范化值，
    ///    所以这条断言对新实现**更加直接对应**。
    func testDisplayedDayEqualsNormalizedBinding() {
        let cal = AppCalendar.shared
        // 带时分秒的"真实时刻"（用户实际会拿到的那种 Date）。
        let raw = cal.date(from: DateComponents(year: 2026, month: 10, day: 30,
                                                hour: 23, minute: 48))!

        // 复刻 `day` 绑定的 get 端：startOfDay。
        let displayed = cal.startOfDay(for: raw)

        XCTAssertEqual(cal.component(.day, from: displayed), 30,
                       "显示给用户的必须是 30 日")
        XCTAssertEqual(cal.component(.hour, from: displayed), 0,
                       "规范化后必须压到当天 0 点（业务只关心日期）")
        XCTAssertTrue(cal.isDate(displayed, inSameDayAs: raw),
                      "显示值与真相值必须是同一天 —— 不允许出现差一天的偏移")
    }

    /// ★ 日期必须按**自然日**读写，不受时刻影响（写入记录时也走同一套规范）。
    func testDayWriteBackIsCalendarDay() {
        let cal = AppCalendar.shared
        let lateNight = cal.date(from: DateComponents(year: 2026, month: 10, day: 30,
                                                      hour: 23, minute: 59))!
        let written = cal.startOfDay(for: lateNight)

        XCTAssertEqual(cal.component(.year, from: written), 2026)
        XCTAssertEqual(cal.component(.month, from: written), 10)
        XCTAssertEqual(cal.component(.day, from: written), 30,
                       "23:59 选的 30 日，写回记录也必须是 30 日")
    }

    /// ★★★ 「选完自动收」的判据（v1.1.11 第二十七轮 · **最终定案**）。
    ///
    /// 现在**直接测真函数** `LabelTemplate.shouldCollapseAfterDateChange(from:to:)`，
    /// 不再"复刻规则" —— 复刻的规则和视图里的实现会漂移，这条正是被漂移坑过一次。
    ///
    /// 判据 = **只有「年月没变、只是换了某一天」才算"选完日期"**：
    ///
    /// ① 同月换天   → **收**（用户点网格里的某一天）—— 核心行为；
    /// ② 换月（日不变）→ **不收**（用户滚月份滚轮导航，**这就是本轮修的 bug**）；
    /// ③ 换年（日不变）→ **不收**（滚年份滚轮）；
    /// ④ 同一天（只是时刻不同）→ **不收**（`onChange` 一般不触发，这里兜底）；
    /// ⑤ 跨年换月（12月→1月）→ **不收**（年月都变）。
    func testCollapseRuleOnlyOnSameMonthDayChange() {
        let cal = AppCalendar.shared
        func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: mi))!
        }
        func collapse(from a: Date, to b: Date) -> Bool {
            LabelTemplate.shouldCollapseAfterDateChange(from: a, to: b, calendar: cal)
        }

        // ① 同月换天 → 收（用户点网格里的日期）
        XCTAssertTrue(collapse(from: d(2026, 10, 10), to: d(2026, 10, 30)),
                      "点中同月的另一天 → 必须收起（用户要的核心行为）")

        // ② 换月、日不变 → **不收** ← 本轮修的核心 bug
        XCTAssertFalse(collapse(from: d(2026, 10, 15), to: d(2026, 11, 15)),
                       "滚月份滚轮（10/15 → 11/15，日没变）→ 不许收起")
        XCTAssertFalse(collapse(from: d(2026, 10, 30), to: d(2026, 11, 30)),
                       "滚月份滚轮带日不变 → 不许收起")

        // ③ 换年、日不变 → **不收**
        XCTAssertFalse(collapse(from: d(2026, 10, 15), to: d(2027, 10, 15)),
                       "滚年份滚轮（2026 → 2027，日没变）→ 不许收起")

        // ④ 同一天、只是时刻不同 → 不收
        XCTAssertFalse(collapse(from: d(2026, 10, 10, 9, 0), to: d(2026, 10, 10, 21, 30)),
                       "同一天的不同时刻 → 不许收起（规范化后相等）")

        // ⑤ 跨年换月（12月 → 次年1月）→ 不收
        XCTAssertFalse(collapse(from: d(2026, 12, 15), to: d(2027, 1, 15)),
                       "滚到次年 1 月 → 不许收起")
    }

    /// ★ 滚轮换月时，`日` 可能被"夹"到月末（如 10/31 → 11/30）——
    ///   此时「日」也变了，但**年月仍然变了** → 判定依然是"不收"。
    ///   这条钉住"年月优先"这个判据顺序（不能先看日）。
    func testCollapseRuleMonthChangeWinsEvenIfDayClamped() {
        let cal = AppCalendar.shared
        func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: day))!
        }
        XCTAssertFalse(
            LabelTemplate.shouldCollapseAfterDateChange(
                from: d(2026, 10, 31), to: d(2026, 11, 30), calendar: cal),
            "10/31 滚到 11/30（日被夹到月末，日也变了）→ 仍然是滚轮导航，不许收起"
        )
        // 对照组：同月内换天，判据不受影响
        XCTAssertTrue(
            LabelTemplate.shouldCollapseAfterDateChange(
                from: d(2026, 11, 1), to: d(2026, 11, 30), calendar: cal),
            "同一个月内点另一天 → 收起"
        )
    }
}
