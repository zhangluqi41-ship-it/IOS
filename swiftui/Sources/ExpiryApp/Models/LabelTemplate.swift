//
//  LabelTemplate.swift
//  模板业务规则 + 时间阈值 + 二维码解析（精确迁移自 Flutter `label_template.dart`）。
//

import Foundation

// MARK: - 全局历法

/// 全流程统一使用的历法。
///
/// ★ 为什么不能直接用 `Calendar.current`：
///   设备如果把「日历」设成佛历 / 民国纪年 / 日本和历，`component(.year,…)`
///   取出来的就是 2569、115 这种年份，会**直接印到标签上**，
///   日期差值（+7 天、阈值判断）也会跟着错。
///   这里锁定公历 + 中文区域，时区仍跟随设备（用户在当地看当地时间是对的）。
enum AppCalendar {
    static let shared: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_Hans_CN")
        calendar.timeZone = TimeZone.current
        return calendar
    }()
}

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
//
// ★ 2026-10-07：`prepared` 字段被删掉了。
//   原因：二维码内容收紧后（见 `LabelData.qrText`）不再包含「制备时间」，
//   世上没有任何地方还在用这个字段。
//   注意 `maker` 同理 —— 新格式的二维码里也没有制作人了，所以扫回来的
//   一发标签 `maker` 会是空串（页面会自动隐藏「操作人」那一行）。

struct KombuchaFirstLabel: Hashable {
    let title: String
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

    // ★★ 输入长度上限（安全 + 性能）
    //    标题会参与「超宽自动缩字号」的量测：几万字的标题会让 CoreText 量出
    //    一个天文数字宽度，缩到 0 号字并拖慢渲染；二维码内容也会被撑爆
    //    （CIQRCodeGenerator 超限直接返回 nil，二维码就没了）。
    //    条数上限见 `ExpiryStore.maxRecords`。
    static let maxTitleLength = 40
    static let maxNameLength = 20
    /// 二维码原文接受的最大字节数（超过直接判定为非法标签）。
    static let maxQrBytes = 1200

