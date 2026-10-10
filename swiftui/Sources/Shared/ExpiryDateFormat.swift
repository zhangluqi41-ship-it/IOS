//
//  ExpiryDateFormat.swift
//  共享的日期格式化 —— 主 App 与 Widget 扩展都要用。
//
//  ★ 为什么不复用主 App 的 `LabelTemplate.fmtDate/fmtDateTime`：
//    那是**标签排版**用的，任何改动都可能让已定版的标签输出变样
//    （它还绑着「≤7 天用当前时刻 / >7 天用 23:59」的阈值规则）。
//    灵动岛上只需要「给人看的时间」，两件事不该互相牵制，所以单独放一份。
//
//  ★ 输出刻意与标签一致（`yyyy/MM/dd HH:mm`）：
//    用户在灵动岛上看到的时刻，要和手里那张标签上印的**逐字相同**，
//    否则会怀疑「是不是两个时间」。
//

import Foundation

enum ExpiryDateFormat {

    /// `yyyy/MM/dd`
    ///
    /// ★★ 2026-10-10 新增（第七轮用户反馈图8）：
    ///    「时间改为对应的时间模组，比如『最佳使用时间 2026/01/01』」
    ///    → 展开态底部那行要「里程碑文案 + 完整日期」，
    ///      所以需要一个**只到日**的格式（不带时分，与 `time(_:)` 分工）。
    ///    格式与标签一致（`yyyy/MM/dd`），保证用户核对的时刻逐字相同。
    static func date(_ t: Date) -> String { formatter("yyyy/MM/dd").string(from: t) }

    /// `yyyy/MM/dd HH:mm`
    static func dateTime(_ t: Date) -> String { formatter("yyyy/MM/dd HH:mm").string(from: t) }

    /// `HH:mm`
    static func time(_ t: Date) -> String { formatter("HH:mm").string(from: t) }

    /// ★ 与 `LabelTemplate.AppCalendar` 同一套口径：**锁公历**。
    ///   设备把日历设成佛历 / 民国纪年时，`yyyy` 取出来会是 2569 / 115 这种值。
    ///   时区仍跟随设备（用户在当地看当地时间才是对的）。
    private static func formatter(_ format: String) -> DateFormatter {
        let df = DateFormatter()
        df.dateFormat = format
        df.locale = Locale(identifier: "zh_Hans_CN")
        df.calendar = Calendar(identifier: .gregorian)
        df.timeZone = .current
        return df
    }
}
