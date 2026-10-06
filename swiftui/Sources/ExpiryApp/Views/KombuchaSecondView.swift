//
//  KombuchaSecondView.swift
//  康普茶二发 —— 扫一扫取回一发信息后，只补一个水果名即可。
//
//  规则（与安卓/Flutter 版一致）：
//    标题 = 「{一发标题}-{水果}」
//    制备时间 = 扫码那一刻
//    完成时间 = 一发完成时间 + 3 天
//    最佳使用时间 = 沿用一发的最佳使用时间
//

import SwiftUI

struct KombuchaSecondView: View {
    let first: KombuchaFirstLabel

    @State private var fruit = ""
    @State private var maker = Prefs.lastMaker
    @State private var busy = false
    @State private var showFruitAlert = false

    @State private var showPreview = false
    @State private var pdfData = Data()
    @State private var fileName = ""

    var body: some View {
        List {
            Section {
                LabeledContent("一发标题", value: first.title)
                LabeledContent("制备时间", value: LabelTemplate.fmtDateTime(first.prepared))
                LabeledContent("完成时间", value: LabelTemplate.fmtDateTime(first.finished))
                LabeledContent("最佳使用时间", value: LabelTemplate.fmtDateTime(first.bestBefore))
                if !first.maker.isEmpty {
                    LabeledContent("制作人", value: first.maker)
                }
            } header: {
                Text("扫到的一发信息")
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(Theme.brand)
                        .frame(width: 22)
                    TextField("例：百香果", text: $fruit)
                }
                HStack(spacing: 12) {
                    Image(systemName: "person")
                        .foregroundStyle(Theme.brand)
                        .frame(width: 22)
                    TextField("例：四野", text: $maker)
                }
            } header: {
                Text("本次二发")
            } footer: {
                Text("标题将为「\(first.title)-\(fruit.isEmpty ? "水果" : fruit)」")
            }

            Section {
                Label("制备时间 = 扫码这一刻", systemImage: "clock")
                Label("完成时间 = 一发完成 + 3 天", systemImage: "calendar")
                Label("最佳使用时间 = 沿用一发", systemImage: "calendar.badge.checkmark")
            } header: {
                Text("自动推算")
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryActionBar(
                title: "生成标签",
                busyTitle: "生成中…",
                hint: "标签规格 50 × 30 mm · 生成后可预览 / 打印 / 分享",
                isBusy: busy,
                action: generate
            )
        }
        .navigationTitle("康普茶 · 二发")
        .navigationBarTitleDisplayMode(.inline)
        .alert("请先填写水果", isPresented: $showFruitAlert) {
            Button("好", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showPreview) {
            PreviewView(pdfData: pdfData, fileName: fileName)
        }
    }

    private func generate() {
        let f = fruit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty else {
            showFruitAlert = true
            return
        }
        let makerValue = maker.trimmingCharacters(in: .whitespacesAndNewlines)
        let makerFinal = makerValue.isEmpty ? "未署名" : makerValue
        Prefs.lastMaker = maker

        let now = Date()
        let data = LabelTemplate.buildKombuchaSecond(
            firstTitle: first.title,
            fruit: f,
            now: now,
            firstFinished: first.finished,
            firstBestBefore: first.bestBefore,
            maker: makerFinal
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
        KombuchaSecondView(
            first: KombuchaFirstLabel(
                title: "康普茶-红茶",
                prepared: Date(),
                finished: Date(),
                bestBefore: Date(),
                maker: "四野"
            )
        )
    }
}
