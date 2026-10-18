//
//  SummaryView.swift
//  摘要 —— 效期总览（★ 2026-10-18 用户第 1 条新增，Tab 第 2 位）
//
//  用户原话：「tabbar 增加新功能『摘要』，位置放在第二个，
//    统计**正在制作中（未到完成时间）**的东西，和**本周到期**等等，你可以先做一个我看看」
//
//  设计参照「健康」App 的摘要页：大标题 + 一组磁贴（系统材质、圆角 20、大数值）。
//  ★ 统计口径**复用** `ExpiryStatus.of(_:now:)`（与「效期管理」列表同源，
//    不另起一套判断，避免两处对不上）。
//

import SwiftUI

struct SummaryView: View {
    @ObservedObject private var store = ExpiryStore.shared
    /// ★ 2026-10-18：磁贴**可点击** → 切到「效期管理」看完整列表
    ///   （用户：「摘要页面只能看，什么都点不开吗？」）。
    @ObservedObject private var router = AppRouter.shared

    private var now: Date { Date() }

    /// 只有「还在用」的记录参与统计（已用完的不算）。
    private var active: [LabelRecord] {
        store.records.filter { $0.usedAt == nil }
    }

    /// ★ 正在制作中 = **完成时间还没到**（`expireAt > now`）。
    ///   覆盖：肉类解冻中、康普茶一发发酵中、康普茶二发发酵中。
    ///   按完成时间由近到远排（最该关注的排最前）。
    private var inProgress: [LabelRecord] {
        active.filter { $0.expireAt > now }
            .sorted { $0.expireAt < $1.expireAt }
    }

    private func count(_ stage: ExpiryStage) -> Int {
        active.filter { ExpiryStatus.of($0, now: now).stage == stage }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    progressTile

                    HStack(spacing: 14) {
                        smallTile("今天到期", count(.today),
                                  icon: "clock.badge.exclamationmark", tint: .orange)
                        smallTile("7 天内到期", count(.within3) + count(.within7),
                                  icon: "calendar", tint: .blue)
                    }

                    smallTile("已过期未处理", count(.expired),
                              icon: "exclamationmark.triangle.fill", tint: .red)

                    totalTile
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("摘要")
        }
    }

    // MARK: 磁贴

    /// ① 正在制作中（主磁贴，带前 3 件明细）
    private var progressTile: some View {
        GroupBox {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("正在制作中")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Image(systemName: "hourglass")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(inProgress.count)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(inProgress.isEmpty ? Color.secondary : Color.primary)
                Text("件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if inProgress.isEmpty {
                Text("当前没有在制作中的物料")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(inProgress.prefix(3))) { record in
                        HStack(spacing: 8) {
                            Text(record.title)
                                .font(.footnote)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(finishText(record.expireAt))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if inProgress.count > 3 {
                        Text("还有 \(inProgress.count - 3) 件…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .onTapGesture { router.goToExpiry() }
    }

    /// ② 小磁贴（今天到期 / 7 天内到期 / 已过期）
    private func smallTile(_ title: String,
                           _ value: Int,
                           icon: String,
                           tint: Color) -> some View {
        GroupBox {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text("\(value)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(value == 0 ? Color.secondary : Color.primary)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .onTapGesture { router.goToExpiry() }
    }

    /// ③ 总览
    private var totalTile: some View {
        GroupBox {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("全部在用物料")
                .font(.subheadline)
            Spacer(minLength: 8)
            Text("\(active.count) 件")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .onTapGesture { router.goToExpiry() }
    }

    // MARK: 文案

    /// 「还剩多久完成」——制作中的东西关心的是**多久后能开始用**。
    private func finishText(_ date: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "已完成" }
        let hours = Int(seconds / 3600)
        if hours < 24 { return "\(max(1, hours)) 小时后" }
        let days = hours / 24
        let rest = hours % 24
        return rest == 0 ? "\(days) 天后" : "\(days) 天 \(rest) 小时"
    }
}

#Preview {
    SummaryView()
}
