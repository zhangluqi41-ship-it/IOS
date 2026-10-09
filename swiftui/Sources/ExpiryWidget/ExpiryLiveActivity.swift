//
//  ExpiryLiveActivity.swift
//  灵动岛 / 锁屏的 Live Activity 界面。
//
//  ─────────────── 2026-10-09 第三轮（用户反馈，本文件主要改动） ───────────────
//
//  用户原话：
//    「灵动岛通知界面排版有问题：排版彻底有问题：
//      小图标时：左侧沙漏图标距离中间出现超大缝隙，已超出排版页面，
//                右侧与中间距离同样超长，已完全看不到数字（间距过大，
//                占用大量上方面积）
//      大图标时：左侧文字展示不全，可：摄像头行显示你的小logo，
//                下方增加文字（整个灵动岛大通知变宽），右侧可参考苹果健身时
//                的小数字变大的特效来制作。
//      同时：小图标时右侧数字加粗，变大图标后右侧的时间上方不要最佳使用时间」
//    「功能逻辑不对：距离倒计时结束计时后：无灵动岛主动变大图标进行提醒」
//
//  ★★ 先说最重要的一件事（决定了第 2 条到底能不能做）：
//     **灵动岛不可能由 App 主动「变大」。**
//     苹果没有开放任何 API 让第三方 App 撑开灵动岛 —— 展开只由两种方式触发：
//       ① 用户**长按**紧凑态；
//       ② 系统级事件（来电、Face ID、计时器归零…）。
//     第三方 Live Activity 拿不到第 ② 条，所以「倒计时结束自动变大」在
//     iOS 上**做不到**（不是我们没写对，是平台没这个口子）。
//
//     旧的注释里写着「phase 变 .due 后紧凑态会自动渲染展开内容」——
//     那是**错的**：紧凑态（compactLeading/compactTrailing）是系统给的
//     固定小区域，只能塞下图标和几个字，物理上渲染不了展开布局。
//     `phase` 确实会随系统时钟翻成 `.due`，但它只能改变**紧凑态自己**的
//     呈现（比如把数字换成「到点」），**不会**让岛变大。
//
//     ✅ 所以在做不到「自动变大」的前提下，本文件的替代方案是：
//        到点那一刻，**紧凑态自己变成最醒目的样子** ——
//        右边用红色「到点」字样 + 沙漏图标，用户一眼就知道该长按进来看。
//        这是免费账号 + 无推送能力下能做到的极限，也是唯一诚实的做法。
//
//  ★★ 排版修复（用户说「间距超大、看不到数字」的真正原因）：
//     上一版为了消掉两侧的默认边距，写了两句
//        `.contentMargins(.horizontal, 0, for: .compactLeading/.compactTrailing)`
//     ——**这种做法把两侧内边距压成 0 之后，系统反而把内容往两端推得更开**
//     （紧凑态的两个区域本身有最小布局宽度），结果就是用户看到的
//     「沙漏离摄像头一大段、数字被挤出屏幕」。
//     ➜ 本版**删掉那两句 contentMargins**，回到系统默认边距 ——
//       默认值本来就是苹果调过的，两侧距离正确、数字完整可见。
//
//  ★ 大图标（展开态）改动：
//     · 左侧：上一版只堆了「图标 + 标题」，标题一长就被截断。
//       现在改成**两行**：上排 logo + 类别，下排标题（`lineLimit(2)`），
//       整个展开卡也因此更宽、能容下长标题。
//     · 右侧：按用户要求参考「健身 App 数字变大」的做法 ——
//       用一个**大号粗体等宽**的时间数字，让右侧有「数字放大」的视觉重点。
//     · 去掉时间上方的「最佳使用时间」里程碑文案（用户明确要求）。
//
//  ★ 紧凑态：右侧数字**加粗放大**（用户要求「小图标时右侧数字加粗」）。
//
//  【第四轮】★ 本次 —— 用户仍然不满：
//    「小图标时：左侧沙漏图标距离中间缝隙依旧很大，不需要有缝隙，
//      右侧的倒计时与中心摄像头距离超长，需要紧贴
//      （整个界面除了文字无任何空格，不影响文字大小下尽量保证最小灵动岛）」
//    「功能逻辑不对：距离倒计时结束计时后，无灵动岛主动变大图标进行提醒」
//
//  ★★ 缝隙的真正来源（上一轮判断错了）：
//     上一轮我以为删掉 `contentMargins` 就够了 —— **不够**。
//     真正的元凶是倒计时用了 `showsHours: true`：
//     它强制文本按 `H:MM:SS`（如 `12:34:56`）预留宽度，
//     于是 `compactTrailing` 区域被撑得很宽，系统把内容**推离摄像头**；
//     左侧的沙漏同理，被塞进一个偏大的区域里居中，看着就是「一大段缝隙」。
//
//     ✅ 本版三处收敛：
//       ① 倒计时改 `showsHours: false` —— 走 `M:SS`，
//          只有真的超过 1 小时才回退成带小时的形式（见 `CompactCountdownText`）；
//       ② 两侧内容**显式压到最小**（沙漏用 `.imageScale(.small)`，
//          文字 `minimumScaleFactor` 收紧），并**不加任何多余 padding / frame**；
//       ③ 不再写 `contentMargins`（保持系统默认），也不加 `Spacer`。
//     ➜ 目标就是用户说的「除了文字无任何空格」。
//
//  ★★ 「倒计时结束主动变大」——必须说清楚：**平台做不到**。
//     苹果没有开放任何 API 让第三方 App 撑开灵动岛；展开只由
//     ① 用户长按 ② 系统事件（来电 / Face ID / 计时器归零）触发。
//     第三方 Live Activity 两条都拿不到。
//     ➜ 本版把「到点」这一刻的**紧凑态做到最醒目**作为替代：
//        沙漏换成 `exclamationmark.triangle.fill` + 红色，
//        右侧文字变红色「到点」——用户一眼就知道要长按进来处理。
//        这是无推送权限下唯一诚实的做法。
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct ExpiryLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExpiryActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // ── 左上：logo + 类别（第一行），标题（第二行，允许折行）──
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "hourglass")
                                .font(.caption2)
                            Text(context.attributes.kindLabel)
                                .font(.caption2)
                        }
                        .foregroundStyle(.white.opacity(0.8))

                        Text(context.attributes.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .foregroundStyle(.white)
                    }
                    // ★ 不再写 `.padding(.leading, 4)` —— 交给系统的展开态默认边距，
                    //   之前那点手工 padding 在真机上反而让内容贴边不齐。
                }

                // ── 右上：只有「大号时间」，**不再有里程碑文案** ──
                //   ★ 用户明确要求：「变大图标后右侧的时间上方不要最佳使用时间」。
                //   ★ 「参考苹果健身的小数字变大」→ 用大号、粗体、等宽数字，
                //     让它是整张卡的视觉重点。
                DynamicIslandExpandedRegion(.trailing) {
                    Text(ExpiryDateFormat.time(context.state.dueAt))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(context.state.phase == .due ? "已到时间" : "距离到期")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                            CountdownText(state: context.state)
                                .font(.system(.title3, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                        }
                        ActionButtons(attributes: context.attributes,
                                      state: context.state)
                    }
                    .padding(.bottom, 2)
                }
            } compactLeading: {
                // ★★ 【第五轮修复】「左侧沙漏离中间缝隙依旧很大」。
                //
                //  根因：`compactLeading` / `compactTrailing` 是**系统预留给内容的
                //  固定槽位**，不是「内容多大就占多大」。内容比槽位小时，
                //  系统会让它**在槽内居中** → 视觉上就是「离摄像头一大段缝隙」。
                //
                //  ★ 正解：用 `.frame(maxWidth: .infinity, alignment: ...)`
                //    让内容**撑满槽位**，并把对齐方向**朝向摄像头**：
                //      · 左槽 → 右对齐（`.trailing`，往中间靠）
                //      · 右槽 → 左对齐（`.leading`，往中间靠）
                //    这样「缝隙」和「黑边」都会被推掉，内容紧贴灵动岛中央。
                //  ⚠️ 不要用负 padding 硬顶 —— 会与系统裁切打架。
                Image(systemName: context.state.phase == .due
                      ? "exclamationmark.triangle.fill"
                      : "hourglass")
                    .imageScale(.small)
                    .foregroundStyle(context.state.phase == .due ? Color.red : Color.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } compactTrailing: {
                // ★ 右侧同理：内容**左对齐**（往摄像头靠），把右侧黑边推掉。
                //   宽度收敛靠 `CompactCountdownText` 里的 `showsHours` 动态判断。
                CompactCountdownText(state: context.state)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } minimal: {
                // minimal 只留给一个图标，别放文字。
                Image(systemName: "hourglass")
                    .imageScale(.small)
                    .foregroundStyle(.white)
            }
            .keylineTint(Theme.brand)
            // ⚠️⚠️ **千万不要再加 `.contentMargins(.horizontal, 0, for: .compact*)`**
            //    上一版就是这么写的，结果把紧凑态内容推到两端、
            //    数字被挤出屏幕（用户反馈「已完全看不到数字」）。
            //    系统的默认边距才是对的 —— 保持不放任何 contentMargins。
        }
    }
}

