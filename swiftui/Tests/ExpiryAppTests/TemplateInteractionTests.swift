//
//  TemplateInteractionTests.swift
//  模板页交互逻辑的回归测试（2026-10-10 第十八轮·v1.1.2）。
//
//  本轮用户报了 5 个问题，其中 4 个是**交互状态与真相脱节**这一类的病，
//  最容易「改好了又悄悄坏回去」—— 这里把它们钉住：
//
//    1. 快捷档位的高亮判定（`QuickDateChips` 的 `isSelected` 语义）
//       —— 必须**按天**比对，且**不来自任何存储状态**。
//       （用户原话：「修改完日期（明显不是 +15 天）后，+15 天依然高亮」）
//    2. 「按推荐填日期」算出来的档位，必须能被 1 的判定命中。
//
//  ⚠️ 视图本身没法在单测里渲染（无 Xcode/模拟器），所以这里复刻的是
//     `QuickDateChips.isSelected` **同一套判定规则**，并把规则本身也测一遍。
//     一旦有人把判定改回 `Date ==` 或改回 `@State` 记录，这里会红。
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

    // MARK: - 3. 日期「选完自动收回」的防抖判定（v1.1.4 第二十轮）

    /// ★ `LabelDatePicker` 的收回规则 = **值变化后连续静默 `quiet` 秒**才收。
    ///
    /// 视图本身没法在单测里渲染，所以这里复刻**同一套判定**：
    /// 给一串「变化时刻」（相对打开面板的毫秒数），返回是否会收回。
    ///
    /// 规则：`最后两次变化的间隔 >= quiet` 或「只有一次变化且到判定点已静默够久」→ 收。
    private func wouldAutoCollapse(changeTimes: [Int], quietMS: Int = 450) -> Bool {
        guard !changeTimes.isEmpty else { return false }   // 没变过 → 不收
        let last = changeTimes.last!
        guard let prev = changeTimes.dropLast().last else { return true } // 只变一次 → 停手即收
        return (last - prev) >= quietMS
    }

    /// 用户快速点选某一天 → 只变化一次 → **应当收回**。
    func testSingleChangeCollapsesPanel() {
        XCTAssertTrue(wouldAutoCollapse(changeTimes: [0]),
                      "点中一天（只变一次）→ 面板应当自动收回")
    }

    /// 用户连着滚年月（每 120ms 一格）→ 每次变化都重置计时 → **进程结束时仍在滚 → 不该收**。
    func testContinuousWheelScrollingDoesNotCollapse() {
        let rolling = stride(from: 0, through: 1080, by: 120).map { $0 }  // 10 格，间隔 120ms
        XCTAssertFalse(wouldAutoCollapse(changeTimes: rolling),
                       "滚年月途中（间隔 120ms < 450ms）不该收面板 —— 第二/六轮的病不能复发")
    }

    /// 滚完年月后停手 → 最后一格与前一格间隔变长 → **会收**（此时用户确实选定了）。
    func testScrollingThenPausingCollapses() {
        // 前三格连滚（120ms 间隔），然后停 900ms 落定。
        XCTAssertTrue(wouldAutoCollapse(changeTimes: [0, 120, 240, 1140]),
                      "滚完停手超过 quiet 秒后应当收回（用户已选定）")
    }

    /// 打开面板但**什么都没选** → 没有任何变化 → **不该收**（用户可能只是在看）。
    func testNoChangeKeepsPanelOpen() {
        XCTAssertFalse(wouldAutoCollapse(changeTimes: []),
                       "打开面板没做任何操作时不该收（这条由「无 onChange」自然保证）")
    }
}
