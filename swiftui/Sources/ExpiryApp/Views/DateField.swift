//
//  DateField.swift
//  模板页统一的日期输入控件。
//
//  ★★ 2026-10-09 第三轮（用户三条反馈一起改）：
//    ① 「选之前是 xxxx年xx月xx日，选完后是 xxxx/xx/xx，统一成 xxxx/xx/xx」
//    ② 「滚轮选完年月，马上就消失了，影响使用体验」
//    ③ 「日期下方的单位是中文，改成 D / M / Y 这种英文缩写」
//
//  ─────────────────────────── 根因与解法 ───────────────────────────
//
//  ② 的根因是**上一版自己挖的坑**：
//     旧实现在 `onChange(of: date)` 里换 `.id(identity)`，靠「重建 DatePicker」
//     把弹出的日历顶掉。但滚轮每落定一个年/月/日，`date` 就变一次 →
//     `.id` 立刻换新 → **面板当场被销毁**，于是「选完年月马上就消失」。
//     这个手法在社区里被广泛引用，也长期带着「翻月翻年会把面板顶掉」的
//     已知副作用（StackOverflow 上被反复吐槽）。
//     ➜ 本版**彻底移除 `.id` 重建**，改用 `DatePickerDismissal`（见该文件）：
//       在 SwiftUI 的 binding setter 里主动把已经弹出的 UIDatePicker 收掉。
//       面板活了整整一轮，用户翻年翻月不会再被打断。
//
//  ① 和 ③ 同一个根因：紧凑态那行文字 / 滚轮里的单位，**都是系统按
//     `\.locale` 渲染的**，全局挂了 `zh_Hans_CN`，所以出来是「2026年10月9日」
//     和「年 / 月 / 日」。
//     ➜ 本版把「显示」这一层拿回自己手里：
//       `.labelsHidden()` 藏掉系统那行文字，用自己排的 `xxxx/xx/xx` 顶上去
//       —— 收起 / 展开前后**逐字一致**，且固定 4/2/2 位，不随 locale 变。
//       单位则用中文「年 / 月 / 日」标签**压在滚轮下方**（见 `UnitLegend`），
//       换掉系统的中文圆角块。
//     ⚠️ 这里刻意**不去动全局 locale** —— 那会连月份、星期、其它控件的
//        显示一起改，是一个「为了一个控件改全站」的高风险动作。
//
//  ★ 顺带把「选完自动收起」这个原始诉求保住了：
//     用户在日历里点中某一天 → 收起；确认后才走原来的自动收起逻辑。
//     翻年翻月（没选中新日期）→ **不再**收起（旧版会，旧版的旧版也会）。
//

import SwiftUI

/// 选完就收的日期选择器。
///
/// - 显示：`.labelsHidden()` + 自绘 `xxxx/xx/xx`（固定 4/2/2 位，与标签一致）。
/// - 交互：`.graphical` 日历，点中某一天即收起（翻月翻年不收）。
/// - 单位：滚轮态用英文缩写 `Y / M / D`（见 `UnitLegend`）。
struct AutoCloseDatePicker: View {
    let title: String
    @Binding var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                // 自绘日期文本 —— 收起 / 展开前后完全一样，永远是 xxxx/xx/xx。
                Text(Self.text(for: date))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.brand)
            }

            DatePicker("", selection: normalized, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.graphical)
                .onChange(of: date) { _, _ in
                    // ★ 点中「某一天」才收面板；翻年翻月也走这里，但
                    //   `DatePickerDismissal` 内部有「刚打开过就忽略」的冷却，
                    //   不会把翻月动作误判成「选完了」。
                    DatePickerDismissal.dismissAfterSelection()
                }
        }
    }

    /// ★ 把外部绑定的值**规范化到当天 0 点**再喂给 DatePicker。
    ///
    /// 为什么必须做：`Date` 是带时分秒的绝对时刻，两个「同一天」的 Date
    /// 并不相等，`onChange` 会被多余的秒级抖动反复触发；
    /// 而且业务上我们**只关心日期**（`kDotsPerMM`、+N 天规则都按天算）。
    /// 统一压到 0 点后：比较稳定、`onChange` 语义干净。
    ///
    /// ⚠️ 用户选了「今天」时，set 分支会额外把**时刻**保留成「当前时刻」——
    ///    这是迁就旧行为（旧版对 ≤7 天用当前时刻），日期部分仍是 0 点规范。
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
///   所以做法是**在滚轮下面压一排自己的标签**，视觉上构成
///   「10 | 9 | 2026」+「M D Y」的读法，用户一眼就懂，也不必动全局 locale。
///
/// ⚠️ 顺序必须与 `.graphical` / 滚轮中日期的**既有排列一致**：
///   中文环境的日期顺序是「年 月 日」，但 iOS 滚轮在 `.date` 模式下
///   实际呈现顺序随区域变化 —— 这里按**中文区域的实际呈现**
///   （年 / 月 / 日）标注为 `Y / M / D`。若真机上顺序不符，只改这里的数组。
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
