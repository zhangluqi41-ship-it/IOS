//
//  KombuchaTemplateView.swift
//  康普茶一发 —— 只填茶叶品种 + 操作人，三个时间全自动推算。
//

import SwiftUI

struct KombuchaTemplateView: View {
    @State private var variety = ""
    @State private var maker = Prefs.lastMaker
    @State private var showVarietyAlert = false
    /// ★ 第一方焦点（第十九轮）：收键盘走 `focused = nil`，键盘才有系统动画。
    @FocusState private var focus: AnyHashable?

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "leaf")
                        .foregroundStyle(Theme.brand)
                        .frame(width: 22)
                    TextField("输入茶叶品种", text: $variety)
                        .focused($focus, equals: AnyHashable("variety"))
                        .onChange(of: variety) { _, value in
                            if value.count > LabelTemplate.maxNameLength {
                                variety = String(value.prefix(LabelTemplate.maxNameLength))
                            }
                        }
                }
                MakerField(maker: $maker, focused: $focus)
            } footer: {
                Text("标题自动为「康普茶-\(variety.isEmpty ? "品种" : variety)」")
            }

            Section {
                Label("制备时间 = 当前时刻", systemImage: "clock")
                Label("完成时间 = 制备 + 7 天", systemImage: "calendar")
                Label("最佳使用时间 = 制备 + 30 天", systemImage: "calendar.badge.checkmark")
            } header: {
                Text("自动推算")
            }
        }
        .navigationTitle("康普茶 · 一发")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissible(focus: $focus)
        .modifier(LabelActions(build: buildDraft))
        .alert("请先填写茶叶品种", isPresented: $showVarietyAlert) {
            Button("好", role: .cancel) {}
        }
    }

    private func buildDraft() -> LabelDraft? {
        let v = LabelTemplate.clamp(variety, LabelTemplate.maxNameLength)
        guard !v.isEmpty else {
            showVarietyAlert = true
            return nil
        }
        let makerFinal = MakerField.finalize(maker)

        let now = Date()
        let data = LabelTemplate.buildKombuchaFirst(variety: v, now: now, maker: makerFinal)
        let done = AppCalendar.shared.date(byAdding: .day,
                                           value: LabelTemplate.kombuchaDoneDays,
                                           to: now) ?? now
        let best = AppCalendar.shared.date(byAdding: .day,
                                           value: LabelTemplate.kombuchaBestDays,
                                           to: now) ?? now
        let record = LabelTemplate.makeRecord(kind: .kombucha, data: data, createdAt: now,
                                              expireAt: done, bestBefore: best,
                                              maker: makerFinal)
        return LabelDraft(data: data, record: record)
    }
}

#Preview {
    NavigationStack {
        KombuchaTemplateView()
    }
}
