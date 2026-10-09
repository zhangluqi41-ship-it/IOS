//
//  DateField.swift
//  模板页统一的日期输入控件。
//
//  ─────────────────────── 演变史（三次用户反馈） ───────────────────────
//
//  【第一轮】「选完时间后面板不收」→ 用 `.id` 重建 DatePicker 把它顶掉。
//  【第二轮】三条反馈：
//     ① 未点开是 `xxxx年xx月xx日`、选完变成 `xxxx/xx/xx`，要求统一 `xxxx/xx/xx`；
//     ② 「滚轮选完年月，马上就消失了，影响使用体验」；
//     ③ 日期单位是中文，要英文缩写 `D/M/Y`。
//     → ② 的根因就是第一轮的 `.id` 重建：滚轮每落定一个年/月/日，
//       `onChange` 就换一次 `.id`，面板当场被销毁。
//       所以**彻底删掉 `.id` 重建**，改用 `DatePickerDismissal`；
//       ①③ 则把显示层拿回自己手里（自绘 `xxxx/xx/xx` + `UnitLegend`）。
//  【第三轮】★ 本次 —— 用户又提：「日期选择不应该全展开啊，应该是点击后全展开，
//     和之前一样，怎么突然改了这么多？」
//
//  ★★ 为什么「全展开」是我上一轮闯的祸：
//     为了让自绘的 `xxxx/xx/xx` 与系统文字不打架，我上一轮把样式改成了
//     `.graphical`（日历直接铺满）。这等于**永久占据一大块表单高度**，
//     把原本紧凑的模板页撑得面目全非 —— 正是用户说的「全展开」。
//
//  ★★ 本次正解：回到 `.compact`（点击后才弹出），但**不再用 `.id` 重建**。
//     收起由 `DatePickerDismissal` 负责（见该文件），它只做一件事：
//     用户点中某一天之后，把已经弹出的浮层收掉；翻年翻月不会被打断。
//     ➜ 「点击后展开」与「选完自动收起」两者终于可以同时成立。
//
//  ★ 显示格式仍然固定为 `xxxx/xx/xx`：
//     `.compact` 态系统那行文字同样受 `\.locale` 影响（会渲染成
//     「2026年10月9日」），所以照旧 `.labelsHidden()` 藏掉它，
//     用自己排的 Text 顶上去 —— 收起 / 展开前后逐字一致。
//
//  ★ 单位仍然是英文缩写 `D / M / Y`（`UnitLegend`）。
//     滚轮里的中文单位由 locale 决定，SwiftUI 没给「只换单位」的口子，
//     所以把 `Y / M / D` 直接**画在弹出面板的下方**作为图例。
//
//  ⚠️ 刻意**不动全局 locale** —— 那会连月份、星期、其它控件一起改，
//     是「为了一个控件改全站」的高风险动作。
//

import SwiftUI

/// 点击展开、选完自动收起的日期选择器。
///
/// - 形态：`.compact`（收起时只有一行，点击才弹出日历）—— 与历史版本一致。
/// - 显示：`.labelsHidden()` + 自绘 `xxxx/xx/xx`（固定 4/2/2 位，与标签一致）。
/// - 收起：靠 `DatePickerDismissal`（选中某一天后收），**不再重建视图**。
/// - 单位：面板下方画 `Y / M / D` 图例（见 `UnitLegend`）。
struct AutoCloseDatePicker: View {
    let title: String
    @Binding var date: Date

    var body: some View {
        DatePicker(title, selection: normalized, displayedComponents: .date)
            // ★ 系统文字同样跑 locale，会渲染成「2026年10月9日」——
            //   与下面自绘的 `xxxx/xx/xx` 打架，所以藏掉。
            .labelsHidden()
            .datePickerStyle(.compact)
            .overlay(alignment: .leading) {
                // ★ 用 overlay 顶一行自绘文字，替掉被隐藏的系统 label。
                //   这样「标题 + xxxx/xx/xx」这一行的排版完全由我们掌控，
                //   且右侧留给系统的 compact 日期按钮（点击弹出）。
                //   `.allowsHitTesting(false)` 保证不吃掉点击 —— 否则点不到
                //   系统那个日期按钮，面板就弹不出来。
                HStack {
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(Self.text(for: date))
                        .monospacedDigit()
                        .foregroundStyle(Theme.brand)
                    // 给系统的 compact 按钮留出位置（它渲染在 overlay 之下的右侧）。
                    Color.clear.frame(width: 84)
                }
                .allowsHitTesting(false)
            }
            .onChange(of: date) { _, _ in
                // ★ 用户点中「某一天」→ 收起弹出的日历。
                //   翻年翻月也走这里，但 `DatePickerDismissal` 内部有冷却窗口，
                //   不会把「翻月」误判成「选完了」。
                DatePickerDismissal.dismissAfterSelection()
            }
    }

    /// ★ 把外部绑定的值**规范化到当天 0 点**再喂给 DatePicker。
    ///
    /// 为什么必须做：`Date` 是带时分秒的绝对时刻，两个「同一天」的 Date
    /// 并不相等，`onChange` 会被多余的秒级抖动反复触发；
    /// 而且业务上我们**只关心日期**（`kDotsPerMM`、+N 天规则都按天算）。
    /// 统一压到 0 点后：比较稳定、`onChange` 语义干净。
    private var normalized: Binding<Date> {
        Binding(
            get: { AppCalendar.shared.startOfDay(for: date) },
            set: { date = $0 }
        )
    }

    /// `xxxx/xx/xx` —— 固定 4/2/2 位，手拼而不用 DateFormatter，
    /// 彻底绕开 locale 对格式的影响（这也正是需求①要的）。
    static func text(for date: Date) -> String {
        let c = AppCalendar.shared
        let y = c.component(.year, from: date)
        let m = c.component(.month, from: date)
        let d = c.component(.day, from: date)
        return String(format: "%04d/%02d/%02d", y, m, d)
    }
}

/// 日期单位图例：英文缩写 `Y / M / D`（需求③）。
///
/// ★ 为什么要单独做一个 `UnitLegend` 而不是塞进 DatePicker 里：
///   系统滚轮的单位文字由 locale 决定（`zh_Hans_CN` → 年/月/日），
///   SwiftUI 没有提供「只换单位不换 locale」的口子。
///   所以做法是在**弹出面板下方压一排自己的标签**。
///
/// ⚠️ 顺序按中文区域滚轮的实际呈现（年 / 月 / 日）标注为 `Y / M / D`。
///   若真机上顺序不符，只改这里的数组。
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
    Form {
        Section("日期") {
            AutoCloseDatePicker(title: "原始保质期", date: .constant(Date()))
            UnitLegend()
        }
    }
}
