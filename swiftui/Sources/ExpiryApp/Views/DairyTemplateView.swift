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
    @State private var preview: PreviewPayload?

    var body: some View {
        List {
            Section {
                Picker("奶制品类型", selection: $kind) {
                    Text("请选择").tag(nil as DairyKind?)
                    ForEach(DairyKind.allCases) { k in
                        Text(k.label).tag(Optional(k))
                    }
                }
                .pickerStyle(.menu)

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
                DatePicker("原始保质期（开封后）", selection: $expireDate, displayedComponents: .date)
                DatePicker("最佳使用时间", selection: $bestDate, displayedComponents: .date)
            } header: {
                Text("日期")
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "person")
                        .foregroundStyle(Theme.brand)
                        .frame(width: 22)
                    TextField("输入操作人", text: $maker)
                        .onChange(of: maker) { _, value in
                            if value.count > LabelTemplate.maxNameLength {
                                maker = String(value.prefix(LabelTemplate.maxNameLength))
                            }
                        }
                }
            } footer: {
                Text("会记住上次填写的操作人")
            }
        }
        .navigationTitle("奶制品")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(LabelActions(preview: $preview, build: buildDraft))
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
        let makerValue = LabelTemplate.clamp(maker, LabelTemplate.maxNameLength)
        let makerFinal = makerValue.isEmpty ? "未署名" : makerValue
        Prefs.lastMaker = makerValue

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
