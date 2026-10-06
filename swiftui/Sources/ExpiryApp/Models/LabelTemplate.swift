//
//  LabelTemplate.swift
//  模板业务规则 + 时间阈值 + 二维码解析（精确迁移自 Flutter `label_template.dart`）。
//

import Foundation

// MARK: - 奶制品类型

/// 奶制品类型 → 推荐效期（天）。
/// 牛奶/高蛋白/豆奶 +7/+3；燕麦奶 +45/+5；巴旦木奶 +60/+7。
enum DairyKind: String, CaseIterable, Identifiable {
    case milk = "牛奶"
    case highProteinMilk = "高蛋白牛奶"
    case soyMilk = "豆奶"
    case oatMilk = "燕麦奶"
    case almondMilk = "巴旦木奶"

    var id: String { rawValue }
    var label: String { rawValue }

    var expireDays: Int {
        switch self {
        case .milk, .highProteinMilk, .soyMilk: return 7
        case .oatMilk: return 45
        case .almondMilk: return 60
        }
    }

    var bestDays: Int {
        switch self {
        case .milk, .highProteinMilk, .soyMilk: return 3
        case .oatMilk: return 5
        case .almondMilk: return 7
        }
    }

    static func offsetLabel(_ days: Int) -> String { "+\(days) 天" }
}

// MARK: - 康普茶一发解析结果

struct KombuchaFirstLabel: Hashable {
    let title: String
    let prepared: Date
    let finished: Date
    let bestBefore: Date
    let maker: String

    /// 茶叶品种（标题里第一个「-」之后的部分）。
    var variety: String {
        if let i = title.firstIndex(of: "-") {
            return String(title[title.index(after: i)...])
        }
        return title
    }
}

// MARK: - 模板装配

enum LabelTemplate {
    static let endOfDayThresholdDays = 7
    static let kombuchaDoneDays = 7
    static let kombuchaBestDays = 30
    static let kombuchaSecondDoneDays = 3
    static let kombuchaPrefix = "康普茶"

    private static let weekCn = ["日", "一", "二", "三", "四", "五", "六"]
    private static let weekEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // MARK: 日期格式化

    static func fmtDate(_ t: Date) -> String {
        let c = Calendar.current
        let y = c.component(.year, from: t)
        let m = c.component(.month, from: t)
        let d = c.component(.day, from: t)
        return String(format: "%04d/%02d/%02d", y, m, d)
    }

    static func fmtDateTime(_ t: Date) -> String {
        let c = Calendar.current
        let h = c.component(.hour, from: t)
        let mi = c.component(.minute, from: t)
        return "\(fmtDate(t)) \(String(format: "%02d:%02d", h, mi))"
    }

    static func fmtDateAt(_ date: Date, _ time: Date) -> String {
        let c = Calendar.current
        let h = c.component(.hour, from: time)
        let mi = c.component(.minute, from: time)
        return "\(fmtDate(date)) \(String(format: "%02d:%02d", h, mi))"
    }

    static func fmtDateEndOfDay(_ t: Date) -> String {
        return "\(fmtDate(t)) 23:59"
    }

    static func fmtTime(_ t: Date) -> String {
        let c = Calendar.current
        let h = c.component(.hour, from: t)
        let mi = c.component(.minute, from: t)
        return String(format: "%02d:%02d", h, mi)
    }

    // MARK: 阈值规则

    /// date 距 now 是否 ≤ 7 个自然日（按自然日差比较，不受时刻影响）。
    static func isWithinThreshold(_ now: Date, _ date: Date) -> Bool {
        let c = Calendar.current
        let today = c.startOfDay(for: now)
        let end = c.startOfDay(for: date)
        let days = c.dateComponents([.day], from: today, to: end).day ?? 0
        return days <= endOfDayThresholdDays
    }

    /// 阈值内 → date 的日期 + 当前时刻；超过 → date 的日期 + 23:59。
    static func fmtDateByThreshold(_ now: Date, _ date: Date) -> String {
        isWithinThreshold(now, date) ? fmtDateAt(date, now) : fmtDateEndOfDay(date)
    }

    private static func weekdayCn(_ t: Date) -> String {
        let w = Calendar.current.component(.weekday, from: t) - 1 // 1=周日 → 索引 0
        return weekCn[w]
    }

    private static func weekdayEn(_ t: Date) -> String {
        let w = Calendar.current.component(.weekday, from: t) - 1
        return weekEn[w]
    }

    // MARK: 通用效期

    static func buildGeneric(title: String, now: Date, expireDate: Date,
                             bestBefore: Date, maker: String) -> LabelData {
        LabelData(
            title: title,
            rows: [
                LabelRow(label: "开封时间：", value: fmtDateTime(now)),
                LabelRow(label: "原始保质期：", value: fmtDateByThreshold(now, expireDate)),
                LabelRow(label: "最佳使用时间：", value: fmtDateByThreshold(now, bestBefore)),
            ],
            weekdayCn: weekdayCn(now),
            weekdayEn: weekdayEn(now),
            rightText: fmtTime(now),
            maker: "制作人：\(maker)"
        )
    }

    // MARK: 奶制品

