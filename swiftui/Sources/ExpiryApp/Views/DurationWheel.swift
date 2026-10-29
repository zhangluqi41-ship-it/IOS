//
//  DurationWheel.swift
//  时长滚轮 —— 「N 天 N 小时 N 分钟」三列选择器 + 格式化工具。
//
//  ★★★ 2026-10-29（用户）：「能否使用官方滚轮插件来选择天、小时、分钟这些呢？」
//   → 选定方案 A（只用滚轮）。用 Apple 第一方控件 `UIPickerView`，自己配三列数据源。
//
//  为什么不用 `UIDatePicker`：
//    · `.countDownTimer` 只能到 **23:59**，选不了「3 天」；
//    · `.dateAndTime` 是「绝对时刻」，而模板里的天数是**相对时长**。
//
//  存储：对外一律 `Double`（天）—— 0.5 天 = 12 小时；5 分钟 = 5/1440 天。
//

import SwiftUI
import UIKit

// MARK: - 格式化

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

// MARK: - UIKit 滚轮

/// 三列 `UIPickerView`（天 / 小时 / 分钟）。
/// 小时固定 0...23、分钟固定 0...59，超出就进位到上一列，符合直觉。
struct DurationWheel: UIViewRepresentable {

    @Binding var days: Double
    /// 天数上限（原始保质期要 3650，其余 365）。
    var maxDays: Int = 365

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        let c = DurationFormat.components(days: days)
        // 只在「外部值 ≠ 当前选中」时才回写，避免打断正在滚的轮子。
        if picker.selectedRow(inComponent: 0) != c.day {
            picker.selectRow(min(c.day, maxDays), inComponent: 0, animated: false)
        }
        if picker.selectedRow(inComponent: 1) != c.hour {
            picker.selectRow(c.hour, inComponent: 1, animated: false)
        }
        if picker.selectedRow(inComponent: 2) != c.minute {
            picker.selectRow(c.minute, inComponent: 2, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: DurationWheel

        init(parent: DurationWheel) { self.parent = parent }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 3 }

        func pickerView(_ pickerView: UIPickerView,
                        numberOfRowsInComponent component: Int) -> Int {
            switch component {
            case 0: return parent.maxDays + 1     // 0...maxDays
            case 1: return 24                     // 0...23
            default: return 60                    // 0...59
            }
        }

        func pickerView(_ pickerView: UIPickerView,
                        titleForRow row: Int,
                        forComponent component: Int) -> String? {
            switch component {
            case 0: return "\(row) 天"
            case 1: return "\(row) 小时"
            default: return "\(row) 分钟"
            }
        }

        func pickerView(_ pickerView: UIPickerView,
                        didSelectRow row: Int,
                        inComponent component: Int) {
            parent.days = DurationFormat.days(
                day: pickerView.selectedRow(inComponent: 0),
                hour: pickerView.selectedRow(inComponent: 1),
                minute: pickerView.selectedRow(inComponent: 2))
        }
    }
}

// MARK: - 表单行

/// `Form` 里的一行：左边标题、右边「3天6小时」，点开在 sheet 里滚。
///
/// ★ 为什么用 sheet 而不是内联：`UIPickerView` 自身高 216pt，
///   内联会把整页撑得很长，两个滚轮同时出现时视觉噪音也太大。
struct DurationWheelRow: View {

    let title: String
    /// ★ 2026-10-29：**故意不用 `Binding<Double>`** ——
    ///   在 `Form` 的 `Section` 里内联构造 `Binding(get:set:)` 会让 Swift 的
    ///   类型推断器在 Release（`-O`）下直接放弃（CI 报 `Failed frontend command`，
    ///   一条 `error:` 都不给）。
    ///   ➜ 改成「值 + 回调」，调用方写 `value: x) { newValue in x = ... }`，
    ///     推断简单到不会超时。
    let value: Double
    let onChange: (Double) -> Void
    /// 是否允许 0（= 立即完成）。制备/完成时间允许，最佳天数不允许。
    var allowsZero: Bool = true
    var maxDays: Int = 365

    @State private var showing = false
    @State private var draft: Double = 0

    /// 不允许 0 时的下限：1 分钟。
    private var floorValue: Double {
        allowsZero ? 0 : 1.0 / Double(DurationFormat.minutesPerDay)
    }

    var body: some View {
        Button {
            draft = value
            showing = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(DurationFormat.short(days: value))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) {
            NavigationStack {
                VStack(spacing: 0) {
                    DurationWheel(days: $draft, maxDays: maxDays)
                        .frame(height: 216)
                    Spacer(minLength: 0)
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showing = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            onChange(max(floorValue, draft))
                            showing = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.height(360)])
        }
    }
}