// MARK: - 锁屏 / 横幅

private struct LockScreenView: View {
    let context: ActivityViewContext<ExpiryActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(Theme.brandLight)
                Text(context.attributes.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(context.attributes.kindLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(context.attributes.milestoneLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ExpiryDateFormat.dateTime(context.state.dueAt))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                CountdownText(state: context.state)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(context.state.phase == .due ? .red : Theme.brandLight)
            }

            ActionButtons(attributes: context.attributes, state: context.state)
        }
        .padding(14)
    }
}

// MARK: - 按钮（★ 按阶段显示）

/// ★★ 2026-10-09 修正（用户反馈）：
///    「前 10 分钟提醒，按钮只保留已完成使用，删除到时间后的稍后提醒」
///
///    → 所以**提前阶段（`.soon`）只显示「已完成使用」**；
///      「稍后提醒」只在**已经到时间（`.due`）**之后才出现。
///
///    判据用 `ContentState.phase`，它是**按当前时刻现算**的派生属性
///    （见 `ExpiryActivityAttributes.ContentState.phase`），
///    系统每秒刷倒计时时会一起重绘 → 到点自动切换，不需要 App 干预。
private struct ActionButtons: View {
    let attributes: ExpiryActivityAttributes
    let state: ExpiryActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ExpiryMarkDoneIntent(recordID: attributes.recordID)) {
                Label("已完成使用", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)

            // ★ 只有「到时间」之后才给「稍后提醒」。
            if state.phase == .due {
                Button(intent: ExpirySnoozeIntent(recordID: attributes.recordID,
                                                  dueAt: state.dueAt)) {
                    Label("稍后提醒", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .tint(.orange)
            }
        }
    }
}

