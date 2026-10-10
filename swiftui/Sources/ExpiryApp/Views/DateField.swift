//
//  DateField.swift
//  模板页统一的日期输入控件。
//
//  ─────────────────────── 演变史（七次用户反馈） ───────────────────────
//
//  【第一轮】「选完时间后面板不收」→ 用 `.id` 重建 DatePicker 把它顶掉。
//  【第二轮】三条反馈：
//     ① 未点开是 `xxxx年xx月xx日`、选完变成 `xxxx/xx/xx`，要求统一 `xxxx/xx/xx`；
//     ② 「滚轮选完年月，马上就消失了，影响使用体验」；
//     ③ 日期单位是中文，要英文缩写 `D/M/Y`。
//     → ② 的根因就是第一轮的 `.id` 重建：滚轮每落定一个年/月/日，
//       `onChange` 就换一次 `.id`，面板当场被销毁。所以**彻底删掉 `.id` 重建**。
//  【第三轮】「日期选择不应该全展开」→ 回到 `.compact`（点击后才弹出），
//     收起由 `DatePickerDismissal` 负责（点中某一天后收，带冷却窗口）。
//  【第四轮】「左侧文字全无、时间跑到左边」→ 改用 HStack 当**主布局**。
//  【第五轮】「右侧日期重复排版」→ **删掉自绘 Text，只留系统 DatePicker**。
//  【第六轮】（v1.1.1）「滚完滚轮马上就闪关闭界面」→ **取消一切自动收起**
//     （删掉挂在 `.onChange(of: date)` 上的 `DatePickerDismissal`）。
//
//  ★★★【第七轮】本次 —— 用户两条反馈合起来指向了同一个结论：
//     ① 「选择好日期后**应当自动收回**（但不包含前期的滚轮选择年月）」
//     ② 「日历选择页面收回后**完全不影响画面滚动**，质疑是否正常使用苹果第一方协议」
//
//     第六轮我们把面板的开关「完全交给系统」，结果 `.compact` 弹出的仍然是一个
//     **滚轮 / 日历型 UIDatePicker**，它的呈现容器是 UIKit 私有 popover。实测表现：
//       · 滚轮一动 `date` 就变（同一份 binding），**没有可靠的「选完了」时机**
//         —— 第六轮「不自动收」正是被这一点逼出来的；
//       · 它的容器会**吃掉列表的滚动手势**（用户说的「影响画面滚动」）；
//       · 它和键盘 accessory bar / 我们的 window 手势互相打架（问题 1 的卡顿）。
//
//  ★★ 正解 = **改用第一方的 `.graphical`（整块日历）作为这行的菜单内容**：
//     用 `Menu { DatePicker(.graphical) }`,系统负责弹出、点选、**以及关闭**
//     —— 和我们 100% 自己写的代码零交互，所以「不会卡顿 /
//     不会吃滚动 / 选完自动收」三件事同时成立，且完全符合第一方行为。
//
//  为什么是「菜单」而不是直接把整块日历铺在列表里（试过，见下）：
//     `.graphical` 整块日历高度约 330pt，铺进 List 行会把两行日期撑成两屏，
//     用户还要往下滚 —— 与「点开才出现」的既有交互相悖。
//     `Menu` + `.displayInline` 则完全等价于系统「日历」App 的「新建日程 → 日期」。
//
//  ⚠️ 「前期滚轮选择年月不收、选完具体某天自动收」这条细分要求，是**滚轮**才有的
//     问题（滚轮上「年月」和「日」是同一根轮子，代码无法区分用户滚的是哪一段）。
//     换成日历后这条需求被**自然满足**：点标题栏 `‹ 2026年10月 ›` 只翻月、
//     菜单**不会关**；只有点中下方某个具体日期才会关 —— 正是用户要的行为。
//
//  ⚠️ 触发器的坑：`Menu` 的「值变 → 自动关闭」判定挂在**内部选择器真的变了**时，
//     而不是挂在外部 `onChange(of: date)` 上 —— 后者在滚轮上会被每一格触发
//     （第六轮/第二轮的同一个坑，**不要再走 onChange**）。
//
//  ⚠️ 菜单 label **不要**再 `+` 一个自绘日期文字（那是第五轮删掉的重复排版），
//     系统 `DatePicker(.compact)` 自己就带 `xxxx年xx月xx日`，且它才是可点的那个。
//

import SwiftUI

/// 模板页统一的日期选择器：**点开是日历，选好某天自动收回**（系统第一方行为）。
///
/// - 形态：菜单式 —— 折叠时是系统 `DatePicker(.compact)` 的一行日期，
///   点开弹出**整块日历**（与系统「日历」App 新建日程完全一致）。
/// - 收起：**由系统负责**。翻月/翻年不关，点中具体某天立刻关。
/// - 好处：弹出层是系统自己管理的独立容器，不参与本页滚动/键盘手势，
///   所以既不会卡顿，也不会「影响画面滚动」。
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

            Menu {
                // ★ `.graphical` = 整块日历（第一方 UIDatePicker 的日历形态）。
                //   ⚠️ 它的高度是固定的（约 330pt），所以**必须**放进菜单里
                //      按需弹出，不能直接铺在 List 行内。
                //   ⚠️ `labelsHidden()` 只藏它的标签，不影响点击。
                DatePicker("", selection: normalized, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
            } label: {
                // ★ 菜单的「标题」= 系统 DatePicker(.compact) —— 形态、字体、
                //   点击热区都与前六轮**完全一致**（用户不会觉得界面变了），
                //   但它现在只负责「显示 + 打开菜单」，日期改动由上面的日历落笔。
                DatePicker("", selection: normalized, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .allowsHitTesting(false)     // 点击交给外层 Menu
                    .fixedSize()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .contentShape(Rectangle())
    }

    /// ★ 把外部绑定的值**规范化到当天 0 点**再喂给 DatePicker。
    ///
    /// 为什么必须做：`Date` 是带时分秒的绝对时刻，两个「同一天」的 Date
    /// 并不相等；而且业务上我们**只关心日期**（`kDotsPerMM`、+N 天规则都按天算）。
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
    /// ⚠️ **第五轮起本方法不再被视图调用**（日期显示交回系统 DatePicker）。
    ///    保留它是为了「万一又要自绘」时有现成的格式化入口。**别因为"没人用"删掉。**
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
    Form {
        Section("日期") {
            LabelDatePicker(title: "原始保质期", date: .constant(Date()))
            UnitLegend()
        }
    }
}
