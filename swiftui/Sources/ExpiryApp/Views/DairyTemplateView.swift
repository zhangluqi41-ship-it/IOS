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

    var body: some View {
        List {
            Section {
                Picker("奶制品类型", selection: $kind) {
                    // ★ 2026-10-09：去掉「请选择」占位项（用户反馈「点开后不应该
                    //   有『请选择』这个选项」）。未选时 selection 是 nil，
                    //   系统会自动把 label 显示成空白 —— 视觉上已经能看出「没选」，
                    //   再塞一条「请选择」只是多一个要划过去的废选项。
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
                AutoCloseDatePicker(title: "原始保质期（开封后）", date: $expireDate)
                AutoCloseDatePicker(title: "最佳使用时间", date: $bestDate)
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
        .keyboardDismissible()
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