// MARK: - 倒计时

/// 展开态 / 锁屏用的倒计时。
///
/// ★ `Text(timerInterval:)` 的区间必须「下界 < 上界」，否则会崩。
///   到点之后区间已经走完，系统会停在 `0:00`；这里额外兜一层，
///   显示「已到时间」比 `0:00` 更清楚。
private struct CountdownText: View {
    let state: ExpiryActivityAttributes.ContentState

    var body: some View {
        if let interval = state.countdownInterval {
            Text(timerInterval: interval, countsDown: true, showsHours: true)
                .monospacedDigit()
        } else {
            Text("已到时间")
        }
    }
}

/// 紧凑态（灵动岛最小宽度）专用的倒计时。
///
/// ★★ 【第四轮关键修复】宽度收敛 —— 这是「右侧与摄像头距离超长」的真正解法：
///    上一版用 `Text(timerInterval:countsDown:showsHours: true)`，
///    它会按 `H:MM:SS`（`12:34:56`，8 个字符）**预留宽度**，
///    把 `compactTrailing` 撑得很宽 → 系统把这一块**推离摄像头**，
///    于是用户看到「中间一大段空隙」。
///
///    ✅ 现在改成：
///      · 剩余时间 **< 1 小时**（绝大多数场景）→ `showsHours: false`，
///        只渲染 `M:SS`（`12:34`，5 个字符），宽度立刻收窄一大截；
///      · 剩余时间 **≥ 1 小时** → 才回退成带小时的 `H:MM:SS`。
///    判据用 `state.dueAt.timeIntervalSinceNow`，**每秒由系统重绘时现算**，
///    所以跨越 1 小时的那个瞬间会自动从 `59:59` 切到 `1:00:00`，无需 App 干预。
///
/// ★ 用户要求「小图标时右侧数字加粗」→ `.bold`。
/// ★ 用户要求「除了文字无任何空格」→ 这里**不加任何 padding / frame**，
///   只靠 `minimumScaleFactor` 往下缩，绝不主动占宽。
///
/// ★★ 到点之后显示**红色「到点」** —— 因为平台不允许 App 主动撑开灵动岛
///    （见文件头），我们能做的就是让紧凑态在到点那一刻本身最醒目。
private struct CompactCountdownText: View {
    let state: ExpiryActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.phase == .due {
                // 已到点：不再走 timerInterval（区间已走完），直接给醒目文字。
                Text("到点")
            } else {
                // ★ 以「是否还有 1 小时以上」决定格式：
                //   < 1h → `M:SS`（`showsHours: false`），窄；
                //   ≥ 1h → `H:MM:SS`（`showsHours: true`），宽但必要。
                //
                //   ⚠️ `Text(timerInterval:)` 要求**下界 < 上界**，否则崩。
                //      这里直接复用 `state.countdownInterval`（内部已 guard
                //      「dueAt > startedAt 且 now < dueAt」），只有在
                //      `phase != .due` 时才非 nil —— 天然安全。
                if let interval = state.countdownInterval {
                    let needsHours = state.dueAt.timeIntervalSinceNow >= 3600
                    Text(timerInterval: interval,
                         countsDown: true,
                         showsHours: needsHours)
                        .monospacedDigit()
                } else {
                    Text("到点")
                }
            }
        }
        .font(.caption)
        .fontWeight(.bold)
        .lineLimit(1)
        // ★ 长时长（如 `1:23:45`）自动缩，而不是把容器撑宽把数字挤出屏幕。
        .minimumScaleFactor(0.7)
        .foregroundStyle(state.phase == .due ? Color.red : Color.white)
    }
}
