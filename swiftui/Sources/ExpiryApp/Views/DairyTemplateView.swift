//
//  DairyTemplateView.swift
//  奶制品 —— 只选类型 + 制作人，两个日期手填，快捷档位按类型推荐。
//

import SwiftUI

struct DairyTemplateView: View {
    @State private var kind: DairyKind?
    @State private var maker = Prefs.lastMaker
    @State private var expireDate = Date()
    @State private var bestDate = Date()
    @State private var busy = false
    @State private var showKindAlert = false

    @State private var showPreview = false
    @State private var pdfData = Data()
    @State private var fileName = ""

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
                    TextField("例：四野", text: $maker)
                }
            } footer: {
                Text("会记住上次填写的名字")
            }

            Section {
                Button {
                    generate()
                } label: {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(busy ? "生成中…" : "生成标签")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.brand)
                .disabled(busy)
            } footer: {
                Text("标签三行 = 开封时间 / 原始保质期 / 最佳使用时间")
            }
        }
        .navigationTitle("奶制品")
        .navigationBarTitleDisplayMode(.inline)
        .alert("请先选择奶制品类型", isPresented: $showKindAlert) {
            Button("好", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showPreview) {
            PreviewView(pdfData: pdfData, fileName: fileName)
        }
    }

    private func applyRule(_ k: DairyKind) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        expireDate = cal.date(byAdding: .day, value: k.expireDays, to: today) ?? today
        bestDate = cal.date(byAdding: .day, value: k.bestDays, to: today) ?? today
    }

    private func generate() {
        guard let k = kind else {
            showKindAlert = true
            return
        }
        let makerValue = maker.trimmingCharacters(in: .whitespacesAndNewlines)
        let makerFinal = makerValue.isEmpty ? "未署名" : makerValue
        Prefs.lastMaker = maker

        let now = Date()
        let data = LabelTemplate.buildDairy(
            kindLabel: k.label, now: now, expireDate: expireDate,
            bestBefore: bestDate, maker: makerFinal
        )
        pdfData = LabelRenderer.renderPDF(data,
                                          regular: FontProvider.regular(12),
                                          bold: FontProvider.bold(12))
        fileName = LabelTemplate.labelFileName(k.label, now)
        showPreview = true
    }
}

#Preview {
    NavigationStack {
        DairyTemplateView()
    }
}
