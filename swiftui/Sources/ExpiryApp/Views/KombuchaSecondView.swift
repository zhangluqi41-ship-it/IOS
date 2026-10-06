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
    @State private var showFruitAlert = false
    @State private var preview: PreviewPayload?

    var body: some View {
        List {
            Section {
                LabeledContent("一发标题", value: first.title)
                LabeledContent("制备时间", value: LabelTemplate.fmtDateTime(first.prepared))
                LabeledContent("完成时间", value: LabelTemplate.fmtDateTime(first.finished))
                LabeledContent("最佳使用时间", value: LabelTemplate.fmtDateTime(first.bestBefore))
                if !first.maker.isEmpty {
                    LabeledContent("操作人", value: first.maker)
                }
            } header: {
                Text("扫到的一发信息")
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(Theme.brand)
                        .frame(width: 22)
                    TextField("输入水果名称", text: $fruit)
                        .onChange(of: fruit) { _, value in
                            if value.count > LabelTemplate.maxNameLength {
                                fruit = String(value.prefix(LabelTemplate.maxNameLength))
                            }
                        }
                }
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
        .navigationTitle("康普茶 · 二发")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(LabelActions(preview: $preview, build: buildDraft))
        .alert("请先填写水果名称", isPresented: $showFruitAlert) {
            Button("好", role: .cancel) {}
        }
    }

    private func buildDraft() -> LabelDraft? {
        let f = LabelTemplate.clamp(fruit, LabelTemplate.maxNameLength)
        guard !f.isEmpty else {
            showFruitAlert = true
            return nil
        }
        let makerValue = LabelTemplate.clamp(maker, LabelTemplate.maxNameLength)
        let makerFinal = makerValue.isEmpty ? "未署名" : makerValue
        Prefs.lastMaker = makerValue

        let now = Date()
        let data = LabelTemplate.buildKombuchaSecond(firstTitle: first.title,
                                                     fruit: f,
                                                     now: now,
                                                     firstFinished: first.finished,
                                                     firstBestBefore: first.bestBefore,
                                                     maker: makerFinal)
        let done = AppCalendar.shared.date(byAdding: .day,
                                         value: LabelTemplate.kombuchaSecondDoneDays,
                                         to: first.finished) ?? first.finished
        let record = LabelTemplate.makeRecord(kind: .kombucha, data: data, createdAt: now,
                                              expireAt: done, bestBefore: first.bestBefore,
                                              maker: makerFinal)
        return LabelDraft(data: data, record: record)
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
