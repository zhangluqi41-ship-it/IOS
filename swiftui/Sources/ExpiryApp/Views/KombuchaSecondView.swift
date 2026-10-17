//
//  KombuchaSecondView.swift
//  康普茶二发 —— 扫一扫取回一发信息后，只补一个水果名即可。
//
//  规则：
//    标题 = 「{一发标题}-{水果}」
//    制备时间 = 扫码那一刻
//    完成时间 = **二发制备时间 + 3 天**（★ 见 `LabelTemplate.kombuchaSecondDone`）
//    最佳使用时间 = 沿用一发的最佳使用时间
//
//  ★ 2026-10-07 起页面只显示「二维码里真的有的东西」：
//    二维码内容已收紧为「名称 + 后两组时间」，不含一发的制备时间与制作人，
//    所以这两行不再展示（否则是一片空值）。若扫到的是**旧格式**标签
//    （里面还带制作人），操作人那行会自动出现。
//

import SwiftUI

struct KombuchaSecondView: View {
    let first: KombuchaFirstLabel

    @State private var fruit = ""
    @State private var maker = Prefs.lastMaker
    @State private var showFruitAlert = false
    /// ★★★ 2026-10-17（用户功能 2）：**原材料（一发那瓶）是否已用完**。
    ///   用户要求「扫描二维码后再加工的标签…增加『原材料是否用完』选项，
    ///   放在扫描后页面的最上面」；康普茶同理 —— 二发起发时把一发记录标用完。
    ///   默认**关**；开启且打印成功后 `consumeSourceRecord()` 才动数据。
    @State private var consumeSource = false
    /// ★ 第一方焦点（第十九轮）：收键盘走 `focused = nil`，键盘才有系统动画。
    @FocusState private var focus: AnyHashable?

    var body: some View {
        List {
            // ★★★ 2026-10-17（功能 2）：**放在页面最上面**（用户明确要求）。
            Section {
                Toggle(isOn: $consumeSource) {
                    Label("原材料已用完", systemImage: "checkmark.circle")
                }
            } footer: {
                Text("开启并打印后，会把效期管理里「\(first.title)」这条一发记录标记为已用完；"
                     + "关闭则不动它。")
            }

            Section {
                LabeledContent("一发标题", value: first.title)
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
                        .focused($focus, equals: AnyHashable("fruit"))
                        .onChange(of: fruit) { _, value in
                            if value.count > LabelTemplate.maxNameLength {
                                fruit = String(value.prefix(LabelTemplate.maxNameLength))
                            }
                        }
                }
                MakerField(maker: $maker, focused: $focus)
            } header: {
                Text("本次二发")
            } footer: {
                Text("标题将为「\(first.title)-\(fruit.isEmpty ? "水果" : fruit)」")
            }

            Section {
                Label("制备时间 = 扫码这一刻", systemImage: "clock")
                Label("完成时间 = 制备时间 + \(LabelTemplate.kombuchaSecondDoneDays) 天",
                      systemImage: "calendar")
                Label("最佳使用时间 = 沿用一发", systemImage: "calendar.badge.checkmark")
            } header: {
                Text("自动推算")
            }
        }
        .navigationTitle("康普茶 · 二发")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissible(focus: $focus)
        // ★ 功能 2：打印成功后再消耗原材料（失败不处理）。
        .modifier(LabelActions(build: buildDraft, onConfirmed: consumeSourceRecord))
        .alert("请先填写水果名称", isPresented: $showFruitAlert) {
            Button("好", role: .cancel) {}
        }
    }

    /// ★★★ 2026-10-17（功能 2）：把「这一发的那瓶」在效期管理里标为已用完。
    ///
    ///   定位方式：扫码时 `ScanView` 用**同一个二维码原文** `add()` 入库
    ///   （按 `qrText` 去重），所以 `qrText == first.sourceQR` 就是那条一发记录。
    ///   ⚠️ 只在 `consumeSource == true` 时执行。
    private func consumeSourceRecord() {
        guard consumeSource, !first.sourceQR.isEmpty else { return }
        guard let record = ExpiryStore.shared.records.first(where: {
            $0.qrText == first.sourceQR
        }) else { return }
        ExpiryStore.shared.markUsed(record)
    }

    private func buildDraft() -> LabelDraft? {
        let f = LabelTemplate.clamp(fruit, LabelTemplate.maxNameLength)
        guard !f.isEmpty else {
            showFruitAlert = true
            return nil
        }
        let makerFinal = MakerField.finalize(maker)

        let now = Date()
        let data = LabelTemplate.buildKombuchaSecond(firstTitle: first.title,
                                                     fruit: f,
                                                     now: now,
                                                     firstBestBefore: first.bestBefore,
                                                     maker: makerFinal)
        // ★ 与标签上的完成时间走**同一个来源**，别再各算一遍。
        let done = LabelTemplate.kombuchaSecondDone(after: now)
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
                finished: Date(),
                bestBefore: Date(),
                maker: "四野"
            )
        )
    }
}
