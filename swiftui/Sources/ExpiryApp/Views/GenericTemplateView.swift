//
//  GenericTemplateView.swift
//  通用效期 —— 标题手填 + 两个日期（统一「日期」组）+ 快捷档位。
//

import SwiftUI

struct GenericTemplateView: View {
    @State private var title = ""
    @State private var maker = Prefs.lastMaker
    @State private var expireDate = Date()
    @State private var bestDate = Date()
    @State private var busy = false
    @State private var showTitleAlert = false

    @State private var showPreview = false
    @State private var pdfData = Data()
    @State private var fileName = ""

    var body: some View {
        List {
            Section {
                field(icon: "tag", placeholder: "例：杨桃菠萝浓缩汁", text: $title)
                field(icon: "person", placeholder: "例：四野", text: $maker)
            } footer: {
                Text("会记住上次填写的名字")
            }

            Section {
                DatePicker("原始保质期", selection: $expireDate, displayedComponents: .date)
                QuickDateChips(selection: $expireDate)

                DatePicker("最佳使用时间", selection: $bestDate, displayedComponents: .date)
                QuickDateChips(selection: $bestDate)
            } header: {
                Text("日期")
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
                Text("标签规格 50 × 30 mm · 生成后可预览 / 打印 / 分享")
            }
        }
        .navigationTitle("通用效期")
        .navigationBarTitleDisplayMode(.inline)
        .alert("请先填写标题", isPresented: $showTitleAlert) {
            Button("好", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showPreview) {
            PreviewView(pdfData: pdfData, fileName: fileName)
        }
    }

    private func field(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.brand)
                .frame(width: 22)
            TextField(placeholder, text: text)
        }
    }

    private func generate() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            showTitleAlert = true
            return
        }
        let makerValue = maker.trimmingCharacters(in: .whitespacesAndNewlines)
        let makerFinal = makerValue.isEmpty ? "未署名" : makerValue
        Prefs.lastMaker = maker

        let now = Date()
        let data = LabelTemplate.buildGeneric(
            title: t, now: now, expireDate: expireDate,
            bestBefore: bestDate, maker: makerFinal
        )
        let regular = FontProvider.regular(12)
        let bold = FontProvider.bold(12)
        pdfData = LabelRenderer.renderPDF(data, regular: regular, bold: bold)
        fileName = LabelTemplate.labelFileName(t, now)
        showPreview = true
    }
}

/// 快捷档位：+7 天 / +15 天 / +1 个月。
struct QuickDateChips: View {
    @Binding var selection: Date

    @State private var selectedLabel = ""

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.label) { p in
                Button {
                    selection = p.date
                    selectedLabel = p.label
                } label: {
                    Text(p.label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            selectedLabel == p.label ? Theme.brand : Color(.tertiarySystemFill),
                            in: Capsule()
                        )
                        .foregroundStyle(selectedLabel == p.label ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }

    private struct Preset {
        let label: String
        let date: Date
    }

    private var presets: [Preset] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func add(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: today) ?? today }
        func addMonth(_ m: Int) -> Date { cal.date(byAdding: .month, value: m, to: today) ?? today }
        return [
            Preset(label: "+7 天", date: add(7)),
            Preset(label: "+15 天", date: add(15)),
            Preset(label: "+1 个月", date: addMonth(1)),
        ]
    }
}

#Preview {
    NavigationStack {
        GenericTemplateView()
    }
}
