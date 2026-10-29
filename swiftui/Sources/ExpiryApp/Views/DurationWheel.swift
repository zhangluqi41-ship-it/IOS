//
//  DurationWheel.swift
//  时长滚轮 —— 「N 天 N 小时 N 分钟」三列 `UIPickerView`。
//
//  ★★★ 2026-10-29（用户）：
//    「选择天的时候就按整数天来选择就好了，后面不是有时分秒的嘛」→ 方案 A（只用滚轮）。
//    「只要…能完成我要的功能和我们前面确认的界面就行」。
//
//  为什么不用 `UIDatePicker`：`.countDownTimer` 只能到 23:59，选不了「3 天」。
//
//  ⚠️⚠️ 接口是「值 + 回调」，**不是 `Binding`**：
//    在 `Form` 的 `Section` 里内联 `Binding(get:set:)` + 多参数会让 Swift 的
//    类型推断在 Release（-O）下直接放弃（CI 报 `Failed frontend command`，
//    一条 `error:` 都不给）。实测改成值+回调后模型层立刻能编过。
//
//  ⚠️ 存储是「整数天 + 额外分钟」两个字段 —— 刻意**不改** `prepDays: Int` 的类型，
//    避免 40+ 处引用连锁。
//

import SwiftUI
import UIKit

// MARK: - 格式化

enum DurationFormat {
    static let minutesPerDay = 24 * 60

    /// 行内文案：`3天` / `3天6小时` / `5分钟` / `立即`。
    static func short(days: Int, extraMinutes: Int) -> String {
        var parts: [String] = []
        if days > 0 { parts.append("\(days)天") }
        let h = extraMinutes / 60
        let m = extraMinutes % 60
        if h > 0 { parts.append("\(h)小时") }
        if m > 0 { parts.append("\(m)分钟") }
        return parts.isEmpty ? "立即" : parts.joined()
    }
}

// MARK: - UIKit 滚轮

/// 三列：天 / 小时 / 分钟。小时和分钟合并成「额外分钟」一个整数回传。
struct DurationWheel: UIViewRepresentable {

    let days: Int
    let extraMinutes: Int
    let onChange: (Int, Int) -> Void
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
        let h = extraMinutes / 60
        let m = extraMinutes % 60
        if picker.selectedRow(inComponent: 0) != days {
            picker.selectRow(min(days, maxDays), inComponent: 0, animated: false)
        }
        if picker.selectedRow(inComponent: 1) != h {
            picker.selectRow(h, inComponent: 1, animated: false)
        }
        if picker.selectedRow(inComponent: 2) != m {
            picker.selectRow(m, inComponent: 2, animated: false)
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
            case 0: return parent.maxDays + 1   // 0...maxDays 天
            case 1: return 24                   // 0...23 小时
            default: return 60                  // 0...59 分钟
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
            let d = pickerView.selectedRow(inComponent: 0)
            let h = pickerView.selectedRow(inComponent: 1)
            let m = pickerView.selectedRow(inComponent: 2)
            parent.onChange(d, h * 60 + m)
        }
    }
}

// MARK: - 表单行

/// `Form` 里的一行：左边标题、右边「3天6小时」，点开在 sheet 里滚。
struct DurationWheelRow: View {

    let title: String
    let days: Int
    let extraMinutes: Int
    let onChange: (Int, Int) -> Void
    /// 是否允许「0 天 0 分」（= 立即完成）。制备允许，最佳/原始天数不允许。
    var allowsZero: Bool = true
    var maxDays: Int = 365

    @State private var showing = false
    @State private var draftDays: Int = 0
    @State private var draftMinutes: Int = 0

    var body: some View {
        Button {
            draftDays = days
            draftMinutes = extraMinutes
            showing = true
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(DurationFormat.short(days: days, extraMinutes: extraMinutes))
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
                    DurationWheel(days: draftDays,
                                  extraMinutes: draftMinutes,
                                  onChange: { d, m in
                                      draftDays = d
                                      draftMinutes = m
                                  },
                                  maxDays: maxDays)
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
                            // 不允许 0 时，最少 1 分钟。
                            let (d, m) = (allowsZero || draftDays > 0 || draftMinutes > 0)
                                ? (draftDays, draftMinutes)
                                : (0, 1)
                            onChange(d, m)
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
