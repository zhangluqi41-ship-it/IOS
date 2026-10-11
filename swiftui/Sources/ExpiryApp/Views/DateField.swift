//
//  DateField.swift
//  模板页统一的日期输入控件。
//
//  ─────────────────────── 十三轮演变的最终结论（v1.1.7） ───────────────────────
//
//  ★★★ 2026-10-11（第二十三轮）—— 用户复验 v1.1.6 后报：「现在点击日期后也不收回日历选项了」
//
//     背景：第 22 轮我做了两件事，其中一件**做对了**、另一件**做过头了**。
//
//     ✔ 做对了：不再"把系统控件拆开重拼"（`.buttonStyle` 自绘 / `Menu` /
//       `Button`+`.popover` 全部删掉），回归一行原生 `DatePicker(.compact)`。
//       好处是**样式、配色、日历浮层外观**全部回到系统原生 —— 这一步用户认可。
//
//     ✘ 做过头了：我顺手把「**选完自动收**」这个需求整个**放弃**了。
//       当时的理由是"系统原生『点日历外面即关闭』体验等价"。
//       但用户复验后明确指出「点击日期后也不收回」—— 这个理由**站不住**：
//         · 原生 `.compact` 浮层在 `List` 行里会**飘到屏幕上方盖住内容**（用户截图）；
//         · 用户点完日期，手是停在浮层里的，要关它必须**再去找浮层外面**点一下，
//           而且浮层盖住了内容，视觉上"点哪都像在浮层里" → 体验很差。
//       ➜ 所以「选完自动收」是**真实需求**，必须实现。
//
//  ★★★ 实现的关键约束（这是十三轮踩坑换来的）：
//
//    ① **绝不能重建控件**（`.id()` 换值 = 销毁重建）——
//       第 2/6/9/11 轮三次栽在这里：重建会连带**销毁正在弹出的浮层**，
//       表现就是"面板瞬间闪关、无动画"，而且 UIKit 侧来不及恢复样式（格式退化）。
//       ➜ 所以收浮层必须走"**让控件自己收**"，而不是"换掉控件"。
//
//    ② `DatePicker` 的 SwiftUI 层**没有**控制浮层开关的 API。
//       唯一可靠的第一方手段 = **让它的焦点消失**。
//
//    ③ 于是正解 = `@FocusState` + `focused(_:)`：
//       点中某一天 → `selection` 真的变了 → 把焦点置 `nil`
//       → 系统**自己**播它的收起动画（不是我们"关掉"它）。
//       ⚠️ 判据必须是「**值真的变了**」，不能是"打开着就收"：
//          `DatePicker(.compact)` 的浮层在**不选任何日期**时也可能因为
//          别的交互被系统收走，用"值变了"当判据就天然不会误伤。
//
//    ④ 只读**规范化后的「天」**做比较 —— 避免"点同一天又触发一次收起"。
//
//  ⚠️ 墓碑（按踩坑顺序，**一个都不要再写回来**）：
//     ① `.id(...)` 换值重建控件 —— 无动画 + 销毁浮层 + 样式退化（第 2/6/9/11 轮）；
//     ② `Menu { DatePicker }` —— Menu 只装命令，日历不渲染（第 7 轮）；
//     ③ 防抖计时器（Task.sleep）—— 自造冷却窗口（第 10/11 轮）；
//     ④ `Button` + `.popover` 自绘日期行 —— 锚点飘到导航栏 + 阻断交互 + 破坏配色（第 11 轮）；
//     ⑤ 自绘 `Text` 显示日期 / 自绘 `Capsule` 背景 —— 拆了重拼（第 3~11 轮）；
//     ⑥ `.buttonStyle(.bordered/.borderedProminent)` 当日期 chip —— 蓝底蓝字（第 22 轮）。
//
//  ★ 一句话：**外观交给系统原生，行为（选完就收）用 `@FocusState` 补。**
//

import SwiftUI

/// 模板页统一的日期选择器。
///
/// **外观是完全原生的 `DatePicker(.compact)`**（标题在左、日期在右，点日期弹日历），
/// 唯一的补充行为是：**选中某一天后，自动让日历收回**。
struct LabelDatePicker: View {
    let title: String
    @Binding var date: Date

    /// ★ 给这个 `DatePicker` 一个独立的焦点位。
    ///
    /// 它**不是"输入焦点"**（日期不是文本），我们只用它做一件事：
    /// 在用户选完日期后 `focus = nil`，让系统播浮层收起的动画。
    /// ⚠️ 每个 `LabelDatePicker` 各自持有一个 `@FocusState` —— 一页里有两个日期行时，
    ///    它们必须互不干扰（各自收各自的浮层）。
    @FocusState private var isFocused: Bool

    var body: some View {
        DatePicker(title, selection: day, displayedComponents: .date)
            .datePickerStyle(.compact)
            // ★ 把这个控件的"焦点"绑出来 —— 收浮层靠它。
            .focused($isFocused)
            .onChange(of: day.wrappedValue) { _, _ in
                // ★★★ 关键：日期**真的变了**才收（见文件头约束③④）。
                //
                //   `day` 是"规范化到当天 0 点"的绑定，所以：
                //     · 用户点中另一天  → 值变 → 收起 ✔
                //     · 用户点中的是当前这天 → 值没变 → 不收（避免"点了没反应却抖一下"）
                //     · 系统因别的原因收起 → 不经过这里 → 不受影响
                //
                //   ⚠️ 不写 `Task.sleep` / 防抖：`selection` 只在"点到某一天"时才变，
                //      翻月份、滚年份都**不碰它** → 天然不会误收，不需要冷却窗口。
                if isFocused { isFocused = false }
            }
    }

    /// ★ 把外部绑定的值**规范化到当天 0 点**再喂给 `DatePicker`。
    ///
    /// 为什么必须做：`Date` 是带时分秒的绝对时刻，两个「同一天」的 Date 并不相等；
    /// 而且业务上我们**只关心日期**（`kDotsPerMM`、+N 天规则都按天算）。
    /// 统一压到 0 点后：比较稳定、写入语义干净、`onChange` 的"值变了"判据才准确。
    private var day: Binding<Date> {
        Binding(
            get: { AppCalendar.shared.startOfDay(for: date) },
            set: { date = $0 }
        )
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