    /// 去空白 + 截断，所有来自用户输入的文字都必须过这里。
    static func clamp(_ text: String, _ max: Int = maxTitleLength) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > max ? String(trimmed.prefix(max)) : trimmed
    }

    private static let weekCn = ["日", "一", "二", "三", "四", "五", "六"]
    private static let weekEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // MARK: 日期格式化

    static func fmtDate(_ t: Date) -> String {
        let c = AppCalendar.shared
        let y = c.component(.year, from: t)
        let m = c.component(.month, from: t)
        let d = c.component(.day, from: t)
        return String(format: "%04d/%02d/%02d", y, m, d)
    }

    static func fmtDateTime(_ t: Date) -> String {
        let c = AppCalendar.shared
        let h = c.component(.hour, from: t)
        let mi = c.component(.minute, from: t)
        return "\(fmtDate(t)) \(String(format: "%02d:%02d", h, mi))"
    }

    static func fmtDateAt(_ date: Date, _ time: Date) -> String {
        let c = AppCalendar.shared
        let h = c.component(.hour, from: time)
        let mi = c.component(.minute, from: time)
        return "\(fmtDate(date)) \(String(format: "%02d:%02d", h, mi))"
    }

    static func fmtDateEndOfDay(_ t: Date) -> String {
        return "\(fmtDate(t)) 23:59"
    }

    static func fmtTime(_ t: Date) -> String {
        let c = AppCalendar.shared
        let h = c.component(.hour, from: t)
        let mi = c.component(.minute, from: t)
        return String(format: "%02d:%02d", h, mi)
    }

    // MARK: 阈值规则

    /// date 距 now 是否 ≤ 7 个自然日（按自然日差比较，不受时刻影响）。
    static func isWithinThreshold(_ now: Date, _ date: Date) -> Bool {
        let c = AppCalendar.shared
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
        let w = AppCalendar.shared.component(.weekday, from: t) - 1 // 1=周日 → 索引 0
        return weekCn[w]
    }

    private static func weekdayEn(_ t: Date) -> String {
        let w = AppCalendar.shared.component(.weekday, from: t) - 1
        return weekEn[w]
    }

    // MARK: 通用效期

    static func buildGeneric(title: String, now: Date, expireDate: Date,
                             bestBefore: Date, maker: String) -> LabelData {
        LabelData(
            title: clamp(title),
            rows: [
                LabelRow(label: "开封时间：", value: fmtDateTime(now)),
                LabelRow(label: "原始保质期：", value: fmtDateByThreshold(now, expireDate)),
                LabelRow(label: "最佳使用时间：", value: fmtDateByThreshold(now, bestBefore)),
            ],
            weekdayCn: weekdayCn(now),
            weekdayEn: weekdayEn(now),
            rightText: fmtTime(now),
            maker: "制作人：\(clamp(maker, maxNameLength))"
        )
    }

    // MARK: 奶制品

    static func buildDairy(kindLabel: String, now: Date, expireDate: Date,
                           bestBefore: Date, maker: String) -> LabelData {
        LabelData(
            title: clamp(kindLabel),
            rows: [
                LabelRow(label: "开封时间：", value: fmtDateTime(now)),
                LabelRow(label: "原始保质期：", value: fmtDateByThreshold(now, expireDate)),
                LabelRow(label: "最佳使用时间：", value: fmtDateByThreshold(now, bestBefore)),
            ],
            weekdayCn: weekdayCn(now),
            weekdayEn: weekdayEn(now),
            rightText: fmtTime(now),
            maker: "制作人：\(clamp(maker, maxNameLength))"
        )
    }

    // MARK: 康普茶

    static func kombuchaTitle(_ variety: String) -> String {
        let v = clamp(variety, maxNameLength)
        return v.hasPrefix(kombuchaPrefix) ? v : "\(kombuchaPrefix)-\(v)"
    }

    static func buildKombuchaFirst(variety: String, now: Date, maker: String) -> LabelData {
        let done = AppCalendar.shared.date(byAdding: .day, value: kombuchaDoneDays, to: now) ?? now
        let best = AppCalendar.shared.date(byAdding: .day, value: kombuchaBestDays, to: now) ?? now
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
            maker: "制作人：\(clamp(maker, maxNameLength))"
        )
    }

    /// 康普茶二发的完成时间 = **二发自己的制备时间 + 3 天**。
    ///
    /// ★★ 2026-10-07 修 bug（用户反馈「完成时间应该是 +3 天，而现在是 +10 天」）：
    ///   原来是 `一发完成时间 + 3 天`。而一发完成本身 = 一发制备 + 7 天，
    ///   所以从**二发标签上印着的制备时间**看过去，完成时间变成了 +10 天，
    ///   和旁边那行「制备时间」根本对不上（间隔多久全看你是第几天扫的码）。
    ///
    ///   正确语义：二发的「制备」就是加水果那一刻（= 扫码那一刻），
    ///   完成 = 那一刻 + 3 天，和标签上第一行严格相差 3 天。
    ///   ⚠️ 安卓 / Flutter 版是同一处错误，不要以那边为准。
    ///
    /// 抽成独立函数是为了让「标签上的完成时间」和「入库记录的 expireAt」
    /// 走同一个来源 —— 之前两处各算一遍，改一处漏一处。
    static func kombuchaSecondDone(after now: Date) -> Date {
        AppCalendar.shared.date(byAdding: .day,
                               value: kombuchaSecondDoneDays,
                               to: now) ?? now
    }

    static func buildKombuchaSecond(firstTitle: String, fruit: String, now: Date,
                                    firstBestBefore: Date,
                                    maker: String) -> LabelData {
        let done = kombuchaSecondDone(after: now)
        // 标题里的 firstTitle 来自扫到的二维码（外部输入），同样要收紧
        let combined = clamp("\(clamp(firstTitle, maxTitleLength))-\(clamp(fruit, maxNameLength))",
                             maxTitleLength)
        return LabelData(
            title: combined,
            rows: [
                LabelRow(label: "制备时间：", value: fmtDateTime(now)),
                LabelRow(label: "完成时间：", value: fmtDateTime(done)),
                LabelRow(label: "最佳使用时间：", value: fmtDateTime(firstBestBefore)),
            ],
            weekdayCn: weekdayCn(now),
            weekdayEn: weekdayEn(now),
            rightText: fmtTime(now),
            maker: "制作人：\(clamp(maker, maxNameLength))"
        )
    }

    // MARK: 记录装配

    /// 由标签数据 + 关键日期装配一条「效期管理」记录。
    /// - Parameter expireAt: 原始保质期；康普茶传「完成时间」。
    /// - Parameter bestBefore: 最佳使用时间（到期提醒的基准）。
    static func makeRecord(kind: LabelKind,
                           data: LabelData,
                           createdAt: Date,
                           expireAt: Date,
                           bestBefore: Date,
                           maker: String,
                           source: RecordSource = .printed) -> LabelRecord {
        LabelRecord(title: data.title,
                    kind: kind,
                    maker: clamp(maker, maxNameLength),
                    createdAt: createdAt,
                    printedAt: nil,
                    expireAt: expireAt,
                    bestBefore: bestBefore,
                    usedAt: nil,
                    qrText: data.qrText,
                    source: source)
    }

    // MARK: 重新打印

    /// 由一条「效期管理」记录**确定性还原**出它当初打印的那张标签。
    ///
    /// ★ 为什么不是「再调一次 buildXxx」：
    ///   那几个 builder 里的「完成 / 最佳」是**照 now 现算**的（now + 7 / now + 30）。
    ///   重打时如果重新算，只要记录里的日期不是当初那套推算规则算出来的
    ///   （康普茶二发的「最佳使用时间」是**沿用一发**的，就不是 now + 30），
    ///   印出来的标签就跟实物对不上了 —— 而重打的意义恰恰是「跟原来一模一样」。
    ///
    ///   所以这里**只按记录里存着的三个时间原样排版**：
    ///     `createdAt` → 第一行（通用/奶制品=开封时间，康普茶=制备时间）
    ///     `expireAt`  → 第二行（原始保质期 / 完成时间）
    ///     `bestBefore`→ 第三行（最佳使用时间）
    ///   这正是 `makeRecord` 当初存进去的东西，逐字一致。
    ///
    /// ★ 「原始保质期」那两行当初用的是 `fmtDateByThreshold(now, date)`，
    ///   依赖 `now` 只是为了判「是否 ≤7 天」，所以这里传 `createdAt` 复现结果完全相同。
    static func rebuild(from record: LabelRecord) -> LabelData {
        let now = record.createdAt
        let rows: [LabelRow]
        switch record.kind {
        case .generic, .dairy:
            rows = [
                LabelRow(label: "开封时间：", value: fmtDateTime(now)),
                LabelRow(label: "原始保质期：", value: fmtDateByThreshold(now, record.expireAt)),
                LabelRow(label: "最佳使用时间：", value: fmtDateByThreshold(now, record.bestBefore)),
            ]
        case .kombucha:
            rows = [
                LabelRow(label: "制备时间：", value: fmtDateTime(now)),
                LabelRow(label: "完成时间：", value: fmtDateTime(record.expireAt)),
                LabelRow(label: "最佳使用时间：", value: fmtDateTime(record.bestBefore)),
            ]
        }
        return LabelData(
            title: clamp(record.title),
            rows: rows,
            weekdayCn: weekdayCn(now),
            weekdayEn: weekdayEn(now),
            rightText: fmtTime(now),
            maker: "制作人：\(clamp(record.maker, maxNameLength))"
        )
    }

    // MARK: 二维码解析

    /// 一个日期时间的正则片段：`2026/10/05 15:30`。
    private static let dateTimePat = "\\d{4}/\\d{2}/\\d{2} \\d{2}:\\d{2}"

    /// **新格式**：`{标题}完成时间：{完成}最佳使用时间：{最佳}`
    /// （第一组时间和制作人都被收紧掉了，见 `LabelData.qrText`）。
    private static let kombuchaQrRe = try! NSRegularExpression(
        pattern: "^(?<title>.+?)完成时间：(?<done>\(dateTimePat))"
            + "最佳使用时间：(?<best>\(dateTimePat))$"
    )

    /// **旧格式**（v1.6.14 之前打印出去的标签）：
    /// `{标题}制备时间：{制备}完成时间：{完成}最佳使用时间：{最佳}制作人：{人}`
    ///
    /// ★ 必须保留：用户手里可能已经有打好的实物标签，
    ///   网上改一个格式就让存量标签扫不出来是不可接受的。
    ///   新格式因为有 `$` 锚定，不会误吃到这种串（它结尾多一段「制作人：x」），
    ///   所以先试新、再试旧，顺序安全。
    private static let kombuchaQrLegacyRe = try! NSRegularExpression(
        pattern: "^(?<title>.+?)制备时间：(?<prep>\(dateTimePat))"
            + "完成时间：(?<done>\(dateTimePat))"
            + "最佳使用时间：(?<best>\(dateTimePat))"
            + "制作人：(?<maker>.*)$"
    )

    private static func parseDate(_ s: String) -> Date? {
        let parts = s.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let d = parts[0].split(separator: "/").compactMap { Int($0) }
        let t = parts[1].split(separator: ":").compactMap { Int($0) }
        guard d.count == 3, t.count == 2 else { return nil }
        return AppCalendar.shared.date(from: DateComponents(
            year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1]
        ))
    }

    /// 生成 PDF 文件名：`标题_yyyyMMdd_HHmm.pdf`（非法字符替换、超长截断）。
    static func labelFileName(_ title: String, _ now: Date) -> String {
        // ★ 字符类里带上 `.`：否则标题写成 `..` 时文件名就是 `..`，
        //   拼接路径会跑出文档目录（目录穿越）。PdfSaver 还有第二道校验。
        var safe = title.replacingOccurrences(
            of: "[\\\\/:*?\"<>|\\s.]+",
            with: "_",
            options: .regularExpression
        )
        while safe.hasPrefix("_") { safe.removeFirst() }
        if safe.count > 40 { safe = String(safe.prefix(40)) }
        if safe.isEmpty { safe = "标签" }
        let c = AppCalendar.shared
        let ts = String(format: "%04d%02d%02d_%02d%02d",
                        c.component(.year, from: now),
                        c.component(.month, from: now),
                        c.component(.day, from: now),
                        c.component(.hour, from: now),
                        c.component(.minute, from: now))
        return "\(safe)_\(ts).pdf"
    }

    /// 解析康普茶（一发）标签二维码；不是康普茶标签返回 nil。
    ///
    /// 先按**新格式**（名称 + 后两组时间）解析，失败再按**旧格式**兜底，
    /// 保证存量实物标签照样能扫（见 `kombuchaQrLegacyRe`）。
    static func parseKombuchaQr(_ raw: String) -> KombuchaFirstLabel? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // ★ 二维码内容来自外部（别人贴的一张码就能扫），先卡长度再做正则，
        //   避免超大字符串把正则/后续逻辑拖住。
        guard !text.isEmpty, text.utf8.count <= maxQrBytes else { return nil }
        let ns = text as NSString

        func matched(_ re: NSRegularExpression) -> NSTextCheckingResult? {
            re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        }
        func group(_ m: NSTextCheckingResult, _ name: String) -> String? {
            let r = m.range(withName: name)
            guard r.location != NSNotFound else { return nil }
            return ns.substring(with: r)
        }

        for re in [kombuchaQrRe, kombuchaQrLegacyRe] {
            guard let m = matched(re) else { continue }
            guard let title = group(m, "title")?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                  title.hasPrefix(kombuchaPrefix),
                  let done = group(m, "done").flatMap(parseDate),
                  let best = group(m, "best").flatMap(parseDate) else {
                continue
            }
            return KombuchaFirstLabel(
                title: title,
                finished: done,
                bestBefore: best,
                // 新格式里没有制作人 → 空串，页面会隐藏「操作人」那一行。
                maker: group(m, "maker")?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        return nil
    }
}
