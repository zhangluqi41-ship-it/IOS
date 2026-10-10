//
//  DateField.swift
//  模板页统一的日期输入控件。
//
//  ─────────────────── 演变史（十次用户反馈，前九次全是「自造 → 打脸」） ───────────────────
//
//  【一~九轮】反复在「用 `.id` 重建 DatePicker 顶掉面板」和「`.compact` 私有 popover
//     点了外面才关」之间来回横跳，连踩三次同一个坑（第二、六、九轮）。
//
//  ★★★【第十轮】本次（v1.1.5）—— 用户报：
//     「点击 10 月 30 日，先显示系统格式，但日历栏马上**瞬间收回，无动画**！
//       然后格式**一瞬间变成其他样子**（2026/10/30）。感觉又像写了史山代码。
//       使用第一方工具！」
//
//     ★ 用户描述的两个现象是**同一个根因**：`.id(calendarId)`。
//       `.id` 换值 = SwiftUI **销毁并重建整个 `DatePicker` 控件**：
//         ① 重建瞬间，UIKit 侧来不及恢复 `.compact` 的样式状态
//            → 控件退化成「普通文本」的样子（用户看到的"格式变成 2026/10/30"）；
//         ② 重建是**硬替换**，没有任何过渡 → 就是用户说的"瞬间收回、无动画"。
//       ➜ 这正是第二/六轮的旧病。**`.id` 重建 = 自造手法，必须彻底弃用。**
//
//     ★ 为什么以前觉得"必须用 `.id`"：因为 `.compact` 弹的是 **UIKit 私有 popover**，
//       SwiftUI 层**没有 API 能关它** —— 于是只能靠"重建控件"这种歪招把它顶掉。
//       ➜ 正解不是继续修歪招，而是**换成一套公开的、可控的第一方 API**：
//
//     ★★★ 定案 = **`.popover` + `DatePicker(.graphical)`**：
//       · `popover` 是**公开的第一方弹层**，`isPresented` 完全由我们掌握
//         → **选完直接把 `isPresented = false`**，弹层走**系统自己的
//           收起动画**（带转场、带缩放淡出），这就是"有动画"。
//       · `.graphical` 是**公开的日历样式**，不再依赖任何私有实现
//         → 不存在"重建后样式退化"。
//       · 主行显示日期**我们自己用 `Text` 渲染**（`xxxx/xx/xx`），
//         不重建任何控件 → 格式**永远稳定**，不会"一瞬间变成别的样子"。
//       · 触发按钮是普通 `Button` → 与 `List` 滚动、与收键盘手势都**不冲突**。
//
//     ⚠️ 已被淘汰、**不要再写回来**的三样东西：
//       ① `.id(...)` 重建 —— 无动画 + 样式退化（第二/六/九轮，用户三次报障）；
//       ② `Menu { DatePicker }` —— Menu 只装命令，日历根本不渲染（第七轮）；
//       ③ `.compact` + 私有 popover —— 关不掉，只能靠歪招（第八/九轮）。
//     ⚠️ `.popover` 在 iPhone 上默认会变成 sheet（半屏卡），
//        必须加 `.presentationCompactAdaptation(.popover)` 才保持"浮层"形态。
//
//  ★★★ 验收要点（v1.1.5）
//     点日期 → 弹出系统日历浮层；点中某一天 → 浮层**带动画**收起；日期格式**始终稳定**。
//
//  ★ 一句话记住这次的教训：
//    **`.id()` 换值 = 销毁重建控件**。凡是"关不掉某个系统弹层"的困境，
//    正确做法是**换一个公开、可控的第一方 API**（这里 = `popover` + `isPresented`），
//    而不是用重建控件的歪招 —— 后者必然带来「无动画 + 样式退化」。

import SwiftUI

/// 模板页统一的日期选择器：**点日期 → 弹出系统日历浮层 → 选完自动、带动画收起**。
///
/// 全程只用第一方公开 API：`Button` + `popover` + `DatePicker(.graphical)` + `Text(format:)`。
struct LabelDatePicker: View {
    let title: String
    @Binding var date: Date

