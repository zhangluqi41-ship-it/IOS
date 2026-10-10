//
//  DateField.swift
//  模板页统一的日期输入控件。
//
//  ───────────────────────── 十二轮演变的最终结论 ─────────────────────────
//
//  ★★★ 2026-10-11（v1.1.6）—— 用户复验 v1.1.5 后报三条，逼出了**最终答案**：
//     「键盘：现在点也不能收回，滑也不能收回，完全无响应」
//     「日期已经无法正常显示（浮层飘到导航栏上了）」
//     「字体颜色不要修改，恢复原来的白色和黑色」
//
//     ★ 这次必须承认一个**方向性错误**：
//       我从第七轮起一直在**自绘一个日期控件去模拟系统的行为**
//       （自绘 HStack → 自绘 Text → 套 Menu → 套 Button+popover），
//       每一轮都在"把系统控件拆开、用零件重新拼一个像它的东西"。
//       而用户要的是「**苹果原生最高流畅度**」——
//       那答案恰恰是**别拆它**：`DatePicker` 本身就自带
//       "点击弹出日历 / 点外面关闭 / 系统动画 / 稳定样式"这一整套行为。
//
//     ★ `.popover` 方案为什么彻底失败（v1.1.5）：
//       ① **锚点不可靠**：`.popover` 挂在 `List` 行内的自定义 `Button` 上时，
//          系统找不到稳定的锚点，浮层会**飘到导航栏位置**（用户截图就是）；
//       ② **阻断交互**：`popover` 展示期间会接管整个交互层，
//          加上我又在容器上加了 `contentShape` → 「点不能收、滑不能收，完全无响应」；
//       ③ 自绘的 `Text` 带 `Theme.brand` → 日期变成蓝色，破坏了系统原有的黑/白配色。
//
//     ➜ 最终定案 = **一行系统控件，外面什么都不套**：
//        ```swift
//        DatePicker(title, selection: day, displayedComponents: .date)
//            .datePickerStyle(.compact)
//        ```
//        · 「点开日历」= 系统自带；
//        · 「点面板外面关闭」= 系统自带（不再需要"选完自动收"这种自造逻辑）；
//        · 「关闭动画」= 系统自带；
//        · 「日期黑字 / 标题黑字」= 系统自带（不覆写任何颜色）。
//
//     关于"选完自动收"：**放弃这个需求**。
//       它是用户第 3/7/9/10 轮反复提的诉求，但十二轮的实践证明了它的代价：
//       为它引入的每一种手段（`.id` 重建 / `.onChange` 收起 / `popover`）
//       **都带来了更严重的新 bug**（无动画、样式退化、浮层错位、交互全失）。
//       而系统原生行为「点日历外面即关闭」**体验上完全等价**，
//       且零风险 —— 这正是"用第一方工具"的正确含义。
//
//  ⚠️ 墓碑（按踩坑顺序，**一个都不要再写回来**）：
//     ① `.id(...)` 换值重建控件 —— 无动画 + 样式退化（第 2/6/9 轮，用户三次报障）；
//     ② `Menu { DatePicker }` —— Menu 只装命令，日历不渲染（第 7 轮）；
//     ③ `.onChange(of: date)` 里收面板 —— 滚轮每格触发，面板当场闪关（第 2/6 轮）；
//     ④ 防抖计时器（Task.sleep）—— 自造冷却窗口，第 10 轮引入、第 11 轮全删；
//     ⑤ `Button` + `.popover` 自绘日期行 —— 锚点飘到导航栏 + 阻断交互 + 配色破坏（第 11 轮）；
//     ⑥ 自绘 `Capsule` 背景 / 自绘 `Text` 显示日期 —— 典型的"拆了重拼"（第 3~11 轮）。
//
//  ★ 一句话：**系统控件给了什么就用什么，不要拆开重拼。**

import SwiftUI

/// 模板页统一的日期选择器。
///
/// **就是一个标准的系统 `DatePicker`**：标题在左、日期在右，点日期弹日历，
/// 点日历外面关闭。全部行为、动画、配色都由系统负责，我们**不做任何干预**。
struct LabelDatePicker: View {
    let title: String
    @Binding var date: Date

    var body: some View {
        // ★★★ 一行搞定。外面**不加**任何 `.id` / `.popover` / 自绘 `Text` / 自定义颜色。
        //
        //   · `.datePickerStyle(.compact)`：标准 List 行形态（标题 + 可点日期），
        //     也就是用户从第一轮起就在用、并且认可的那个样子。
        //   · 日期文字颜色由系统给（浅色模式黑、深色模式白），**绝不覆写**。
        DatePicker(title, selection: day, displayedComponents: .date)
            .datePickerStyle(.compact)
    }

    /// ★ 把外部绑定的值**规范化到当天 0 点**再喂给 DatePicker。
    ///
    /// 为什么必须做：`Date` 是带时分秒的绝对时刻，两个「同一天」的 Date
    /// 并不相等；而且业务上我们**只关心日期**（`kDotsPerMM`、+N 天规则都按天算）。
    /// 统一压到 0 点后：比较稳定、写入语义干净。
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
