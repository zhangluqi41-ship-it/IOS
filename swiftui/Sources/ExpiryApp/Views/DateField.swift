//
//  DateField.swift
//  模板页统一的日期输入控件 —— 选完日期自动收起日历。
//
//  ★ 为什么需要它（用户反馈）：
//    「效期中选择时间后，应该直接关闭选择时间的界面，但是目前点击完还保留在
//      选择时间的界面上。」
//    `.compact` 样式的 DatePicker 弹出的日历属于 UIKit 自己管理的浮层，
//    SwiftUI 没有暴露「选中即关闭」的开关，所以选完一天后面板会赖在屏幕上，
//    必须再点一下空白处才收。
//
//  ★ 解法：改变 `.id` 让 DatePicker 整体重建。
//    重建会销毁背后的 UIDatePicker，它弹出的日历也就跟着消失 ——
//    这也是社区里的一致做法（SwiftUI 没给更好的口子）。
//
//  ⚠️ `.id` 只能在「日期真的换了天」的时候才变。
//     否则在日历面板里翻月 / 翻年（并没有选中新日期）也会把面板顶掉，
//     反而变得更难用。所以下面用 `isDate(_:inSameDayAs:)` 做闸门。
//

import SwiftUI

/// 选完就收的日期选择器。
struct AutoCloseDatePicker: View {
    let title: String
    @Binding var date: Date

    /// 变了就重建 DatePicker（= 收起弹出的日历）。
    @State private var identity = UUID()

    var body: some View {
        DatePicker(title, selection: $date, displayedComponents: .date)
            .id(identity)
            .onChange(of: date) { old, new in
                guard !AppCalendar.shared.isDate(old, inSameDayAs: new) else { return }
                identity = UUID()
            }
    }
}
