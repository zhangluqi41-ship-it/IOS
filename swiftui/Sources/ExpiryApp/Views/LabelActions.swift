//
//  LabelActions.swift
//  标签动作的公共装配 —— 四个模板页（通用 / 康普茶一发 / 康普茶二发 / 奶制品）
//  共用同一套「预览标签 / 打印」动作与提示，避免四处复制。
//
//  ★ 为什么用 `.toolbar(placement: .bottomBar)` 而不是大按钮：
//    用户要求把原来的「生成标签」大按钮改成二级工具栏，分成「预览标签」和「打印」
//    两个动作。bottom bar 是 iOS 的原生工具栏语义，在 iOS 26 上自动获得液态玻璃
//    材质，且不会和列表行叠出双层背景。
//

import SwiftUI

// MARK: - 提示

struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

// MARK: - 一张待输出的标签

/// 模板页把「标签数据 + 待入库记录」打包成 draft，
/// 预览与打印都从同一个 draft 出发生成 PDF，保证两边内容完全一致。
struct LabelDraft {
    let data: LabelData
    let record: LabelRecord

    var fileName: String {
        LabelTemplate.labelFileName(data.title, record.createdAt)
    }

    /// 生成 PDF（50×30mm 矢量，可直接送打印机）。
    func pdf() -> Data {
        LabelRenderer.renderPDF(data,
                                regular: FontProvider.regular(12),
                                bold: FontProvider.bold(12))
    }
}

/// 预览页的载荷。
struct PreviewPayload: Identifiable {
    let id = UUID()
    let pdfData: Data
    let fileName: String
    let draft: LabelDraft
}

// MARK: - 底部工具栏

/// 二级工具栏：左边「预览标签」，右边「打印」。
struct LabelActionToolbar: ToolbarContent {
    let isBusy: Bool
    let onPreview: () -> Void
    let onPrint: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button(action: onPreview) {
                Label("预览标签", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(isBusy)

            Spacer()

            if isBusy {
                ProgressView()
            }

            Button(action: onPrint) {
                Label("打印", systemImage: "printer.fill")
                    .fontWeight(.semibold)
            }
            .tint(Theme.brand)
            .disabled(isBusy)
        }
    }
}

// MARK: - 动作修饰器

/// 给模板页挂上：底部工具栏 + 预览全屏页 + 忙碌指示 + 提示弹窗。
///
/// - Parameter build: 由各页自己实现——校验通过返回 `LabelDraft`，
///   校验不过时页面内部弹自己的提示并返回 `nil`。
struct LabelActions: ViewModifier {
    @Binding var preview: PreviewPayload?
    let build: () -> LabelDraft?

    @ObservedObject private var printer = PrinterService.shared

    @AppStorage("printCopies") private var copies: Int = 1
    @AppStorage("printDensity") private var density: Int = 0
    @AppStorage("paperType") private var paperType: Int = 1

    @State private var notice: Notice?

    func body(content: Content) -> some View {
        content
            .toolbar {
                LabelActionToolbar(isBusy: printer.isPrinting,
                                   onPreview: openPreview,
                                   onPrint: printNow)
            }
            .fullScreenCover(item: $preview) { payload in
                PreviewView(payload: payload)
            }
            .alert(notice?.title ?? "",
                   isPresented: Binding(get: { notice != nil },
                                        set: { if !$0 { notice = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(notice?.body ?? "")
            }
    }

    // MARK: 动作

    private func openPreview() {
        guard let draft = build() else { return }
        preview = PreviewPayload(pdfData: draft.pdf(),
                                 fileName: draft.fileName,
                                 draft: draft)
    }

    private func printNow() {
        guard printer.isConnected else {
            notice = Notice(title: "还没有连接打印机",
                            body: "请到「打印机」标签页扫描并连接硕方 T50 Pro，再回来打印。")
            return
        }
        guard let draft = build() else { return }

        printer.printLabel(pdf: draft.pdf(),
                           fileName: draft.fileName,
                           copies: copies,
                           density: density,
                           paperType: paperType,
                           record: draft.record) { ok, message in
            if ok {
                notice = Notice(title: "已发送到打印机",
                                body: "\(draft.data.title)\n份数 \(copies) · 浓度 \(density == 0 ? "自动" : "\(density)")")
            } else {
                notice = Notice(title: "打印失败",
                                body: message?.isEmpty == false ? message! : "请检查打印机状态后重试。")
            }
        }
    }
}
