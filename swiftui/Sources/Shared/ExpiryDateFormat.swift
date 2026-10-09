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
