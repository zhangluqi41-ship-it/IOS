//
//  ExpiryLiveActivity.swift
//  灵动岛 / 锁屏的 Live Activity 界面。
//
//  ★ 用户要求（清单「三、效期管理」第 2 条）：
//     「提前 10 分钟和到时间这两个通知可以增加灵动岛交互，像快递软件一样
//       在岛上显示倒计时，长按打开岛的提醒大界面后增加已完成使用和稍后提醒
//       两个按钮」
//
//  ★ 倒计时为什么用 `Text(timerInterval:countsDown:)`：
//    它是**系统自己每秒钟刷**的，不需要 App 在后台推状态 ——
//    而免费开发者账号根本没有 APNs 推送能力，这是唯一可行的做法。
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
                Image(systemName: "hourglass")
                    .foregroundStyle(.white)
            } compactTrailing: {
                CountdownText(state: context.state)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 54)
            } minimal: {
                Image(systemName: "hourglass")
                    .foregroundStyle(.white)
            }
            .keylineTint(Theme.brand)
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

// MARK: - 两个按钮

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

// MARK: - 倒计时

private struct CountdownText: View {
    let state: ExpiryActivityAttributes.ContentState

    var body: some View {
        // ★ `Text(timerInterval:)` 的区间必须「下界 < 上界」，否则会崩。
        //   正常路径下 startedAt < dueAt（只给 8 小时内、且尚未到期的里程碑起活动），
        //   这里再兜一层，异常数据退化成静态短横。
        if state.dueAt > state.startedAt {
            Text(timerInterval: state.startedAt...state.dueAt,
                 countsDown: true,
                 showsHours: true)
                .monospacedDigit()
        } else {
            Text("—")
        }
    }
}
