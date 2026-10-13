//
//  DairyTemplateView.swift
//  奶制品 —— 只选类型 + 操作人，两个日期手填，快捷档位按类型推荐。
//

import SwiftUI

struct DairyTemplateView: View {
    @State private var kind: DairyKind?
    @State private var maker = Prefs.lastMaker
    @State private var expireDate = Date()
    @State private var bestDate = Date()
    @State private var showKindAlert = false
    /// ★ 第一方焦点（第十九轮）：收键盘走 `focused = nil`，键盘才有系统动画。
    @FocusState private var focus: AnyHashable?

    var body: some View {
        List {
            Section {
                // ★★★ 2026-10-13（用户反馈）：改成 `MenuPickerRow` —— **整行**都能点开
                //   菜单（原生的 `.pickerStyle(.menu)` 在 List 里只有尾部小箭头能点）。
                //   （同样没有「请选择」占位项：未选时右侧只是空的。）
                MenuPickerRow(title: "奶制品类型",
                              options: DairyKind.allCases,
                              optionLabel: { $0.label },
                              selection: $kind)

                if let k = kind {
                    Button {
                        applyRule(k)
                    } label: {
                        HStack {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(Theme.brand)
                            Text("按推荐填日期")
                                .foregroundStyle(Theme.brand)
                            Spacer()
                            Text("保质期 +\(k.expireDays) 天 · 最佳 +\(k.bestDays) 天")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                LabelDatePicker(title: "原始保质期（开封后）", date: $expireDate)
                LabelDatePicker(title: "最佳使用时间", date: $bestDate)
            } header: {
                Text("日期")
            }

            Section {
                MakerField(maker: $maker, focused: $focus)
            } footer: {
                Text("会记住上次填写的操作人")
            }
        }
        .navigationTitle("奶制品")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissible(focus: $focus)
        .modifier(LabelActions(build: buildDraft))
        .alert("请先选择奶制品类型", isPresented: $showKindAlert) {
            Button("好", role: .cancel) {}
        }
    }

    private func applyRule(_ k: DairyKind) {
        let cal = AppCalendar.shared
        let today = cal.startOfDay(for: Date())
        expireDate = cal.date(byAdding: .day, value: k.expireDays, to: today) ?? today
        bestDate = cal.date(byAdding: .day, value: k.bestDays, to: today) ?? today
    }

    private func buildDraft() -> LabelDraft? {
        guard let k = kind else {
            showKindAlert = true
            return nil
        }
        let makerFinal = MakerField.finalize(maker)

        let now = Date()
        let data = LabelTemplate.buildDairy(kindLabel: k.label, now: now,
                                            expireDate: expireDate,
                                            bestBefore: bestDate,
                                            maker: makerFinal)
        let record = LabelTemplate.makeRecord(kind: .dairy, data: data, createdAt: now,
                                              expireAt: expireDate, bestBefore: bestDate,
                                              maker: makerFinal)
        return LabelDraft(data: data, record: record)
    }
}

#Preview {
    NavigationStack {
        DairyTemplateView()
    }
}
