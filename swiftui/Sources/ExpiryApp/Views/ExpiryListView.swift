//
//  ExpiryListView.swift
//  效期管理 —— 把「打印过的」和「扫到的」物料按到期紧迫度列出来，并做到期提醒。
//
//  ★ 到期基准 = 记录的最佳使用时间（见 LabelRecord 顶部注释）。
//  ★ 分组顺序：已过期 → 今天 → 3 天内 → 7 天内 → 更久之后 → 已用完。
//  ★ 提醒开关打开时才申请系统通知权限，不给用户「一进 App 就被问权限」的体验。
//  ★ 每条记录可以「重新打印」—— 左滑或进详情页，标签按当初的内容原样重出。
//

import SwiftUI
import UIKit

struct ExpiryListView: View {
    @Binding var path: NavigationPath

    @ObservedObject private var store = ExpiryStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showUsed = false
    /// ★★★ 2026-10-19（用户）：「不是说『用完』点击后的特效和删除相同吗？**这不一样啊**」
    ///   ➜ `withAnimation { store.markUsed(...) }` 实测**拿不到** List 的行删除动画
    ///     （记录只是属性变化、再由 `grouped()` 过滤，SwiftUI 判成"重排"而不是"删行"）。
    ///   ➜ 真正的同一条路：**先让这行从数据源里消失**（和 `delete` 一样），再更新 store。
    ///     所以这里维护一个"本地已移除"集合，用完时先把 id 塞进来触发删除动画。
    @State private var pendingRemoval: Set<UUID> = []
    @State private var selected: LabelRecord?
    @State private var showClearConfirm = false
    @State private var showDeniedAlert = false
    @State private var notice: Notice?
    @State private var now = Date()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                usedFilterSection

