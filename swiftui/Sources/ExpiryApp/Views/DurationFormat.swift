//
//  DurationFormat.swift
//  「天」与「天/小时/分钟」之间的换算与文案。
//
//  ★★★ 2026-10-29（用户）：天数字段从 `Int` 改成 `Double`，以支持
//   0.5 天 = 12 小时、5 分钟 = 5/1440 天。
//
//  ⚠️ 单独成文件、且**只放纯函数**（不依赖 UIKit），
//     这样即使后面滚轮 UI 出问题，格式化这部分也能独立编译。
//

import Foundation

enum DurationFormat {
    static let minutesPerDay = 24 * 60

    /// 「天」→ (天, 小时, 分钟)，分钟四舍五入（顺带处理进位）。
    static func components(days: Double) -> (day: Int, hour: Int, minute: Int) {
        let total = max(0, Int((days * Double(minutesPerDay)).rounded()))
        return (total / minutesPerDay, (total % minutesPerDay) / 60, total % 60)
    }

    /// (天, 小时, 分钟) → 「天」。
    static func days(day: Int, hour: Int, minute: Int) -> Double {
        Double(day * minutesPerDay + hour * 60 + minute) / Double(minutesPerDay)
    }

    /// 行内文案：`3天` / `3天6小时` / `5分钟` / `立即`。
    static func short(days: Double?) -> String {
        guard let days, days > 0 else { return "立即" }
        let c = components(days: days)
        var parts: [String] = []
        if c.day > 0 { parts.append("\(c.day)天") }
        if c.hour > 0 { parts.append("\(c.hour)小时") }
        if c.minute > 0 { parts.append("\(c.minute)分钟") }
        return parts.isEmpty ? "立即" : parts.joined()
    }
}
