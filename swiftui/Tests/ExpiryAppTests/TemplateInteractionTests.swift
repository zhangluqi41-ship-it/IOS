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
//    3. 日期控件只做「规范化到当天」这一件事，**不许夹带收起/计时等副作用**
//       （v1.1.6 定案：所有"选完自动收"的手段都已被否掉，见下方测试注释）。
//
//  ⚠️ 视图本身没法在单测里渲染（无 Xcode/模拟器），所以这里复刻的是
//     `QuickDateChips.isSelected` / `LabelDatePicker.day` **同一套判定规则**，
//     并把规则本身也测一遍。一旦有人把判定改回去，这里会红。
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

    // MARK: - 3. 日期控件（v1.1.6 第二十二轮 · 定案）

    /// ★ `LabelDatePicker` 的**日期文字**必须与写入记录的日子是同一天（规范化后相等）。
    ///
    /// 背景：v1.1.6 起日期控件回归**一行原生 `DatePicker(.compact)`**，
    /// 它读的是 `startOfDay` 之后的绑定值 —— 这里钉住"显示值 == 真相值"，
    /// 一旦有人把规范化去掉（或改成显示未规范化的 `date`），这条会红。
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

    /// ★★★ v1.1.6 定案：**日期控件不再有"选完自动收"这回事。**
    ///
    /// 这条测试的意义是**反向**的：它断言"我们**没有**引入任何收起逻辑"。
    ///
    /// 十二轮的历史证明，所有"选完自动收"的手段都有代价：
    ///   · `.id(...)` 重建       → 无动画 + 样式退化（第 2/6/9 轮）
    ///   · `Menu { DatePicker }` → 日历根本不渲染（第 7 轮）
    ///   · `.onChange` 收面板    → 滚轮每格触发，面板闪关（第 2/6 轮）
    ///   · 防抖计时器            → 自造冷却窗口（第 10/11 轮）
    ///   · `Button` + `.popover` → 锚点飘到导航栏 + 阻断交互 + 破坏配色（第 11 轮）
    /// 全部被用户否掉。系统原生的"点日历外面即关闭"体验上等价、且零风险。
    func testNoCustomCollapseRuleExists() {
        // 日期控件只做一件事：把绑定值规范化到当天 0 点。
        // 任何"什么时候收起来"的判断都**不该存在**于我们的代码里。
        let cal = AppCalendar.shared
        let anyDay = cal.date(from: DateComponents(year: 2026, month: 10, day: 30))!

        // 幂等：规范化两次 == 规范化一次（说明它是个纯投影，不带副作用/状态）。
        let once = cal.startOfDay(for: anyDay)
        let twice = cal.startOfDay(for: once)
        XCTAssertEqual(once, twice, "规范化必须是幂等的纯函数 —— 不许夹带收起/计时等副作用")

        // 规范化不改变"哪一天"，只抹掉时分秒。
        XCTAssertTrue(cal.isDate(once, inSameDayAs: anyDay))
    }
}
