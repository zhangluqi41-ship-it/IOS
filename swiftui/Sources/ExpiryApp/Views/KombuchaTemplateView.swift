//
//  KombuchaTemplateView.swift
//  康普茶一发 —— 只填茶叶品种 + 制作人，三个时间全自动推算。
//

import SwiftUI

struct KombuchaTemplateView: View {
    @State private var variety = ""
    @State private var maker = Prefs.lastMaker
    @State private var busy = false
    @State private var showVarietyAlert = false

    @State private var showPreview = false
    @State private var pdfData = Data()
    @State private var fileName = ""

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "leaf")
                        .foregroundStyle(Theme.brand)
                        .frame(width: 22)
                    TextField("例：红茶", text: $variety)
                }
                HStack(spacing: 12) {
                    Image(systemName: "person")
                        .foregroundStyle(Theme.brand)
                        .frame(width: 22)
                    TextField("例：四野", text: $maker)
                }
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
                Text("二发请用「扫一扫」识别一发标签上的二维码")
            }
        }
        .navigationTitle("康普茶 · 一发")
        .navigationBarTitleDisplayMode(.inline)
        .alert("请先填写茶叶品种", isPresented: $showVarietyAlert) {
            Button("好", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showPreview) {
            PreviewView(pdfData: pdfData, fileName: fileName)
        }
    }

    private func generate() {
        let v = variety.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else {
            showVarietyAlert = true
            return
        }
        let makerValue = maker.trimmingCharacters(in: .whitespacesAndNewlines)
        let makerFinal = makerValue.isEmpty ? "未署名" : makerValue
        Prefs.lastMaker = maker

        let now = Date()
        let data = LabelTemplate.buildKombuchaFirst(
            variety: v, now: now, maker: makerFinal
        )
        pdfData = LabelRenderer.renderPDF(data,
                                          regular: FontProvider.regular(12),
                                          bold: FontProvider.bold(12))
        fileName = LabelTemplate.labelFileName(data.title, now)
        showPreview = true
    }
}

#Preview {
    NavigationStack {
        KombuchaTemplateView()
    }
}
