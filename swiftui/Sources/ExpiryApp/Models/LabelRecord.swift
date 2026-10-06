//
//  LabelRecord.swift
//  已生成 / 已打印 / 已扫到的物料记录 —— 「效期管理」列表的数据模型。
//
//  ★ 效期基准统一取 `bestBefore`（最佳使用时间）：
//      · 通用效期 / 奶制品：最佳使用时间早于原始保质期，是最该先留意的时刻
//      · 康普茶：`expireAt` 是「完成时间」（能开始用的时刻，不是过期），
//        真正会过期的只有「最佳使用时间」
//    所以三个模板里，拿 bestBefore 当「到期日」都是对的。
//

import Foundation

// MARK: - 模板类别

enum LabelKind: String, Codable, CaseIterable, Identifiable {
    case generic
    case kombucha
    case dairy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .generic: return "通用效期"
        case .kombucha: return "康普茶"
        case .dairy: return "奶制品"
        }
    }

    var systemImage: String {
        switch self {
        case .generic: return "clock"
        case .kombucha: return "drop.fill"
        case .dairy: return "flask.fill"
        }
    }
}

// MARK: - 记录来源

enum RecordSource: String, Codable {
    case printed
    case scanned

    var label: String {
        switch self {
        case .printed: return "已打印"
        case .scanned: return "已扫码"
        }
    }
}

// MARK: - 记录

struct LabelRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// 标签标题（也是列表主文案）。
    var title: String
    var kind: LabelKind
    var maker: String
    /// 标签生成 / 扫到的那一刻。
    var createdAt: Date
    /// 打印成功的时刻；扫码得到的记录为 nil。
    var printedAt: Date?
    /// 原始保质期；康普茶语义为「完成时间」。
    var expireAt: Date
    /// 最佳使用时间 —— 效期提醒的基准。
    var bestBefore: Date
    /// 已用完的时刻（nil = 还在用）。
    var usedAt: Date?
    /// 二维码原文，用于同一条标签去重。
    var qrText: String
    var source: RecordSource

    /// 「到期日」= 最佳使用时间。
    var dueDate: Date { bestBefore }
}

// MARK: - 状态

/// 记录的到期阶段（列表分组 + 角标计数都用它）。
enum ExpiryStage: Int, CaseIterable, Comparable {
    case used = 0
    case expired = 1
    case today = 2
    case within3 = 3
    case within7 = 4
    case later = 5

    static func < (lhs: ExpiryStage, rhs: ExpiryStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ExpiryStatus: Equatable {
    let stage: ExpiryStage
    /// 距到期还有几天（负数=已过期几天）。
    let daysLeft: Int

    /// 需要提醒（角标计数）：已过期 / 今天 / 3 天内，且未标记用完。
    var isAlerting: Bool {
        switch stage {
        case .expired, .today, .within3: return true
        case .used, .within7, .later: return false
        }
    }

    var label: String {
        switch stage {
        case .used: return "已用完"
        case .expired: return daysLeft == -1 ? "昨天过期" : "已过期 \(-daysLeft) 天"
        case .today: return "今天就到期"
        case .within3, .within7, .later: return "还剩 \(daysLeft) 天"
        }
    }

    var groupTitle: String {
        switch stage {
        case .expired: return "已过期"
        case .today: return "今天到期"
        case .within3: return "3 天内到期"
        case .within7: return "7 天内到期"
        case .later: return "更久之后"
        case .used: return "已用完"
        }
    }

    static func of(_ record: LabelRecord, now: Date = Date()) -> ExpiryStatus {
        if record.usedAt != nil {
            return ExpiryStatus(stage: .used, daysLeft: 0)
        }
        let cal = AppCalendar.shared
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: now),
                                      to: cal.startOfDay(for: record.dueDate)).day ?? 0
        let stage: ExpiryStage
        if days < 0 {
            stage = .expired
        } else if days == 0 {
            stage = .today
        } else if days <= 3 {
            stage = .within3
        } else if days <= 7 {
            stage = .within7
        } else {
            stage = .later
        }
        return ExpiryStatus(stage: stage, daysLeft: days)
    }
}

/// 效期列表的一个分组。
/// （用结构体而不是元组：Swift 的 KeyPath 不支持元组成员，
///   `ForEach(id: \.status)` 那种写法编译不过。）
struct ExpiryGroup: Identifiable {
    let status: ExpiryStage
    let title: String
    let items: [LabelRecord]

    var id: Int { status.rawValue }
}
