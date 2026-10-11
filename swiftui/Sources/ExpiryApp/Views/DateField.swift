//
//  DateField.swift
//  模板页统一的日期输入控件。
//
//  ───────────── 十四轮演变的最终结论（v1.1.9 · 路线 B 定案） ─────────────
//
//  ★★★ 2026-10-11（第二十五轮）—— 用户拍板走「路线 B」：
//
//      「直接上 b，但是你要自己检查全部代码，不要出现问题」
//
//  背景：v1.1.7 我押注「`@FocusState` + `.focused` 让它自己收」，**赌输了**。
//        v1.1.8 交付键盘修复后，用户开始处理日历，我逐行读代码找出了真根因：
//
//      ★★★ **`DatePicker` 根本不参与 SwiftUI 的焦点系统。**
//          苹果官方文档对 `.focused(_:)` 的定义是「视图**去争抢焦点**时更新绑定」
//          （"When focus moves to the view, the binding sets the bound value to `true`"）。
//          文本输入控件（`TextField` / `TextEditor` / `SecureField`）会去争抢焦点，
//          所以它们才有效；**`DatePicker` 不是输入控件**，永远不会争抢焦点
//          → `isFocused` **永远是 `false`**
//          → `if isFocused { isFocused = false }` **永远不执行**
//          → 「选完自动收」的代码从写下的那一刻起就是一行死代码。
//          ➜ 这正是「我加了这段代码 ≠ 这段代码在起作用」的又一例证（第 23/24 轮同病）。
//
//  ───────────────────────── 为什么最终选路线 B ─────────────────────────
//
//  用户的硬要求有两条：**「最高的苹果流畅度」** + **「全部用第一方工具」**。
//  而「日期选完自动收」这个需求，在原生 `.compact` 上**根本无法实现**：
//
//    · `.compact` 弹出的是 UIKit **私有**面板
//      （`_UIDatePickerIOSCompactViewController`），苹果**从未公开**关闭它的 API。
//      业界权威答案原话："I see no documented way of doing this right now."
//    · 苹果 HIG 是**有意**设计成「点外面确认」的：
//      "people can make multiple edits to dates and times before tapping outside
//       the view to confirm their choices."
//      ➜ 也就是说，「选完自动收」在 `.compact` 上是**逆着系统设计**走，只能靠歪招
//        （历史第 2/6/9/11 轮 = `.id()` 重建控件 → 无动画 + 样式退化，用户三次报障）。
//
//  ➜ 于是唯一诚实的做法 = **换一套公开的、可控的第一方 API**：
//
//      ★★★ 定案 = `.popover` + `DatePicker(.graphical)`（路线 B）
//
//        ① `.popover` 是**公开的第一方弹层**，`isPresented` 由我们掌握
//           → 选完直接 `showing = false` → 走的是**系统自己的 popover 转场动画**。
//           我们没有"中途插一脚"，而是**从源头就按系统的模型来**（这正是流畅度的来源）。
//        ② `.graphical` 是**公开的日历样式**，不依赖任何私有实现 →
//           不存在"重建后样式退化"。
//        ③ 主行 = 普通 `Button`，与 `List` 滚动、与收键盘 overlay 都**不冲突**。
//        ④ 日期文字用**系统语义色**（`.primary`），不碰 `Theme.brand`
//           —— 用户明确说过"日期文字是系统黑/白，不是蓝色"。
//
//  ─────────────── ⚠️ 第 11 轮（v1.1.5）用同一套 API 为什么失败 ───────────────
//
//  上一版是这么写的（`git show 6bfc114` 可查）：
//
//      .popover(isPresented: $showing, arrowEdge: .bottom) { ... }
//
//  **三个具体的错**，本版逐条修掉：
//
//    ① `arrowEdge: .bottom` 把浮层**推向屏幕上方**。
//       苹果文档：`arrowEdge` = "The edge of the attachmentAnchor that defines the
//       location of the popover's arrow." —— 箭头在浮层的**下边**，
//       意味着浮层要放在锚点**上方**。而这两行日期都排在屏幕**上半部**，
//       上方空间不够 → 系统只好硬塞 → 看起来"飘到导航栏"。
//       ➜ **本版完全不给 `arrowEdge`**，让系统按可用空间自己挑最优方向（这才是原生行为）。
//
//    ② 锚点太小、太靠内。`List` 行里那个 `Button` 的实际布局框只有文字那么高（~20pt），
//       浮层要以这么窄的一条为基准算位置。
//       ➜ 本版给主行**明确的满宽 + 标准行高**（`.frame(maxWidth: .infinity, minHeight: 24)`
//         + `.contentShape(Rectangle())`），锚点是一个稳定、方正的区域。
//
//    ③ 日期文字用了 `Theme.brand`（蓝）→ 用户报"颜色不对"。
//       ➜ 本版用 `.primary`（系统标签色，深色模式下自动变白）。
//
//  ───────────────────────────── 墓碑（一个都别再写回来） ─────────────────────────────
//
//   ① `.id(...)` 换值重建控件 —— 无动画 + 销毁浮层 + 样式退化（第 2/6/9/11 轮）；
//   ② `Menu { DatePicker }` —— Menu 只装命令，日历根本不渲染（第 7 轮）；
//   ③ 防抖计时器（`Task.sleep`）—— 自造冷却窗口（第 10/11 轮）；
//   ④ **`@FocusState` + `.focused` 收 `DatePicker` 的浮层** —— 死代码，
//      `DatePicker` 不参与焦点系统（第 23 轮，本版刚刚证伪）；
//   ⑤ `.compact` + 私有面板 —— 关不掉，只能靠歪招（第 8/9 轮）；
//   ⑥ `arrowEdge: .bottom` 硬编码 —— 会把浮层推向错误方向（第 11 轮）；
//   ⑦ 日期文字用 `Theme.brand` —— 用户要的是系统黑/白（第 11/22 轮）；
//   ⑧ `.background(手势层)` —— 被不透明的 `List` 遮住，收不到触摸（第 23 轮）。
//
//  ★ 一句话：**「关不掉某个系统弹层」的困境，正解是换一个公开、可控的第一方 API，
//    而不是用重建控件的歪招。**
//

