//
//  DurationWheel.swift
//  时长滚轮 —— 「N 天 N 小时 N 分钟」三列选择器。
//
//  ★★★ 2026-10-29（用户）：「新建、编辑的这里面……能否使用官方滚轮插件来选择
//   天、小时、分钟这些呢？」→ 选定方案 A（只用滚轮）。
//
//  为什么不用 `UIDatePicker`：
//    · `.countDownTimer` 只能到 **23:59**，选不了「3 天」；
//    · `.dateAndTime` 是「绝对时刻」，而模板里的天数语义是**相对时长**。
//  ➜ 用官方通用滚轮 `UIPickerView`（Apple 第一方控件），自己配三列数据源。
//
//  存储：对外一律是 **`Double`（天）** —— 与既有 `CustomTemplate.days` 系列字段同构，
//       旧 JSON 里的整数 `3` 也能直接解成 `3.0`，不需要数据迁移。
//       0.5 天 = 12 小时；5 分钟 = 5/1440 ≈ 0.0034722 天。
//

import SwiftUI
import UIKit

// MARK: - 格式化

enum DurationFormat {
    static let minutesPerDay = 24 * 60

    /// 把「天」拆成 (天, 小时, 分钟) —— 分钟四舍五入，顺手把进位处理掉。
    static func components(days: Double) -> (day: Int, hour: Int, minute: Int) {
        let totalMinutes = max(0, Int((days * Double(minutesPerDay)).rounded()))
        return (totalMinutes / minutesPerDay,
                (totalMinutes % minutesPerDay) / 60,
                totalMinutes % 60)
    }

    /// 三个分量合成「天」。
    static func days(day: Int, hour: Int, minute: Int) -> Double {
        Double(day * minutesPerDay + hour * 60 + minute) / Double(minutesPerDay)
    }

    /// 列表里的简短文案：`3天` / `3天6小时` / `5分钟` / `0（立即）`。
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

/// 三列（天 / 小时 / 分钟）的 `UIPickerView`。
///
/// ⚠️ 天的上限 365 是用户明确说过的场景（「365 天就是 365 天」）；
///   小时固定 0...23、分钟固定 0...59 —— 超出就进位到上一列，符合直觉。
struct DurationWheel: UIViewRepresentable {

    @Binding var days: Double
    /// 天数上限（`originalDays` 要 3650，其余 365）。
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
        // 只在「外部值 ≠ 当前选中」时才回写，避免打断用户正在滚的轮子。
        if picker.selectedRow(inComponent: 0) != c.day {
            picker.selectRow(c.day, inComponent: 0, animated: false)
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

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            switch component {
            case 0: return parent.maxDays + 1            // 0...maxDays
            case 1: return 24                            // 0...23
            default: return 60                           // 0...59
            }
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            switch component {
            case 0: return "\(row) 天"
            case 1: return "\(row) 小时"
            default: return "\(row) 分钟"
            }
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let day = pickerView.selectedRow(inComponent: 0)
            let hour = pickerView.selectedRow(inComponent: 1)
            let minute = pickerView.selectedRow(inComponent: 2)
            parent.days = DurationFormat.days(day: day, hour: hour, minute: minute)
        }
    }
}

// MARK: - 表单行（点开在 sheet 里滚）

/// `Form` 里的一行：左边标题，右边显示「3天6小时」，点开弹出滚轮。
///
/// ★ 为什么用 sheet 内联而不是直接塞进 `Form`：
///   `UIPickerView` 自身高度 216pt，内联会把整页撑得很长；
///   而且表单里同时出现两个滚轮时视觉噪音太大。
struct DurationWheelRow: View {

    let title: String
    @Binding var days: Double
    /// 是否允许「0」（= 立即完成）。制备/完成时间允许 0，默认天数不允许。
    var allowsZero: Bool = true
    /// 天数上限。
    var maxDays: Int = 365

    @State private var showing = false
    @State private var draft: Double = 0

    var body: some View {
        Button {
            draft = days
            showing = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(DurationFormat.short(days: days))
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
                            days = allowsZero ? max(0, draft) : max(minimumNonZero, draft)
                            showing = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.height(360)])
        }
    }

    /// `allowsZero == false` 时的最小可用值：1 分钟（不能选 0）。
    private var minimumNonZero: Double {
        1.0 / Double(DurationFormat.minutesPerDay)
    }
}
