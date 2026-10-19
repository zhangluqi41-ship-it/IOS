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


    private var now: Date { Date() }

    /// 只有「还在用」的记录参与统计（已用完的不算）。
    private var active: [LabelRecord] {
        store.records.filter { $0.usedAt == nil }
    }

    /// ★★★ 2026-10-19（用户第 3 条）：「正在制作中的逻辑不对，
    ///   应该是**有『完成时间』的物料**才是正在制作中的」。
    ///   → 判据 = `usesCompletionTime`（康普茶 / 肉类解冻有"完成时间"字段）
    ///     **且** 完成时间还没到。
    ///   → 完成时间已过的那批归到「已完成制作」（新分类）。
    private var inProgress: [LabelRecord] {
        SummaryFilter.inProgress.records(from: store.records, now: now)
    }

    /// 统一口径：直接复用 `SummaryFilter`，保证**磁贴数字 = 点进去的列表条数**。
    private func count(_ filter: SummaryFilter) -> Int {
        filter.records(from: store.records, now: now).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    progressTile

                    HStack(spacing: 14) {
                        // ★ 2026-10-19 新增：完成时间已过、但还没到最佳使用时间的那批。
                        smallTile("已完成制作", count(.finished),
                                  icon: "checkmark.seal.fill", tint: .green,
                                  filter: .finished)
                        smallTile("今天到期", count(.dueToday),
                                  icon: "clock.badge.exclamationmark", tint: .orange,
                                  filter: .dueToday)
                    }

                    HStack(spacing: 14) {
                        smallTile("7 天内到期", count(.withinSeven),
                                  icon: "calendar", tint: .blue,
                                  filter: .withinSeven)
                        smallTile("已过期未处理", count(.overdue),
                                  icon: "exclamationmark.triangle.fill", tint: .red,
                                  filter: .overdue)
                    }

                    totalTile
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("摘要")
            // ★ 2026-10-18（用户第 3 条）：点磁贴 → **独立二级页**（不再跳去效期管理）。
            .navigationDestination(for: SummaryFilter.self) { filter in
                SummaryDetailView(filter: filter)
            }
        }
    }

    // MARK: 磁贴

    /// ① 正在制作中（主磁贴，带前 3 件明细）
    private var progressTile: some View {
        NavigationLink(value: SummaryFilter.inProgress) {
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
            .padding(16)
            // ★ 同模板磁贴：GroupBox 浅色下画的就是页面底色（实测不可见）→ 自己画卡片。
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.tileRadius))
            .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius))
        }
        .buttonStyle(.plain)
    }

    /// ② 小磁贴（今天到期 / 7 天内到期 / 已过期）
    private func smallTile(_ title: String,
                           _ value: Int,
                           icon: String,
                           tint: Color,
                           filter: SummaryFilter) -> some View {
        NavigationLink(value: filter) {
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
            .padding(16)
            // ★ 同模板磁贴：GroupBox 浅色下画的就是页面底色（实测不可见）→ 自己画卡片。
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.tileRadius))
            .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius))
        }
        .buttonStyle(.plain)
    }

    /// ③ 总览
    private var totalTile: some View {
        NavigationLink(value: SummaryFilter.all) {
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
            .padding(16)
            // ★ 同模板磁贴：GroupBox 浅色下画的就是页面底色（实测不可见）→ 自己画卡片。
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.tileRadius))
            .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius))
        }
        .buttonStyle(.plain)
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


// MARK: - 摘要磁贴 → 独立二级页（★ 2026-10-18 用户第 3 条）

/// 摘要磁贴对应的筛选条件。
///
/// 用户原话：「摘要点击后应该是**独立的新二级菜单**，而不是跳转到效期管理里，
/// 但是**后台数据是相通的**」
/// ➜ 点磁贴 push 到 `SummaryDetailView`；数据仍来自同一个 `ExpiryStore.shared`。
enum SummaryFilter: Hashable {
    /// 正在制作中：**有「完成时间」的物料**（康普茶 / 肉类解冻）+ 完成时间未到。
    case inProgress
    /// 已完成制作：有「完成时间」的物料 + 完成时间已过（但还没用完）。
    case finished
    case dueToday
    case withinSeven
    case overdue
    case all

    var title: String {
        switch self {
        case .inProgress: return "正在制作中"
        case .finished: return "已完成制作"
        case .dueToday: return "今天到期"
        case .withinSeven: return "7 天内到期"
        case .overdue: return "已过期未处理"
        case .all: return "全部在用物料"
        }
    }

