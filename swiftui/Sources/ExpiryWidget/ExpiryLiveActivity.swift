//
//  ExpiryLiveActivity.swift
//  灵动岛 / 锁屏的 Live Activity 界面。
//
//  ★ 用户要求（清单「三、效期管理」第 2/3 条）：
//     「提前 10 分钟和到时间这两个通知可以增加灵动岛交互，像快递软件一样
//       在岛上显示倒计时，长按打开岛的提醒大界面后增加已完成使用和稍后提醒
//       两个按钮」
//     「通知时，目前是小灵动岛加一个横幅，但是逻辑应该是小灵动岛放大灵动岛，
//       然后让我选择已完成或者其他」
//
//  ★★ 2026-10-09 第二轮修正（用户反馈）：
//     ① 「未点开时左侧沙漏离摄像头位置缝隙过大，右侧时间的右侧有多余的黑色，
//        大概占了一个图标的位置」——
//        → 紧凑态**不要再给固定宽度**（原来 `compactTrailing` 写了
//          `.frame(maxWidth: 54)`，等于强行留出一个图标的空位）。
//          改成由内容自然决定大小，两边都用 `.fixedSize()` 贴边，
//          并关掉 `.contentMarginsDisabled()` 之外的多余内边距。
//     ② 「前 10 分钟提醒，按钮只保留已完成使用，删除到时间后的稍后提醒」
//        → 按钮**按阶段显示**：`.soon` 只给「已完成使用」，
//          `.due` 才给「已完成使用 + 稍后提醒」。见 `ActionButtons`。
//
//  ★ 倒计时为什么用 `Text(timerInterval:countsDown:)`：
//    它是**系统自己每秒钟刷的**，不需要 App 在后台推状态 ——
//    而免费开发者账号根本没有 APNs 推送能力，这是唯一可行的做法。
//
//  ★★ 到时间那一刻怎么自动变成展开态：
//    见 `ExpiryActivityAttributes.ContentState.phase(at:)` ——
//    `phase` 不是存下来的死值，而是**按当前时刻现算**的派生属性。
//    系统在 `dueAt` 那一刻会重绘，`phase` 就自动从 `.soon` 翻成 `.due`，
//    于是「紧凑态」自动渲染成展开内容、按钮也跟着多出「稍后提醒」，
//    全程不需要 App 在后台做任何事。
//
//  ★ 颜色：锁屏那一栏用语义色（跟随系统深浅色 / iOS 26 玻璃材质），
//    灵动岛内部**恒定是黑底**，所以那里的文字一律用白色系。
//
//  ⚠️ 这个文件属于 `ExpiryWidget` 目标，**看不到** `LabelTemplate` /
//     `ExpiryStore` 等主 App 的类型。所以：
//       · 时间格式化 → `ExpiryDateFormat`（Sources/Shared）
//       · 品牌色 → `Theme`（把 Theme.swift 也编进了本目标，见 project.yml）
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
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                        Text(context.attributes.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(context.attributes.milestoneLabel)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                        Text(ExpiryDateFormat.time(context.state.dueAt))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .padding(.trailing, 4)
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
                // ★ 只放沙漏，且**不加任何 frame** —— 加了固定宽度
                //   就会在摄像头左侧撑出一段空白（用户说的「缝隙过大」）。
                Image(systemName: "hourglass")
                    .font(.caption2)
                    .foregroundStyle(.white)
            } compactTrailing: {
                // ★ 这里原来有 `.frame(maxWidth: 54)`，会在时间右侧留出
                //   一个图标宽的黑块（用户说的「多余黑色」）。去掉固定宽度，
                //   换成 `fixedSize()` 让文字自己贴边。
                CompactCountdownText(state: context.state)
            } minimal: {
                // minimal 只留给「沙漏」一个图标，别放文字。
                Image(systemName: "hourglass")
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
            .keylineTint(Theme.brand)
            .contentMarginsDisabled()
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
///    判据直接用 `ContentState.phase`，它是**按当前时刻现算**的派生属性
///    （见 `ExpiryActivityAttributes.ContentState.phase(at:)`），
///    系统在 `dueAt` 那一刻重绘 → 按钮自动切换，不需要 App 干预。
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
/// ★★ 为什么单独一个 View 而不是复用 `CountdownText`：
///    紧凑态空间极窄，用户明确反馈「右侧有多余的黑色」。
///    这里做三件事把宽度压到最小：
///      ① 不加任何固定 `frame`，只用 `fixedSize()` 让内容自己贴边；
///      ② `monospacedDigit()` 保证每秒刷新时**宽度不跳**（不抖）；
///      ③ `.minimumScaleFactor(0.7)` 让长时长（如 `1:23:45`）自动缩，
///         而不是撑宽容器。
private struct CompactCountdownText: View {
    let state: ExpiryActivityAttributes.ContentState

    var body: some View {
        Group {
            if let interval = state.countdownInterval {
                Text(timerInterval: interval, countsDown: true, showsHours: true)
            } else {
                Text("到点")
            }
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(.white)
    }
}