    static func buildDairy(kindLabel: String, now: Date, expireDate: Date,
                           bestBefore: Date, maker: String) -> LabelData {
        LabelData(
            title: kindLabel,
            rows: [
                LabelRow(label: "开封时间：", value: fmtDateTime(now)),
                LabelRow(label: "原始保质期：", value: fmtDateByThreshold(now, expireDate)),
                LabelRow(label: "最佳使用时间：", value: fmtDateByThreshold(now, bestBefore)),
            ],
            weekdayCn: weekdayCn(now),
            weekdayEn: weekdayEn(now),
            rightText: fmtTime(now),
            maker: "制作人：\(maker)"
        )
    }

    // MARK: 康普茶

    static func kombuchaTitle(_ variety: String) -> String {
        let v = variety.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.hasPrefix(kombuchaPrefix) ? v : "\(kombuchaPrefix)-\(v)"
    }

    static func buildKombuchaFirst(variety: String, now: Date, maker: String) -> LabelData {
        let done = Calendar.current.date(byAdding: .day, value: kombuchaDoneDays, to: now) ?? now
        let best = Calendar.current.date(byAdding: .day, value: kombuchaBestDays, to: now) ?? now
        return LabelData(
            title: kombuchaTitle(variety),
            rows: [
                LabelRow(label: "制备时间：", value: fmtDateTime(now)),
                LabelRow(label: "完成时间：", value: fmtDateTime(done)),
                LabelRow(label: "最佳使用时间：", value: fmtDateTime(best)),
            ],
            weekdayCn: weekdayCn(now),
            weekdayEn: weekdayEn(now),
            rightText: fmtTime(now),
            maker: "制作人：\(maker)"
        )
    }

    static func buildKombuchaSecond(firstTitle: String, fruit: String, now: Date,
                                    firstFinished: Date, firstBestBefore: Date,
                                    maker: String) -> LabelData {
        let done = Calendar.current.date(byAdding: .day, value: kombuchaSecondDoneDays,
                                         to: firstFinished) ?? firstFinished
        return LabelData(
            title: "\(firstTitle)-\(fruit.trimmingCharacters(in: .whitespacesAndNewlines))",
            rows: [
                LabelRow(label: "制备时间：", value: fmtDateTime(now)),
                LabelRow(label: "完成时间：", value: fmtDateTime(done)),
                LabelRow(label: "最佳使用时间：", value: fmtDateTime(firstBestBefore)),
            ],
            weekdayCn: weekdayCn(now),
            weekdayEn: weekdayEn(now),
            rightText: fmtTime(now),
            maker: "制作人：\(maker)"
        )
    }

    // MARK: 二维码解析

    private static let kombuchaQrRe = try! NSRegularExpression(
        pattern: "^(?<title>.+?)制备时间：(?<prep>\\d{4}/\\d{2}/\\d{2} \\d{2}:\\d{2})"
            + "完成时间：(?<done>\\d{4}/\\d{2}/\\d{2} \\d{2}:\\d{2})"
            + "最佳使用时间：(?<best>\\d{4}/\\d{2}/\\d{2} \\d{2}:\\d{2})"
            + "制作人：(?<maker>.*)$"
    )

    private static func parseDate(_ s: String) -> Date? {
        let parts = s.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let d = parts[0].split(separator: "/").compactMap { Int($0) }
        let t = parts[1].split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, t.count == 2 else { return nil }
        return Calendar.current.date(from: DateComponents(
            year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1]
        ))
    }

    /// 生成 PDF 文件名：`标题_yyyyMMdd_HHmm.pdf`（非法字符替换、超长截断）。
    static func labelFileName(_ title: String, _ now: Date) -> String {
        var safe = title.replacingOccurrences(
            of: "[\\\\/:*?\"<>|\\s]+",
            with: "_",
            options: .regularExpression
        )
        if safe.count > 40 { safe = String(safe.prefix(40)) }
        if safe.isEmpty { safe = "标签" }
        let c = Calendar.current
        let ts = String(format: "%04d%02d%02d_%02d%02d",
                        c.component(.year, from: now),
                        c.component(.month, from: now),
                        c.component(.day, from: now),
                        c.component(.hour, from: now),
                        c.component(.minute, from: now))
        return "\(safe)_\(ts).pdf"
    }

    /// 解析康普茶（一发）标签二维码；不是康普茶标签返回 nil。
    static func parseKombuchaQr(_ raw: String) -> KombuchaFirstLabel? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = text as NSString
        guard let m = kombuchaQrRe.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        func group(_ name: String) -> String? {
            let r = m.range(withName: name)
            guard r.location != NSNotFound else { return nil }
            return ns.substring(with: r)
        }
        guard let title = group("title")?.trimmingCharacters(in: .whitespacesAndNewlines),
              title.hasPrefix(kombuchaPrefix),
              let prep = group("prep").flatMap(parseDate),
              let done = group("done").flatMap(parseDate),
              let best = group("best").flatMap(parseDate) else {
            return nil
        }
        return KombuchaFirstLabel(
            title: title,
            prepared: prep,
            finished: done,
            bestBefore: best,
            maker: group("maker")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}