    /// 与磁贴上的数字**同一套口径**（复用 `ExpiryStatus`，别另写判断）。
    func records(from all: [LabelRecord], now: Date = Date()) -> [LabelRecord] {
        let active = all.filter { $0.usedAt == nil }
        switch self {
        case .inProgress:
            // ★ 用户第 3 条：**有「完成时间」的物料**才算制作中，且完成时间还没到。
            //   （通用效期 / 奶制品的第二组时间是"原始保质期"，不算制作中）
            return active
                .filter { $0.usesCompletionTime && $0.expireAt > now }
                .sorted { $0.expireAt < $1.expireAt }
        case .finished:
            // 完成时间已过 = 制作完成（但可能还没用完）。
            return active
                .filter { $0.usesCompletionTime && $0.expireAt <= now }
                .sorted { $0.expireAt < $1.expireAt }
        case .dueToday:
            return active.filter { ExpiryStatus.of($0, now: now).stage == .today }
                .sorted { $0.dueDate < $1.dueDate }
        case .withinSeven:
            return active.filter {
                let stage = ExpiryStatus.of($0, now: now).stage
                return stage == .within3 || stage == .within7
            }
            .sorted { $0.dueDate < $1.dueDate }
        case .overdue:
            return active.filter { ExpiryStatus.of($0, now: now).stage == .expired }
                .sorted { $0.dueDate < $1.dueDate }
        case .all:
            return active.sorted { $0.dueDate < $1.dueDate }
        }
    }
}

/// 摘要的二级列表页 —— 只读展示，点一行弹详情（与「效期管理」共用 `ExpiryDetailSheet`）。
struct SummaryDetailView: View {
    let filter: SummaryFilter

    @ObservedObject private var store = ExpiryStore.shared
    @State private var selected: LabelRecord?
    @State private var notice: Notice?

    private var list: [LabelRecord] {
        filter.records(from: store.records)
    }

    var body: some View {
        List {
            if list.isEmpty {
                ContentUnavailableView("没有相关物料",
                                       systemImage: "checkmark.circle",
                                       description: Text("这一栏现在是空的"))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(list) { record in
                    Button {
                        selected = record
                    } label: {
                        row(record)
                    }
                    .buttonStyle(.plain)
                    // ★★★ 2026-10-19（用户订正）：
                    //   · 「『详情』是什么鬼，不需要」→ 滑动菜单里去掉详情；
                    //   · 「右滑出现的菜单依次是**删除、用完**」→ 顺序固定，删除在前（最右）；
                    //   · 「取消文字」→ 只用 `Image(systemName:)`，图标与效期管理完全一致。
                    // ★★★ 2026-10-19（用户订正）：「**第一个是删除，第二个才是用完**」
                    //   ⚠️ SwiftUI 的 `swipeActions(edge: .trailing)` 里，
                    //   **先声明的按钮显示在最右边**（离屏幕边缘最近）。
                    //   所以要「视觉从左到右 = 删除、用完」，声明顺序必须**倒过来写**。
                    //   另外 `role: .destructive` 在滑动菜单里**不会自动变红**，
                    //   必须显式 `.tint(.red)`（之前截图里两个都是蓝色就是这个原因）。
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            // ★ 同效期管理：`withAnimation { }`（系统默认动画，非自定义曲线）。
                            withAnimation {
                                store.markUsed(record, used: record.usedAt == nil)
                            }
                        } label: {
                            Image(systemName: record.usedAt == nil
                                  ? "checkmark.circle" : "arrow.uturn.backward")
                        }
                        .tint(Theme.brand)

                        Button(role: .destructive) {
                            store.delete(record)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            reprint(record)
                        } label: {
                            Image(systemName: "printer")
                        }
                        .tint(Theme.brand)
                    }
                }
            }
        }
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { record in
            ExpiryDetailSheet(record: record)
        }
        .alert(notice?.title ?? "",
               isPresented: Binding(get: { notice != nil },
                                    set: { if !$0 { notice = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(notice?.body ?? "")
        }
    }

    /// 重打（与效期管理同一套：`LabelReprint.printNoticing`）。
    private func reprint(_ record: LabelRecord) {
        LabelReprint.printNoticing(record,
            successBody: "\(record.title)\n份数 \(Prefs.printCopies)") { notice = $0 }
    }

    private func row(_ record: LabelRecord) -> some View {
        let status = ExpiryStatus.of(record)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(status.isAlerting ? Color.red : Color.secondary)
            }
            Spacer(minLength: 8)
            Text(dateText(filter == .inProgress ? record.expireAt : record.dueDate))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    private func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: date)
    }
}

#Preview {
    NavigationStack {
        SummaryDetailView(filter: .all)
    }
}