                if store.records.isEmpty {
                    emptySection
                } else {
                    ForEach(sections, id: \.status) { group in
                        Section {
                            ForEach(group.items) { record in
                                Button {
                                    selected = record
                                } label: {
                                    row(record)
                                }
                                .buttonStyle(.plain)
                                // ★★★ 2026-10-19（用户）：「取消文字（重新打印、删除、用完
                                //   全都只有图片），统一图片从效期数据里使用」
                                //   → 全部改成 `Image(systemName:)`，不再用 `Label`（那会带文字）。
                                // ★ 顺序同摘要页：**先声明「用完」→ 它显示在最右**；
                                //   视觉从左到右 = 删除（红）、用完（蓝）。
                                // ★ 顺序：**删除在前、用完在后** → 视觉 左=删除（红）、右=用完（蓝）。
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        store.delete(record)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .tint(.red)

                                    Button {
                                        // 和删除走完全相同的路径：先移除数据源 → 原生删行动画 → 再改数据。
                                        if record.usedAt == nil {
                                            withAnimation { pendingRemoval.insert(record.id) }
                                            store.markUsed(record)
                                        } else {
                                            pendingRemoval.remove(record.id)
                                            withAnimation {
                                                store.markUsed(record, used: false)
                                            }
                                        }
                                    } label: {
                                        Image(systemName: record.usedAt == nil
                                              ? "checkmark.circle" : "arrow.uturn.backward")
                                    }
                                    .tint(Theme.brand)
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
                        } header: {
                            Text("\(group.title) · \(group.items.count)")
                        }
                    }

                    Section {} footer: {
                        Text("右滑记录可「重新打印」，左滑可「用完 / 删除」，点开看详情。")
                    }
                }
            }
            .navigationTitle("效期管理")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("清空全部记录", systemImage: "trash", role: .destructive) {
                            showClearConfirm = true
                        }
                        .disabled(store.records.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                refresh()
                // ★ 「到期提醒」开关已删除 → 强制保持开启，保证一定会收到提醒
                //   （如果用户以前关过，这里会自动打开一次）。
                if !store.reminderEnabled { store.setReminderEnabled(true) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
            .confirmationDialog("清空全部记录？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) { store.clearAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会删掉所有已打印 / 已扫码的物料记录，且无法恢复。")
            }
            .alert("通知权限被关闭", isPresented: $showDeniedAlert) {
                Button("去设置") { openSettings() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("需要在系统设置里允许「效期管理系统」发送通知，才能收到到期提醒。")
            }
            .alert(notice?.title ?? "",
                   isPresented: Binding(get: { notice != nil },
                                        set: { if !$0 { notice = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(notice?.body ?? "")
            }
            .sheet(item: $selected) { record in
                ExpiryDetailSheet(record: record)
            }
        }
    }

    // MARK: - 区块

    /// 顶部开关区。
    ///
    /// ★★★ 2026-10-19（用户）：「**这个『到期提醒』完全没用，肯定是需要被提醒的。可以删除**，
    ///   然后把『显示已用完』增加到这个被删除的地方」
    ///   ➜ 「到期提醒」开关 + 那一大段说明整段删除；提醒**强制常开**（见 `onAppear`）。
    ///   ➜ 「显示已用完」从右上角菜单移到这里（原来藏在 `Menu` 里不好找）。
    ///   ➜ 保留"通知权限被关闭"的入口 —— 那个是真有用的提示。
    private var usedFilterSection: some View {
        Section {
            Toggle("显示已用完", isOn: $showUsed)

            if store.notificationDenied {
                Button("通知权限被关闭，去设置") { showDeniedAlert = true }
            }
        } footer: {
            Text("打开后，已标记用完的物料也会列出来。")
        }
    }

    private var emptySection: some View {
        Section {
            ContentUnavailableView {
                Label("还没有记录", systemImage: "tray")
            } description: {
                Text("打印或扫码后，物料会自动出现在这里。")
            }
        }
    }

    private func row(_ record: LabelRecord) -> some View {
        let status = ExpiryStatus.of(record, now: now)
        return HStack(spacing: 12) {
            Image(systemName: record.kind.systemImage)
                .foregroundStyle(record.usedAt == nil ? Theme.brand : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(record.kind.label)
                    Text("·")
                    // ★ 写清楚倒计时是数到**哪个日期** —— 用户反馈「看不出剩余天数是到保质期还是到最佳使用」。
                    Text("\(record.dueLabel) \(LabelTemplate.fmtDate(record.dueDate))")
                    if !record.maker.isEmpty {
                        Text("·")
                        Text(record.maker)
                    }
                    Text("·")
                    Text(record.source.label)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(status.label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color(for: status.stage))
                .multilineTextAlignment(.trailing)
        }
        .contentShape(Rectangle())
    }

    private func color(for stage: ExpiryStage) -> Color {
        switch stage {
        case .expired: return .red
        case .today: return .orange
        case .within3: return .orange
        case .within7: return .yellow
        case .later: return .secondary
        case .used: return .secondary
        }
    }

    // MARK: - 动作

    /// 重新打印一条已有记录的标签（内容与原标签逐字一致）。
    /// 列表分组（叠加"本地已移除"的乐观过滤）。
    /// 用完一条时它会先从这里消失 → 走的是和 `delete` **完全相同**的行移除动画。
    private var sections: [ExpiryGroup] {
        store.grouped(includeUsed: showUsed, now: now).compactMap { group in
            let items = group.items.filter { !pendingRemoval.contains($0.id) }
            guard !items.isEmpty else { return nil }
            return ExpiryGroup(status: group.status, title: group.title, items: items)
        }
    }

    private func reprint(_ record: LabelRecord) {
        LabelReprint.printNoticing(record,
            successBody: "\(record.title)\n份数 \(Prefs.printCopies) · 浓度 "
                + "\(Prefs.printDensity == 0 ? "自动" : "\(Prefs.printDensity)")") { notice = $0 }
    }

    private func refresh() {
        now = Date()
        store.refreshNotificationStatus()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

// MARK: - 详情

struct ExpiryDetailSheet: View {
    let record: LabelRecord

    @ObservedObject private var store = ExpiryStore.shared
    @ObservedObject private var printer = PrinterService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var notice: Notice?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("物料", value: record.title)
                    LabeledContent("类别", value: record.kind.label)
                    if !record.maker.isEmpty {
                        LabeledContent("操作人", value: record.maker)
                    }
                    LabeledContent("来源", value: record.source.label)
                }

                expirySection

                Section {
                    LabeledContent("生成时间", value: LabelTemplate.fmtDateTime(record.createdAt))
                    if let printed = record.printedAt {
                        LabeledContent("打印时间", value: LabelTemplate.fmtDateTime(printed))
                    }
                    if let used = record.usedAt {
                        LabeledContent("用完时间", value: LabelTemplate.fmtDateTime(used))
                    }
                } header: {
                    Text("记录")
                }

                Section {
                    Button {
                        reprint()
                    } label: {
                        HStack {
                            Label("重新打印这一张", systemImage: "printer")
                            Spacer()
                            if printer.isPrinting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(printer.isPrinting)
                } header: {
                    Text("标签")
                } footer: {
                    Text(printer.isConnected
                         ? "按当初的内容原样重打，不会新增一条记录。"
                         : "需要先到「打印机」页连接打印机。")
                }

                Section {
                    Button(record.usedAt == nil ? "标记为已用完" : "恢复为使用中") {
                        withAnimation {
                            store.markUsed(record, used: record.usedAt == nil)
                        }
                        dismiss()
                    }
                    Button("删除这条记录", role: .destructive) {
                        store.delete(record)
                        dismiss()
                    }
                }
            }
            .navigationTitle("记录详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert(notice?.title ?? "",
                   isPresented: Binding(get: { notice != nil },
                                        set: { if !$0 { notice = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(notice?.body ?? "")
            }
        }
    }

    /// 效期区块。
    ///
    /// ★★★ 2026-10-13（用户第 6 条）：判据从 `kind == .kombucha` 改为
    ///   **`record.usesCompletionTime`** —— 肉类解冻记录的第二组数据同样是
    ///   「完成时间」（= 解冻 + 1 天，存在 `expireAt` 槽位）；
    ///   此前它走 else 分支被显示成「原始保质期」，正是用户说的
    ///   「扫解冻后，效期管理里面显示的完成时间被存成了原始保质期」。
    ///   ➜ 康普茶 + 肉类解冻 → 「完成时间」；其余记录 → 「原始保质期」。
    private var expirySection: some View {
        let status = ExpiryStatus.of(record)
        return Section {
            if record.usesCompletionTime {
                LabeledContent("完成时间", value: LabelTemplate.fmtDateTime(record.expireAt))
            } else {
                LabeledContent("原始保质期", value: LabelTemplate.fmtDateTime(record.expireAt))
            }

            LabeledContent("最佳使用时间", value: LabelTemplate.fmtDateTime(record.bestBefore))

            // ★ 写清楚倒计时数到哪个日期：剩余天数一律以「最佳使用时间」为准。
            LabeledContent("距今「\(record.dueLabel)」", value: status.label)
            LabeledContent("状态", value: status.groupTitle)
        } header: {
            Text("效期")
        } footer: {
            if record.kind == .kombucha {
                Text("康普茶没有原始保质期。它的第二组时间是「完成时间」——"
                     + "可以饮用或做二发的时刻；会过期的是「最佳使用时间」。")
            } else if record.usesCompletionTime {
                Text("解冻肉类没有原始保质期。它的「完成时间」= 解冻时间 + "
                     + "\(MeatRule.thawCompleteDays) 天 —— 可以开始使用的时刻；"
                     + "会过期的是「最佳使用时间」。")
            } else {
                Text("剩余天数以「最佳使用时间」为准。")
            }
        }
    }

    private func reprint() {
        LabelReprint.printNoticing(record, successBody: record.title) { notice = $0 }
    }
}

#Preview {
    ExpiryListView(path: .constant(NavigationPath()))
}
