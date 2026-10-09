//
//  Meat.swift
//  肉类模板的品类与规则 —— 保存类型 / 肉类 / 部位，以及各自的效期偏移。
//
//  ★ 规则（2026-10-09 用户清单「一、模板二级菜单」第 4 条）：
//      · 第一组「保存类型」：冷藏 / 冷冻
//      · 第二组「肉类」：鸡肉 / 猪肉 / 牛肉 / 羊肉 → 各自细分部位
//      · 冷藏：原始保质期与最佳使用时间**都 +5 天**
//      · 冷冻：原始保质期与最佳使用时间**都 +3 个月**
//      · 冷冻标签的二维码**再扫一次 = 解冻**：
//          开封时间 → 「解冻时间」（= 扫码那一刻）
//          原始保质期 → **原样不变**
//          最佳使用时间 → 扫码那一刻 + 3 天
//
//  ★ 为什么标题里要带保存类型（`冷冻-牛肉-眼肉`）：
//    二维码内容只有「名称 + 后两组时间」，而肉类和奶制品的三行标签**完全一样**
//    （开封时间 / 原始保质期 / 最佳使用时间），不靠标题就分不出这张是
//    冷藏还是冷冻 —— 而「扫冷冻标签进解冻流程」恰恰要靠这一点来判定。
//    标题带前缀是唯一不用改动已定版式就能做到的方案。
//

import Foundation

// MARK: - 规则常量

enum MeatRule {
    /// 冷藏：原始保质期与最佳使用时间都 +5 天。
    static let chilledDays = 5
    /// 冷冻：原始保质期与最佳使用时间都 +3 个月。
    static let frozenMonths = 3
    /// 解冻后：最佳使用时间 = 解冻那一刻 + 3 天。
    static let thawedBestDays = 3
    /// 解冻标签标题前缀（也用来在二维码里区分「已解冻」）。
    static let thawPrefix = "解冻"
    /// 标题层级分隔符。
    static let titleSeparator = "-"

    /// 由「保存类型 + 基准日」算出（原始保质期, 最佳使用时间）。
    /// 冷藏与冷冻的两个日期都相同（用户要求），所以返回两个相同值。
    static func dates(storage: MeatStorage, from base: Date) -> (expire: Date, best: Date) {
        let cal = AppCalendar.shared
        let day = cal.startOfDay(for: base)
        switch storage {
        case .chilled:
            let d = cal.date(byAdding: .day, value: chilledDays, to: day) ?? day
            return (d, d)
        case .frozen:
            let d = cal.date(byAdding: .month, value: frozenMonths, to: day) ?? day
            return (d, d)
        }
    }

    /// 解冻后的最佳使用时间。
    static func thawedBest(from base: Date) -> Date {
        AppCalendar.shared.date(byAdding: .day, value: thawedBestDays, to: base) ?? base
    }

    /// 肉类标签主标题：`冷藏-牛肉-眼肉`。
    static func title(storage: MeatStorage, animal: MeatAnimal, cut: String) -> String {
        "\(storage.label)\(titleSeparator)\(animal.label)\(titleSeparator)\(cut)"
    }

    /// 解冻标签主标题：把保存类型前缀换成 `解冻`。
    static func thawTitle(baseName: String) -> String {
        "\(thawPrefix)\(titleSeparator)\(baseName)"
    }
}

// MARK: - 保存类型

enum MeatStorage: String, CaseIterable, Identifiable {
    case chilled = "冷藏"
    case frozen = "冷冻"

    var id: String { rawValue }
    var label: String { rawValue }

    var isFrozen: Bool { self == .frozen }

    /// 界面上「按推荐填日期」右侧显示的偏移说明。
    var offsetText: String {
        switch self {
        case .chilled: return "+\(MeatRule.chilledDays) 天"
        case .frozen: return "+\(MeatRule.frozenMonths) 个月"
        }
    }

    var systemImage: String {
        switch self {
        case .chilled: return "thermometer.snowflake"
        case .frozen: return "snowflake"
        }
    }
}

// MARK: - 肉类（动物）

enum MeatAnimal: String, CaseIterable, Identifiable {
    case chicken = "鸡肉"
    case pork = "猪肉"
    case beef = "牛肉"
    case lamb = "羊肉"

    var id: String { rawValue }
    var label: String { rawValue }

    /// 该肉类下的部位（顺序即界面顺序，用户给的清单原样照抄）。
    var cuts: [String] {
        switch self {
        case .chicken:
            return ["鸡胸", "鸡腿"]
        case .pork:
            return ["梅花肉", "五花肉", "后腿肉", "排骨", "筒骨", "猪颈肉"]
        case .beef:
            return ["牛腩", "牛肋条", "牛腱", "菲力（里脊）", "眼肉",
                    "西冷（外脊）", "板腱", "上脑"]
        case .lamb:
            return ["上脑", "里脊", "羊肋排", "羊前腿", "羊后腿", "羊腩", "羊腱子"]
        }
    }
}

// MARK: - 扫到的肉类标签

/// 从肉类标签二维码解析出来的信息。
///
/// ★ `expireRaw` 存的是二维码里**原始保质期那一行的原文**：
///   用户要求解冻后「原始保质期保持原保不变」，
///   所以要原样搬过去，而不是拿 Date 重新格式化一遍
///   （重新格式化会按「是否 ≤7 天」改写时刻，就不叫「不变」了）。
struct MeatLabelInfo: Hashable {
    /// 去掉保存类型 / 解冻前缀之后的「肉类-部位」，如 `牛肉-眼肉`。
    let baseName: String
    /// 原标签的主标题。
    let title: String
    let storage: MeatStorage
    /// 这张标签是不是已经是解冻过的（标题前缀为 `解冻`）。
    let alreadyThawed: Bool
    let expireAt: Date
    let bestBefore: Date
    /// 原始保质期那一行的**原文**（原样搬到解冻标签上）。
    let expireRaw: String
}
