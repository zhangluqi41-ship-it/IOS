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
    /// ★★★ 2026-10-17 新增（用户功能 2）：**扫到的那段二维码原文**。
    ///
    /// 用途：二发页的「原材料是否用完」勾选 —— 确认打印后按它在效期管理里
    /// 找到「这一发的那瓶」记录并标为已用完（扫码时 `ScanView` 用同一个 `code`
    /// 入库，`qrText == sourceQR` 即那条记录）。默认空串，老构造点不用改。
    var sourceQR: String = ""

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

    // MARK: - 日期选择器的「收起判据」

    /// 日历浮层「什么时候该自动收起」的判定 —— **纯函数，可单测**。
    ///
    /// ─────────── 2026-10-11 第二十七轮：修「滚年月也被收起」───────────
    ///
    /// 用户复验 v1.1.10：
    ///   「现在日历点击完日期确实收回了，**但是选择年月的滚轮后也收回了**
    ///     （不应该收回，只有选择完日期后收回）」
    ///
    /// ★ 我上一版判据写的是「规范化后的『天』变了就收」，注释里还写了一句
    ///   "左右翻月 / 滚年份 → `selection` 不参与 → 不受影响" ——
    ///   **这条注释是错的**：`.graphical` 日历点顶部标题弹出的**年月滚轮**
    ///   在滚动时会**立即把新值写进 `selection`**（年月变、日尽量保持），
    ///   于是 `onChange` 触发 → `showing = false` → 浮层被误关。
    ///
    /// ★ 正确判据 = **区分「点网格里的某一天」和「用滚轮换月/换年」**：
    ///
    ///   · 点网格里的一天  → **年月不变**，只有「日」变  → 应当收起 ✔
    ///   · 滚轮换月 / 换年 → **年月变了**，日通常不变    → 不该收起 ✔
    ///   · 点相邻月的灰字日期 → 年月会变（系统还会翻月）  → 不收（用户还在导航，合理）
    ///   · 点中的就是当前这天 → 值不变 → `onChange` 根本不触发 → 不收
    ///
    /// ➜ 所以判据落在一句话上：**「年月没变、只是换了某一天」才算"选完日期"。**
    ///
    /// ⚠️ 别再退回「值变了就收」—— 那正是本轮被否掉的做法。
    /// ⚠️ 别引入防抖计时器来"猜"用户滚完了没 —— 判据本身就该是确定的。
    ///
    /// ⚠️⚠️ 必须写在 `enum LabelTemplate` **内部**：Swift 不允许「顶层 static func」
    ///     （`static methods may only be declared on a type`）——
    ///     v1.1.11 首次推 CI 就是踩了这个坑（两个 job 同时编译失败）。
    static func shouldCollapseAfterDateChange(from old: Date, to new: Date,
                                              calendar: Calendar = AppCalendar.shared) -> Bool {
        let oldDay = calendar.startOfDay(for: old)
        let newDay = calendar.startOfDay(for: new)

        // ① 同一天 → 什么都没选（`onChange` 一般也不会触发，这里兜个底）。
        guard oldDay != newDay else { return false }

        // ② 年月只要变了 → 判定为「滚轮导航」（换月/换年），**不收起**。
        let oldYear = calendar.component(.year, from: oldDay)
        let newYear = calendar.component(.year, from: newDay)
        let oldMonth = calendar.component(.month, from: oldDay)
        let newMonth = calendar.component(.month, from: newDay)
        guard oldYear == newYear, oldMonth == newMonth else { return false }

        // ③ 年月没变、只是换了一天 → 这才是「点了网格里的日期」→ 收起。
        return true
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

    // MARK: 通用效期 / 奶制品 / 肉类（同一版式）

    /// 标签页脚「制作人：xxx」（统一收紧到 `maxNameLength`，全模板共用）。
    private static func makerFooter(_ maker: String) -> String {
        "制作人：\(clamp(maker, maxNameLength))"
    }

    /// 「开封时间 / 原始保质期 / 最佳使用时间」三行版式 ——
    /// 通用 / 奶制品 / 肉类共用，只有标题的来源不同（见下面三个入口）。
    private static func buildOpenedLabel(title: String, now: Date, expireDate: Date,
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
            maker: makerFooter(maker)
        )
    }

    static func buildGeneric(title: String, now: Date, expireDate: Date,
                             bestBefore: Date, maker: String) -> LabelData {
        buildOpenedLabel(title: title, now: now, expireDate: expireDate,
                         bestBefore: bestBefore, maker: maker)
    }

    static func buildDairy(kindLabel: String, now: Date, expireDate: Date,
                           bestBefore: Date, maker: String) -> LabelData {
        buildOpenedLabel(title: kindLabel, now: now, expireDate: expireDate,
                         bestBefore: bestBefore, maker: maker)
    }

    /// 肉类标签。版式与奶制品**完全一致**（开封时间 / 原始保质期 / 最佳使用时间），
    /// 只有标题里多带了保存类型 —— 见 `Meat.swift` 顶部说明。
    static func buildMeat(animal: MeatAnimal, cut: String, storage: MeatStorage,
                          now: Date, expireDate: Date, bestBefore: Date,
                          maker: String) -> LabelData {
        buildOpenedLabel(title: MeatRule.title(storage: storage, animal: animal, cut: cut),
                         now: now, expireDate: expireDate,
                         bestBefore: bestBefore, maker: maker)
    }

    /// 解冻标签（扫冷冻标签的二维码后生成）。
    ///
    /// 三行，逐条对应用户要求：
    ///   ① 第一行「开封时间」→「解冻时间」，值 = 扫码那一刻；
    ///   ② 第二行「原始保质期」→「**完成时间**」，值 = 解冻那一刻 + 1 天
    ///      （2026-10-10 第十五轮用户要求：解冻需要一天）；
    ///   ③ 第三行「最佳使用时间」= 扫码那一刻 + `MeatRule.thawedBestDays`（3）天。
    static func buildMeatThaw(baseName: String, now: Date, maker: String) -> LabelData {
        let complete = MeatRule.thawedComplete(from: now)
        let best = MeatRule.thawedBest(from: now)
        return LabelData(
            title: clamp(MeatRule.thawTitle(baseName: baseName)),
            rows: [
                LabelRow(label: "解冻时间：", value: fmtDateTime(now)),
                LabelRow(label: "完成时间：", value: fmtDateByThreshold(now, complete)),
                LabelRow(label: "最佳使用时间：", value: fmtDateByThreshold(now, best)),
            ],
            weekdayCn: weekdayCn(now),
            weekdayEn: weekdayEn(now),
            rightText: fmtTime(now),
            maker: makerFooter(maker)
        )
    }

    // MARK: 康普茶

    static func kombuchaTitle(_ variety: String) -> String {
        let v = clamp(variety, maxNameLength)
        return v.hasPrefix(kombuchaPrefix) ? v : "\(kombuchaPrefix)-\(v)"
    }

    /// 自定义模板的「制备版式」：制备时间 / 完成时间 / 最佳使用时间。
    ///
    /// ★ 2026-10-19（用户）：「使用制备功能」开启后用这个，和康普茶一发同构。
    static func buildCustomPrep(title: String, now: Date, doneDays: Int,
                               bestBefore: Date, maker: String) -> LabelData {
        let done = AppCalendar.shared.date(byAdding: .day, value: max(1, doneDays), to: now) ?? now
        return LabelData(
            title: clamp(title),
            rows: [
                LabelRow(label: "制备时间：", value: fmtDateTime(now)),
                LabelRow(label: "完成时间：", value: fmtDateTime(done)),
                LabelRow(label: "最佳使用时间：", value: fmtDateTime(bestBefore)),
            ],
            weekdayCn: weekdayCn(now),
            weekdayEn: weekdayEn(now),
            rightText: fmtTime(now),
            maker: makerFooter(maker)
        )
    }

    /// 自定义模板的「二次制备」版式：制备 / 完成 / 最佳（最佳沿用原标签）。
    ///
    /// ★ 2026-10-19（用户）：「扫描二维码二次制备」——扫原标签后续做，
    ///   完成 = **扫描时刻 + `doneDays`**，最佳使用时间**沿用原标签**（和康普茶二发一致）。
    static func buildCustomSecondary(sourceTitle: String, suffix: String, now: Date,
                                     doneDays: Int, sourceBestBefore: Date,
                                     maker: String) -> LabelData {
        let done = AppCalendar.shared.date(byAdding: .day,
                                           value: max(1, doneDays), to: now) ?? now
        let combined = clamp("\(clamp(sourceTitle, maxTitleLength))-\(clamp(suffix, maxNameLength))",
                             maxTitleLength)
        return LabelData(
            title: combined,
            rows: [
                LabelRow(label: "制备时间：", value: fmtDateTime(now)),
                LabelRow(label: "完成时间：", value: fmtDateTime(done)),
                LabelRow(label: "最佳使用时间：", value: fmtDateTime(sourceBestBefore)),
            ],
            weekdayCn: weekdayCn(now),
            weekdayEn: weekdayEn(now),
            rightText: fmtTime(now),
            maker: makerFooter(maker)
        )
    }

    /// 通用二维码解析（自定义模板二次制备用）：从 `qrText` 里取**标题**和**最佳使用时间**。
    ///
    /// 二维码内容 = 标题 + 各行的「label + value」拼起来，例如：
    ///   `冷冻-猪肉-五花肉开封时间：2026/10/19 10:00原始保质期：2026/10/24 10:00最佳使用时间：2026/10/24 10:00`
    static func parseCustomQr(_ raw: String) -> (title: String, bestBefore: Date)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= maxQrBytes else { return nil }

        // 标题 = 第一个「XX时间：」之前的所有内容。
        guard let firstTime = text.range(of: "时间：") else { return nil }
        let title = String(text[text.startIndex..<firstTime.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        // 最佳使用时间：取「最佳使用时间：」后面那一串，直到下一个「：」或结尾。
        guard let bestRange = text.range(of: "最佳使用时间：") else { return nil }
        let tail = String(text[bestRange.upperBound...])
        let candidate = tail.split(separator: "：").first.map(String.init) ?? tail
        guard let date = parseDate(candidate) else { return nil }

        return (title, date)
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
            maker: makerFooter(maker)
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
            maker: makerFooter(maker)
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
    ///     `expireAt`  → 第二行（原始保质期 / 康普茶的完成时间）
    ///     `bestBefore`→ 第三行（最佳使用时间）
    ///   这正是 `makeRecord` 当初存进去的东西，逐字一致。
    ///
    ///   ⚠️ 解冻肉类的第二行是「完成时间」—— 它**就存在 `expireAt`**（与康普茶
    ///      同槽位；2026-10-13 用户第 6 条统一定版），直接用存量值、不现算。
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
        case .meat:
            // 肉类有两副面孔：
            //   · 普通肉类标签 = 开封时间 / 原始保质期 / 最佳使用时间；
            //   · 扫冷冻标签生成的**解冻**标签 = 解冻时间 / **完成时间** / 最佳使用时间。
            // 记录里没有单独存「是哪一副」，但标题前缀是确定性的
            // （解冻标签的标题一定是「解冻-…」，见 `MeatRule.thawTitle`），
            // 由它反推即可，不必为一行文案去改数据模型。
            if record.title.hasPrefix(MeatRule.thawPrefix + MeatRule.titleSeparator) {
                // ★★★ 2026-10-13（用户第 6 条）：完成时间**直接就存在 `record.expireAt`**
                //   （与康普茶同槽位）—— 打印（`MeatThawView`）/ 扫码（`handleMeat`）
                //   两条路径存进去的都是它，重打直接用存量值。
                //   ⚠️ 不要改回「由 `createdAt` 现算」：扫码合并（`add` 会整体替换
                //     记录、只保留 id/usedAt）后 createdAt 变成扫码时刻 → 算出来是错的，
                //     而实物标签上印的完成时间根本没变。
                //   ⚠️ 存量旧解冻记录（本版之前入库的）`expireAt` 还带着冷冻原保，
                //     重打第二行会不对 —— 那批都是旧版测试数据，删掉重新打即可。
                rows = [
                    LabelRow(label: "解冻时间：", value: fmtDateTime(now)),
                    LabelRow(label: "完成时间：",
                             value: fmtDateByThreshold(now, record.expireAt)),
                    LabelRow(label: "最佳使用时间：", value: fmtDateByThreshold(now, record.bestBefore)),
                ]
            } else {
                rows = [
                    LabelRow(label: "开封时间：", value: fmtDateTime(now)),
                    LabelRow(label: "原始保质期：", value: fmtDateByThreshold(now, record.expireAt)),
                    LabelRow(label: "最佳使用时间：", value: fmtDateByThreshold(now, record.bestBefore)),
                ]
            }
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
            maker: makerFooter(record.maker)
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

    // MARK: 通用标签解析（通用效期 / 奶制品）

    /// 通用标签（通用效期、奶制品）二维码：
    /// `{标题}原始保质期：{保质期}最佳使用时间：{最佳}`。
    ///
    /// ★ 2026-10-09（清单「二、扫码」第 1 条）：
    ///    用户要求「所有物料扫码后若无后续操作，均将该物料信息重新加入
    ///    效期管理系统里」。此前只有**康普茶**和**肉类**有解析器能认出标签，
    ///    通用 / 奶制品标签扫了会落进「无法识别的标签」分支 ——
    ///    于是这类物料永远进不了列表。
    ///    ➜ 补一个通用解析器，让它们也能**只入库、不跳转**。
    ///
    /// ⚠️ 必须放在康普茶 / 肉类**之后**判定：那两种的正则更具体，
    ///   先被它们认出才不会被这里「兜底」吃掉。
    ///   这里刻意**不做标题前缀限制** —— 通用标签的标题是用户手填的
    ///   （任何文字都可能），只能靠「原始保质期：… 最佳使用时间：…」
    ///   这套固定字段锚点来识别。
    private static let genericQrRe = try! NSRegularExpression(
        pattern: "^(?<title>.+?)原始保质期：(?<exp>\(dateTimePat))"
            + "最佳使用时间：(?<best>\(dateTimePat))$"
    )

    /// 一份「足够入库」的通用标签信息。`title` 已去掉可能的「开封时间：…」前缀。
    struct GenericLabelInfo {
        let title: String
        let expireAt: Date
        let bestBefore: Date
    }

    /// 解析通用 / 奶制品标签二维码；不是这类标签返回 nil。
    static func parseGenericQr(_ raw: String) -> GenericLabelInfo? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= maxQrBytes else { return nil }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = genericQrRe.firstMatch(in: text, range: full) else { return nil }

        func group(_ name: String) -> String? {
            let r = m.range(withName: name)
            guard r.location != NSNotFound else { return nil }
            return ns.substring(with: r)
        }

        guard var title = group("title")?.trimmingCharacters(in: .whitespacesAndNewlines),
              let expireAt = group("exp").flatMap(parseDate),
              let bestBefore = group("best").flatMap(parseDate) else { return nil }

        // ★ 二维码里没有「开封时间」这一行（`LabelData.qrText` 只取后两行），
        //   所以标题就是纯标题。但**旧格式**的码里第一行可能是
        //   「开封时间：…」，兜一刀把残留前缀切掉，免得标题变成一长串时间。
        if let cut = title.range(of: "原始保质期：") {
            title = String(title[..<cut.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !title.isEmpty else { return nil }

        return GenericLabelInfo(title: title, expireAt: expireAt, bestBefore: bestBefore)
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

    // MARK: 肉类二维码解析

    /// 肉类标签二维码：`{标题}(原始保质期|完成时间)：{日期}最佳使用时间：{最佳}`。
    ///
    /// ★ 标题必须以 `冷藏-` / `冷冻-` / `解冻-` 开头（见 `MeatRule.title`），
    ///   否则就不是肉类标签 —— 这也正是「扫冷冻标签进解冻流程」的判据。
    ///
    /// ★ 第二段锚点**两种都要收**（2026-10-10 第十五轮）：
    ///   · `原始保质期` —— 冷藏 / 冷冻标签，以及改动前打出的**存量旧解冻标签**；
    ///   · `完成时间`   —— 改动后的**新解冻标签**（第二行已改名）。
    ///   漏掉任何一个都会让对应标签「扫不出来」，务必保留两种。
    ///
    /// ⚠️ 只收这两段，与 `LabelData.qrText` 一致（第一行「开封/解冻时间」不进码，
    ///   所以这里也无从得知它 —— 不过它本来就不影响任何判断）。
    private static let meatQrRe = try! NSRegularExpression(
        pattern: "^(?<title>.+?)(?:原始保质期|完成时间)：(?<exp>\(dateTimePat))"
            + "最佳使用时间：(?<best>\(dateTimePat))$"
    )

    /// 解析肉类标签二维码；不是肉类标签返回 nil。
    static func parseMeatQr(_ raw: String) -> MeatLabelInfo? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= maxQrBytes else { return nil }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = meatQrRe.firstMatch(in: text, range: full) else { return nil }

        func group(_ name: String) -> String? {
            let r = m.range(withName: name)
            guard r.location != NSNotFound else { return nil }
            return ns.substring(with: r)
        }

        guard let title = group("title")?.trimmingCharacters(in: .whitespacesAndNewlines),
              let expireRaw = group("exp"),
              let expireAt = parseDate(expireRaw),
              let bestBefore = group("best").flatMap(parseDate) else { return nil }

        let sep = MeatRule.titleSeparator
        let thawHead = MeatRule.thawPrefix + sep
        let chilledHead = MeatStorage.chilled.label + sep
        let frozenHead = MeatStorage.frozen.label + sep

        let storage: MeatStorage
        let alreadyThawed: Bool
        let baseName: String
        if title.hasPrefix(frozenHead) {
            storage = .frozen
            alreadyThawed = false
            baseName = String(title.dropFirst(frozenHead.count))
        } else if title.hasPrefix(chilledHead) {
            storage = .chilled
            alreadyThawed = false
            baseName = String(title.dropFirst(chilledHead.count))
        } else if title.hasPrefix(thawHead) {
            // 解冻标签是从冷冻标签派生的，保存类型仍然是「冷冻」。
            storage = .frozen
            alreadyThawed = true
            baseName = String(title.dropFirst(thawHead.count))
        } else {
            return nil
        }
        guard !baseName.isEmpty else { return nil }

        return MeatLabelInfo(baseName: baseName,
                             title: title,
                             storage: storage,
                             alreadyThawed: alreadyThawed,
                             expireAt: expireAt,
                             bestBefore: bestBefore,
                             // 保留该行原文：对冷藏/冷冻是「原始保质期」，
                             // 对新解冻标签是「完成时间」—— 解冻页顶部只作展示用。
                             expireRaw: expireRaw)
    }
}
