//
//  DateField.swift
//  模板页统一的日期输入控件。
//
//  ─────────────────────── 演变史（九次用户反馈） ───────────────────────
//
//  【第一轮】「选完时间后面板不收」→ 用 `.id` 重建 DatePicker 把它顶掉。
//  【第二轮】① 日期格式统一 `xxxx/xx/xx`；② 「滚轮选完年月马上就消失了」；
//     ③ 日期单位要英文缩写。→ ② 的根因就是 `.id` 重建（滚轮每落定一格就换 id）。
//  【第三轮】「日期选择不应该全展开」→ 回到 `.compact`。
//  【第四轮】日期跑到左边 → 改用 HStack 当主布局。
//  【第五轮】右侧日期重复排版 → 删掉自绘 Text，只留系统 DatePicker。
//  【第六轮】「滚完滚轮马上就闪关闭」→ 取消一切自动收起。
//  【第七轮】「选好日期应自动收」→ 改用 `Menu { DatePicker(.graphical) }`。
//     → **打脸**：Menu 只装命令，日历根本不渲染 = 打不开。
//  【第八轮】（v1.1.3）回归 `DatePicker(.compact)` 直接当 List 行 +
//     `.simultaneousGesture(TapGesture())` 抢回点击。→ 点得开了，但仍不收面板。
//
//  ★★★【第九轮】本次（v1.1.4）—— 用户：
//     「沟通确认的点击红框内日期，收回日期选项栏，但是点击后无收回。依然是反复问题」
//
//     ★ 为什么之前「点了没反应」—— **根因不在本文件，而在收键盘那套链路**：
//       我们挂在 window 上的 `UITapGestureRecognizer` 对 `UIControl` 一律
//       `return false`（为了让输入框能聚焦），于是"点面板外"这次触摸
//       对系统而言**根本没发生** → `.compact` 的私有 popover
//       永远等不到它那个「点了外面就关闭」的条件。
//       ➜ 那个手势已在本次**从 `KeyboardDismiss.swift` 整体删除**，
//         「点弹层外面关闭」这条系统原生路径自行恢复。
//
//     ★ 「选完自动收回」怎么实现而又不重蹈第二/六轮覆辙：
//       第二/六轮的坑是**在 `.onChange(of: date)` 里收起** —— 滚轮每滚一格
//       date 就变一次，面板当场被关掉。
//       ➜ 正解 = **只在"值真的变了"时才顶掉面板，且带一个冷却窗口**：
//         用户一旦开始滚年月（连续变化）就重新计时，只有**停下超过 `quiet` 秒**、
//         且此时值确实变了，才认为"他选定了"，这时把 `calendarId` 换掉 →
//         `DatePicker` 被重建 → 私有 popover 随之消失。
//         ⚠️ 冷却窗口**不能太短**：用户滚轮停手思考时不能关（第二轮的"马上就消失"）。
//         ⚠️ 也**不能挂在 `.id(date)` 或纯 `.onChange` 上** —— 那样中间态必炸。
//
//     ⚠️ 「点得开」是前提，任何改动都必须先保住它：
//        `.simultaneousGesture(TapGesture())` **必须留着**（iOS 17.1 回归的解法）。
//        ⚠️ 别改成 `.onTapGesture`（互斥）、别加 `Menu`（不渲染日历）。

import SwiftUI

/// 模板页统一的日期选择器：标准 `DatePicker(.compact)`，
/// **点自带日期文字弹出日历**，**选定后自动收回**。
struct LabelDatePicker: View {
    let title: String
    @Binding var date: Date

    /// 面板的重建标识：换一次 = 把当前弹层顶掉（即"收回"）。
    @State private var calendarId = 0
    /// 挂起中的回收任务（用户继续滚动时要取消重排）。
    @State private var recheck: Task<Void, Never>?

    /// 停手多久算"选定了"（秒）。**这是唯一的体感旋钮**：
    /// 太短 → 滚年月时面板被关掉（第二/六轮的病）；太长 → 选完迟迟不收。
    private let quiet: TimeInterval = 0.45

    var body: some View {
        DatePicker(title, selection: normalized, displayedComponents: .date)
            .datePickerStyle(.compact)
            // ★★★ 保命的一句：顶掉任何上层 tap 手势对这次点击的抢占。
            //    ⚠️ 必须是 `simultaneousGesture`（并存），不能用 `.onTapGesture`。
            .simultaneousGesture(TapGesture().onEnded {})
            .id(calendarId)
            .onChange(of: date) { _, _ in scheduleRecheck() }
            // 离开页面时别把任务漏在后台。
            .onDisappear { recheck?.cancel() }
    }

    /// 值变了 → **不立刻**收面板，而是等 `quiet` 秒之后再看一眼：
    /// 这期间若又变了（用户在滚年月），任务被重排，计时重新开始。
    ///
    /// ★ 这就是"区分「滚年月」和「选定」"的全部机制：
    ///   · 滚轮连着滚 → 每次变化都把任务往后推 → 面板一直开着（第二/六轮的病不再犯）；
    ///   · 停手超过 `quiet` → 任务落地 → 收面板。
    ///
    /// ⚠️ 只剩一个已知取舍：**打开面板后什么都不做、停超过 `quiet` 秒也收不到**
    ///    （因为没触发 `onChange`）。要连这个也收，就得再引入一条手势/定时链，
    ///    与"不要冗余代码"冲突；而且用户点面板外本来就能关（window 手势已删除，
    ///    系统原生关闭路径已恢复）。**这条取舍是有意保留的。**
    private func scheduleRecheck() {
        recheck?.cancel()
        recheck = Task { @MainActor in
            // ⚠️ 用 `try?` 吞掉取消异常后**必须**再查 `isCancelled` ——
            //    `Task.sleep` 被取消时会抛错，`try?` 会把它变成 nil 继续往下走，
            //    不查取消状态就会"取消后照样收面板"（等于防抖失效）。
            try? await Task.sleep(nanoseconds: UInt64(quiet * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // 换 id → `DatePicker` 重建 → 私有 popover 消失 = 面板收回。
            calendarId &+= 1
        }
    }

    /// ★ 把外部绑定的值**规范化到当天 0 点**再喂给 DatePicker。
    ///
    /// 为什么必须做：`Date` 是带时分秒的绝对时刻，两个「同一天」的 Date
    /// 并不相等；而且业务上我们**只关心日期**（`kDotsPerMM`、+N 天规则都按天算）。
    /// 统一压到 0 点后：比较稳定、写入语义干净，（也顺带避免了同一天被反复触发）。
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
