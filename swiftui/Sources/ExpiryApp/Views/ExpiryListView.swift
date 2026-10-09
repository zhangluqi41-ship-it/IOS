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
    @ObservedObject private var printer = PrinterService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showUsed = false
    @State private var selected: LabelRecord?
    @State private var showClearConfirm = false
    @State private var showDeniedAlert = false
    @State private var notice: Notice?
    @State private var now = Date()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                reminderSection

                if store.records.isEmpty {
                    emptySection
                } else {
                    ForEach(store.grouped(includeUsed: showUsed, now: now), id: \.status) { group in
                        Section {
                            ForEach(group.items) { record in
                                Button {
                                    selected = record
                                } label: {
                                    row(record)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        store.delete(record)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    Button {
                                        store.markUsed(record, used: record.usedAt == nil)
                                    } label: {
                                        Label(record.usedAt == nil ? "用完" : "恢复",
                                              systemImage: record.usedAt == nil
                                                  ? "checkmark.circle" : "arrow.uturn.backward")
                                    }
                                    .tint(Theme.brand)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        reprint(record)
                                    } label: {
                                        Label("重新打印", systemImage: "printer")
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
                        Toggle("显示已用完", isOn: $showUsed)
                        Divider()
                        Button("清空全部记录", systemImage: "trash", role: .destructive) {
                            showClearConfirm = true
                        }
                        .disabled(store.records.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear { refresh() }
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

    private var reminderSection: some View {
        Section {
            Toggle("到期提醒", isOn: Binding(
                get: { store.reminderEnabled },
                set: { store.setReminderEnabled($0) }
            ))

            if store.notificationDenied {
                Button("通知权限被关闭，去设置") { showDeniedAlert = true }
            }
        } footer: {
            Text("开启后，「最佳使用时间」和「原始保质期」各自会在**前一天上午 9:00、"
                 + "当天上午 9:00、提前 1 小时、提前 10 分钟**提醒。"
                 + "到时间那一刻不再弹横幅 —— 改为灵动岛自动放大，直接在岛上点"
                 + "「已完成使用」或「稍后提醒」（稍后提醒每隔 5 分钟再来一次）。"
                 + "康普茶没有原始保质期，它的第二组时间是「完成时间」"
                 + "（可以喝 / 可以做二发），同样会提醒。"
                 + "已过期、今天到期、3 天内到期的物料会显示在底栏角标上。")
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
    private func reprint(_ record: LabelRecord) {
        guard printer.isConnected else {
            notice = Notice(title: "还没有连接打印机",
                            body: "请到「打印机」标签页连接硕方 T50 Pro，再回来重打。")
            return
        }
        LabelReprint.print(record) { ok, message in
            if ok {
                notice = Notice(title: "已发送到打印机",
                                body: "\(record.title)\n份数 \(Prefs.printCopies) · 浓度 "
                                    + "\(Prefs.printDensity == 0 ? "自动" : "\(Prefs.printDensity)")")
            } else {
                notice = Notice(title: "打印失败",
                                body: message?.isEmpty == false ? message! : "请检查打印机状态后重试。")
            }
        }
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
                        store.markUsed(record, used: record.usedAt == nil)
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
    /// ★ 康普茶**没有原始保质期** —— 它的第二组数据是「完成时间」，
    ///   也就是可以喝、可以做二发的时刻（用户反馈：这里显示成「原始保质期」是错的）。
    private var expirySection: some View {
        let status = ExpiryStatus.of(record)
        return Section {
            if record.kind == .kombucha {
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
            } else {
                Text("剩余天数以「最佳使用时间」为准。")
            }
        }
    }

    private func reprint() {
        guard printer.isConnected else {
            notice = Notice(title: "还没有连接打印机",
                            body: "请到「打印机」标签页连接硕方 T50 Pro，再回来重打。")
            return
        }
        LabelReprint.print(record) { ok, message in
            if ok {
                notice = Notice(title: "已发送到打印机", body: record.title)
            } else {
                notice = Notice(title: "打印失败",
                                body: message?.isEmpty == false ? message! : "请检查打印机状态后重试。")
            }
        }
    }
}

#Preview {
    ExpiryListView(path: .constant(NavigationPath()))
}
