//
//  DateField.swift
//  模板页统一的日期输入控件。
//
//  ─────────────────────── 演变史（六次用户反馈） ───────────────────────
//
//  【第一轮】「选完时间后面板不收」→ 用 `.id` 重建 DatePicker 把它顶掉。
//  【第二轮】三条反馈：
//     ① 未点开是 `xxxx年xx月xx日`、选完变成 `xxxx/xx/xx`，要求统一 `xxxx/xx/xx`；
//     ② 「滚轮选完年月，马上就消失了，影响使用体验」；
//     ③ 日期单位是中文，要英文缩写 `D/M/Y`。
//     → ② 的根因就是第一轮的 `.id` 重建：滚轮每落定一个年/月/日，
//       `onChange` 就换一次 `.id`，面板当场被销毁。
//       所以**彻底删掉 `.id` 重建**。
//  【第三轮】「日期选择不应该全展开」→ 回到 `.compact`（点击后才弹出），
//     收起由 `DatePickerDismissal` 负责（点中某一天后收，带冷却窗口）。
//  【第四轮】「左侧文字全无、时间跑到左边」→ 改用 HStack 当**主布局**，
//     标题是一等公民，不再被 overlay 的宽度挤压。
//  【第五轮】「右侧日期重复排版」→ **删掉自绘 Text，只留系统 DatePicker**
//     （系统的 `xxxx年xx月xx日` 才是可点击的那个）。
//
//  【第六轮】★ 本次 —— 用户反馈：
//     「点击弹出日期选择器，操作完滚动滚轮后**马上就闪关闭界面**了，
//       需要修改为『使用完滚轮后无任何操作』」
//
//  ★★ 根因（又一次踩在同一个坑上）：
//     `DatePickerDismissal` 是挂在 `.onChange(of: date)` 上的 —— 而
//     **滚轮每滚一格 `date` 就变一次**。0.35s 冷却窗口只挡得住「连续快速触发」，
//     挡不住「用户滚动途中停手超过 0.35s」→ 面板当场被收掉。
//     用户看到的就是「滚着滚着面板自己没了」。
//
//  ★★ 正解：**彻底不再自动收起**。
//     删掉 `DatePickerDismissal`（连同这里的 `.onChange` 调用），把面板的开/关
//     完全交回系统默认行为 —— 点开弹出、点面板/屏幕其它位置收起。
//     ➜ 「使用完滚轮后无任何操作」= 我们在滚动这条路径上**一行代码都不干预**。
//
//  ⚠️ 代价：选完某一天不会自动收起，需要再点一下别处（这正是用户本轮的要求）。
//     将来若要恢复自动收，**绝对不要再走 `onChange`** ——
//     只要判据来自「date 变了」，滚轮滚动就一定会把它误触发（前两轮的同一个坑）。
//
//  ★ 显示格式仍按用户第五轮的决定：**用系统 DatePicker 自带的日期文字**，
//    不再自绘（自绘会与系统文字重复排版）。
//

import SwiftUI

/// 模板页统一的日期选择器（点击展开、**不自动收起**）。
///
/// - 形态：`.compact`（收起时只有一行，点击才弹出日历）—— 与历史版本一致。
/// - 显示：**只用系统 DatePicker 自带的日期文字**（不自绘，避免重复排版）。
/// - 收起：**完全交给系统**（点面板外收起）—— 第六轮起取消一切自动收起。
struct LabelDatePicker: View {
    let title: String
    @Binding var date: Date

    var body: some View {
        // ★ 行内两段 ——「标题」—「弹性空白」—「系统 DatePicker」。
        //   标题是真实布局元素，**不可能**再被挤没。
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.primary)
                .layoutPriority(1)          // ★ 标题优先保宽度，绝不先被压

            Spacer(minLength: 8)

            // ★ 系统 DatePicker：**自带**日期文字（可点击弹出日历）。
            //   这是这一行**唯一**的日期显示 —— 不再叠加任何自绘文字。
            //
            //  ⚠️ 第六轮起**不再挂 `.onChange` 自动收起**（原因见文件头「第六轮」）。
            //     面板的收起完全由系统负责。
            DatePicker("", selection: normalized, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .fixedSize()
        }
        .contentShape(Rectangle())
    }

    /// ★ 把外部绑定的值**规范化到当天 0 点**再喂给 DatePicker。
    ///
    /// 为什么必须做：`Date` 是带时分秒的绝对时刻，两个「同一天」的 Date
    /// 并不相等，`onChange` 会被多余的秒级抖动反复触发；
    /// 而且业务上我们**只关心日期**（`kDotsPerMM`、+N 天规则都按天算）。
    /// 统一压到 0 点后：比较稳定、写入语义干净。
    private var normalized: Binding<Date> {
        Binding(
            get: { AppCalendar.shared.startOfDay(for: date) },
            set: { date = $0 }
        )
    }

    /// `xxxx/xx/xx` —— 固定 4/2/2 位，手拼而不用 DateFormatter，
    /// 彻底绕开 locale 对格式的影响。
    ///
    /// ⚠️ **第五轮起本方法不再被视图调用**（日期显示交回系统 DatePicker，
    ///    否则会与系统文字重复排版 —— 见 `body` 的注释）。
    ///    保留它是为了「万一又要自绘」时有现成的格式化入口，
    ///    同时也是 #Preview 与未来可能的迁移参照。**不要因为"没人用"就删掉。**
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
///   当初想解决「滚轮单位是中文」，但系统 DatePicker 的 `.compact` 弹出面板
///   无法稳定外挂图例，方案搁置。**别当死代码删** —— 这是有意留的备选。
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
            LabelDatePicker(title: "原始保质期", date: .constant(Date()))
            UnitLegend()
        }
    }
}
