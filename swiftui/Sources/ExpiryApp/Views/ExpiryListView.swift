//
//  ExpiryListView.swift
//  效期管理 —— 把「打印过的」和「扫到的」物料按到期紧迫度列出来，并做到期提醒。
//
//  ★ 到期基准 = 记录的最佳使用时间（见 LabelRecord 顶部注释）。
//  ★ 分组顺序：已过期 → 今天 → 3 天内 → 7 天内 → 更久之后 → 已用完。
//  ★ 提醒开关打开时才申请系统通知权限，不给用户「一进 App 就被问权限」的体验。
//

import SwiftUI
import UIKit

struct ExpiryListView: View {
    @Binding var path: NavigationPath

    @ObservedObject private var store = ExpiryStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showUsed = false
    @State private var selected: LabelRecord?
    @State private var showClearConfirm = false
    @State private var showDeniedAlert = false
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
                            }
                        } header: {
                            Text("\(group.title) · \(group.items.count)")
                        }
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
            Text("开启后，会在物料「最佳使用时间」的前一天和当天上午 9:00 提醒你。"
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
                    Text(LabelTemplate.fmtDate(record.dueDate))
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
    @Environment(\.dismiss) private var dismiss

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

                Section {
                    LabeledContent("最佳使用时间", value: LabelTemplate.fmtDateTime(record.bestBefore))
                    LabeledContent("原始保质期", value: LabelTemplate.fmtDateTime(record.expireAt))
                    LabeledContent("状态", value: ExpiryStatus.of(record).label)
                } header: {
                    Text("效期")
                }

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
        }
    }
}

#Preview {
    ExpiryListView(path: .constant(NavigationPath()))
}
