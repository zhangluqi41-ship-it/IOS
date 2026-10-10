//
//  DateField.swift
//  模板页统一的日期输入控件。
//
//  ─────────────────────── 演变史（八次用户反馈） ───────────────────────
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
//  【第七轮】（v1.1.2）「选好日期应自动收 + 质疑第一方」→ 改成
//     `Menu { DatePicker(.graphical) }`。→ **打脸**：方案错，产生了本轮的重大 bug。
//
//  ★★★【第八轮】本次（v1.1.3）—— 用户两个反馈：
//     ① 「日期选择**点击完全不弹出日历选择**，重大 bug」
//     ② 「收回键盘是**瞬间收回、并无流畅动画**，质疑是否第一方」
//
//     ★★ ① 的根因是**多因一果**，两条都得修：
//
//     【A·结构错】上一轮把日历塞进了 `Menu`：
//         `Menu { DatePicker(.graphical) }`
//         `Menu` 的内容区是**命令列表**（Button / Toggle / Picker…），
//         不是任意视图宿主 —— 塞一个完整 `DatePicker` 进去，
//         它**根本不会渲染成日历**，所以「点了完全没反应」。
//
//     【B·手势被吞】**这恰恰就是用户一直点破的那件事** ——
//         我们挂在 window 上的 `UITapGestureRecognizer`（收键盘用）
//         会**抢走 `DatePicker` 的点击**。这不是我们独有的 bug：
//         iOS 17.1 起 `DatePicker` 的已知回归就是
//         「层级里存在更高层的 tap 手势 → 点不开、要长按 2~3 秒」。
//         社区一致的两个解法，本轮**都采纳**：
//           · `DatePicker` 上加 `.simultaneousGesture(TapGesture())`
//             （**并存**，不互相取消；⚠️ 不能用 `.onTapGesture`，那会互斥）；
//           · 手势 delegate 的 `shouldReceive` 里**排除** `DatePicker` 宿主
//             （已加 `name.contains("DatePicker")`）。
//
//     ➜ 正解 = **回归最朴素的标准写法**：
//        `DatePicker("标题", …).datePickerStyle(.compact)` 直接当 List 行
//        —— 它自己就是「标题 + 可点日期」，也正是用户一直在用的那个形态。
//
//     ② 收键盘：改走第一方 `@FocusState`（见 `KeyboardDismiss.swift`
//        的 `FocusCoordinator`）。UIKit 的 `resignFirstResponder`
//        **不带转场上下文** → 键盘「啪」地消失；`focused = nil` 才播系统动画。
//
//  ⚠️ 已知取舍（**无法同时满足**，别再试图两全）：
//     `.compact` 弹出的是 UIKit 私有 popover，它一翻动就**吃列表滚动手势**
//     —— 这是系统行为。用户本轮把「点得开」排在第一位，所以先恢复可用。
//     「选完自动收」× 「不吃滚动」×「点得开」三者只能取二。
//
//  ⚠️ 触发器的坑：**绝对不要**把收起逻辑挂在 `.onChange(of: date)` 上 ——
//     滚轮每滚一格 date 就变一次，第二/六/七轮连踩三次，别走老路。

import SwiftUI

/// 模板页统一的日期选择器：标准 `DatePicker(.compact)`，
/// **点自带日期文字弹出日历**，收起由系统负责（点面板外）。
///
/// - 形态：`DatePicker("标题", …).datePickerStyle(.compact)` —— 标题在左、
///   可点日期在右，一个系统控件搞定，**不做任何自绘/包壳**。
/// - 为什么这么朴素：`DatePicker` 是 List 里的标准行，层级干净、
///   最不容易被我们挂在 window 上的收键盘手势抢走点击。
struct LabelDatePicker: View {
    let title: String
    @Binding var date: Date

    var body: some View {
        // ★ 系统 `DatePicker` 直接当整行：它**自带**标题与日期文字，
        //   而且那个日期文字就是弹出日历的开关。
        //   ⚠️ 不要再给它套 `Menu` / 自绘 `Text` / `allowsHitTesting(false)`：
        //      套 Menu 会让日历根本不渲染（上一轮的重大 bug）；
        //      自绘会与系统文字重复排版（第五轮删过）。
        DatePicker(title, selection: normalized, displayedComponents: .date)
            .datePickerStyle(.compact)
            // ★★★ 保命的一句：顶掉任何上层 tap 手势对这次点击的抢占。
            //    iOS 17.1 起 `DatePicker` 若被更高层 `.onTapGesture` 抢到，
            //    就会「点不开 / 要长按 2~3 秒」。
            //    挂一个**永远不会满足**的 `simultaneousGesture`，
            //    在不取消系统内部点击的前提下把优先级拿回来。
            //    ⚠️ 必须是 `simultaneousGesture`（并存），
            //      不能用 `.onTapGesture`（会互相取消）。
            .simultaneousGesture(TapGesture().onEnded {})
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