    /// 日历浮层是否展开。**由我们自己掌控** —— 这正是它能"带系统动画收起"的原因。
    @State private var showing = false

    /// 选中的日期（规范化到当天 0 点）。用于和 `DatePicker` 双向绑定。
    private var day: Binding<Date> {
        Binding(
            get: { AppCalendar.shared.startOfDay(for: date) },
            set: { date = $0 }
        )
    }

    /// 日期文字的展示格式：`2026/10/30`。
    ///
    /// ★ 用**第一方 `FormatStyle`**（`Date.FormatStyle`）配置，而不是自己拼字符串：
    ///   拼字符串属于"自造"，还得自己处理补零 / locale / 公历；
    ///   `FormatStyle` 自带这些能力，并与系统语言环境保持一致。
    /// ★ 三项顺序（年 / 月 / 日）与分隔符由 `FormatStyle` 自己按当前 locale 决定；
    ///   中文环境下数字日期本身就是 `2026/10/30` 这种斜杠形式
    ///   （不用 `Text(date, format: .dateTime…)` 的"年月日"写法，
    ///     那个会输出「2026年10月30日」—— 用户从第二轮起就要求统一斜杠格式）。
    private static let slashy = Date.FormatStyle(date: .numeric, time: .omitted)
        .year().month().day()

    var body: some View {
        // ★ 整行就是一个普通 `Button`：左标题、右日期文字。
        //   ⚠️ 不用 `DatePicker` 当行本身 —— 那样又会被迫用它的私有 popover。
        Button {
            showing = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(day.wrappedValue, format: Self.slashy)
                    .foregroundStyle(Theme.brand)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // ★ 第一方弹层：`popover` 的 `isPresented` 由我们掌握 → 能主动、带动画地收起。
        //   ⚠️ iPhone 上默认会自适应成 sheet（半屏卡），必须用
        //      `.presentationCompactAdaptation(.popover)` 强制保持浮层形态。
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            DatePicker(title, selection: day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
                .presentationCompactAdaptation(.popover)
                .onChange(of: day.wrappedValue) { _, _ in
                    // ★ 选完一格 → 收起浮层（系统 popover 自己的转场动画）。
                    //   ⚠️ `.graphical` 的 `selection` **只在点到某一天时才变**
                    //      （左右切换月份不改它）→ 不会出现"翻月份就被关掉"的旧病。
                    //   ⚠️ 这里只可能在"用户点了某天"之后触发：`.onChange` 不会
                    //      在初始渲染时对初值触发，所以弹层刚出来不会被自己关掉。
                    showing = false
                }
        }
    }

    /// `xxxx/xx/xx` —— 固定 4/2/2 位。
    ///
    /// ⚠️ 当前视图**不用**它（显示交给 `Text(_:format:)` 这个第一方 `FormatStyle`）。
    ///    保留它是给测试与「万一要手拼」留的入口。**别因为"没人用"删掉。**
    static func text(for date: Date) -> String {
        let c = AppCalendar.shared
        let y = c.component(.year, from: date)
        let m = c.component(.month, from: date)
        let d = c.component(.day, from: date)
        return String(format: "%04d/%02d/%02d", y, m, d)
    }
}

/// 日期单位图例：英文缩写 `Y / M / D`。
///
/// ⚠️ **从未接入任何真实页面**（只在 #Preview 里出现过）。保留原因：
///   当初想解决「滚轮单位是中文」，但系统 DatePicker 的面板无法稳定外挂图例。
///   **别当死代码删** —— 这是有意留的备选。
struct UnitLegend: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(["Y", "M", "D"], id: \.self) { unit in
                Text(unit)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .allowsHitTesting(false)
    }
}

#Preview {
    NavigationStack {
        Form {
            Section("日期") {
                LabelDatePicker(title: "原始保质期", date: .constant(Date()))
                UnitLegend()
            }
        }
    }
}