import SwiftUI

/// 模板页统一的日期选择器。
///
/// **交互**：点整行 → 弹出系统日历浮层（`.graphical`）→ 点中某一天 → **带动画自动收起**。
/// **实现**：全程只用第一方公开 API —— `Button` + `.popover` + `DatePicker(.graphical)`
///          + `Text(_:format:)`。零自造控件、零重建、零定时器。
struct LabelDatePicker: View {
    let title: String
    @Binding var date: Date

    /// 日历浮层是否展开。
    ///
    /// ★ 这正是"能自动收起"的全部秘密：`popover` 的开关**归我们管**
    ///   （对比 `.compact` 的私有面板 —— 那个苹果不给 API）。
    @State private var showing = false

    /// ★ 把外部绑定的值**规范化到当天 0 点**再喂给 `DatePicker`。
    ///
    /// 为什么必须做：`Date` 是带时分秒的绝对时刻，两个「同一天」的 Date 并不相等；
    /// 业务上也**只关心日期**（`kDotsPerMM`、+N 天规则都按天算）。
    /// 统一压到 0 点后：比较稳定、写入语义干净、`onChange` 的「值变了」判据才准确。
    private var day: Binding<Date> {
        Binding(
            get: { AppCalendar.shared.startOfDay(for: date) },
            set: { date = $0 }
        )
    }

    /// 日期文字的展示格式：`2026/10/30`。
    ///
    /// ★ 用**第一方 `FormatStyle`**，而不是自己拼字符串 —— 补零 / locale / 公历
    ///   它自带，并且天然与系统语言环境一致（用户从第二轮起就要求统一斜杠格式）。
    /// ⚠️ 别用 `Text(date, format: .dateTime…)` 的"年月日"写法 —— 中文环境下
    ///   会输出「2026年10月30日」，不是用户要的斜杠形式。
    private static let slashy = Date.FormatStyle(date: .numeric, time: .omitted)
        .year().month().day()

    var body: some View {
        Button {
            showing = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                // ★ 日期文字 = **系统标签色**（浅色下黑、深色下白），不是品牌蓝。
                Text(day.wrappedValue, format: Self.slashy)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            // ★ 满宽 + 明确行高：给 `.popover` 一个**稳定、方正**的锚点区域
            //   （第 11 轮浮层飘走的成因之一就是锚点太窄）。
            .frame(maxWidth: .infinity, minHeight: 24)
            // ★ 撑满矩形，保证整行都能点中。
            .contentShape(Rectangle())
        }
        // ★ `.plain`：不要给文字染上系统强调色（那会变成"蓝字白底按钮"，
        //   和用户要的"系统黑/白"冲突）。
        .buttonStyle(.plain)
        // ★★★ 第一方弹层。`isPresented` 归我们掌控 → 能主动、带动画地收起。
        //   ⚠️ **不传 `arrowEdge`** —— 交给系统按可用空间自己挑方向（原生行为）。
        //     硬编码 `.bottom` 会把它推到锚点上方，屏幕上半部的行就会"飘到导航栏"。
        .popover(isPresented: $showing) {
            DatePicker(title, selection: day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
                // ★ iPhone 上 `.popover` 默认会自适应成 sheet（半屏卡），
                //   必须用 `.presentationCompactAdaptation(.popover)`（iOS 16.4+）
                //   强制保持「浮层 + 箭头」的原生形态。
                .presentationCompactAdaptation(.popover)
                .onChange(of: day.wrappedValue) { _, _ in
                    // ★★★ 收起判据 = **规范化后的「天」真的变了**。
                    //
                    //   `day` 的 get 端已经 `startOfDay`，所以：
                    //     · 点中另一天        → 值变 → 收起 ✔
                    //     · 点中的是当前这天  → 值不变 → 不收（避免"点了没反应却抖一下"）
                    //     · 左右翻月 / 滚年份 → `selection` 不参与 → **不受影响**
                    //       （这正是当年"防抖计时器"想解决的问题，用"值变了"当判据天然解决）
                    //     · 浮层刚弹出        → `onChange` 不对初值触发 → 不会被自己关掉
                    //
                    //   ⚠️ 不写 `Task.sleep` / 防抖：不需要冷却窗口。
                    //   ⚠️ 绝不重建控件、绝不 `.id()`。
                    showing = false
                }
        }
    }
}

/// 日期单位图例：英文缩写 `Y / M / D`。
///
/// ⚠️ **从未接入任何真实页面**（只在 `#Preview` 里出现过）。保留原因：
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
                LabelDatePicker(title: "最佳使用时间", date: .constant(Date()))
                UnitLegend()
            }
        }
    }
}
