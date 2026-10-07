//
//  PreviewView.swift
//  标签预览 —— 位图自绘预览 + 保存到手机 + 分享 + 直接打印。
//
//  ⚠️⚠️ 2026-10-07：**当前没有任何入口**。
//     用户要求「取消预览标签功能，直接只需要打印」，所以
//     `LabelActionBar` 上的「预览标签」按钮和 `LabelActions` 里的
//     `.fullScreenCover` 都已移除（连带「保存到手机」「分享」一起下线）。
//     本文件保留在仓库里只是为了可快速恢复 —— 它记录了两个很贵的坑（见下），
//     恢复方式：在 `LabelActionBar` 加回按钮 + `LabelActions` 加回 fullScreenCover。
//
//  ★ 为什么不用 PDFKit 的 PDFView（曾经就是这样，结果是全白）：
//    `PDFView.autoScales` 要靠自身的 bounds 算 scaleFactor。放进 SwiftUI 的
//    UIViewRepresentable 时，`makeUIView` 那一刻视图尺寸还是 0，
//    算出来的缩放是错误的 → **整页空白**。
//    改成自己用 CGPDFDocument 栅格化再画成 Image，没有时序问题。
//
//  ★ 再加一道自检：栅格化后统计墨迹比例。如果画面上几乎没有墨，
//    直接告诉用户「渲染异常」，而不是给一张白纸让人以为是自己操作错了。
//
//  ★★ 为什么预览必须「自己算缩放」而不是丢进 ScrollView 里用 aspectRatio：
//    双向 ScrollView 会给子视图一个无界的尺寸建议，`aspectRatio(contentMode: .fit)`
//    在没有确定建议尺寸时是算不出来的 —— 它会退化成图片的**像素尺寸**
//    （栅格化是 1600px 宽，而屏幕只有 390pt），结果一进预览看到的就是放大了
//    四倍的一张纸、还必须左右拖着看（用户实测反馈过）。这里改成先用
//    GeometryReader 量出可用区域，再把图片等比缩到刚好放得下。
//

import SwiftUI
import UIKit

struct PreviewView: View {
    let payload: PreviewPayload

    @ObservedObject private var printer = PrinterService.shared
    @Environment(\.dismiss) private var dismiss

    @AppStorage("printCopies") private var copies: Int = 1
    @AppStorage("printDensity") private var density: Int = 0
    @AppStorage("paperType") private var paperType: Int = 1

    @State private var image: UIImage?
    @State private var inkRatio: Double = 0
    @State private var notice: Notice?
    @State private var shareURL: URL?
    @State private var showShare = false

    /// 相对于「刚好放得下」那一档的放大倍数。1.0 = 完整可见（默认）。
    @State private var scale: CGFloat = 1
    @State private var scaleAnchor: CGFloat = 1

    private let maxScale: CGFloat = 6
    private let doubleTapScale: CGFloat = 2.6

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewArea
                footer
                actionBar
            }
            .navigationTitle("标签预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if scale > 1.001 {
                        Button("还原") { resetZoom() }
                    }
                }
            }
            .task { renderPreview() }
            .alert(notice?.title ?? "",
                   isPresented: Binding(get: { notice != nil },
                                        set: { if !$0 { notice = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(notice?.body ?? "")
            }
            .sheet(isPresented: $showShare) {
                if let shareURL {
                    ShareSheet(items: [shareURL])
                } else {
                    Text("文件准备失败")
                        .foregroundStyle(.secondary)
                        .presentationDetents([.medium])
                }
            }
        }
    }

    // MARK: - 预览区

    @ViewBuilder
    private var previewArea: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemGroupedBackground)

                if let image {
                    // 先算出「刚好放得下」的尺寸，放大倍数再乘上去。
                    let fitted = fitSize(image.size, into: geo.size)
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: fitted.width * scale,
                                   height: fitted.height * scale)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                            .padding(14)
                            // 内容比可视区小时居中；放大后才有得滚。
                            .frame(minWidth: geo.size.width,
                                   minHeight: geo.size.height)
                    }
                    .defaultScrollAnchor(
                        scale > 1.001 ? UnitPoint.center : UnitPoint.top
                    )
                    .gesture(magnifyGesture)
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy) {
                            scale = scale > 1.001 ? 1 : doubleTapScale
                            scaleAnchor = scale
                        }
                    }
                } else {
                    ProgressView("正在渲染标签…")
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - 底部说明

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 6) {
            Text(scale > 1.001 ? "双指缩放 · 双击还原" : "50 × 30 mm · 双击放大")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if inkRatio < 0.05 && image != nil {
                Label("标签内容异常（画面几乎没有内容），请返回重新生成",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 操作区

    private var actionBar: some View {
        VStack(spacing: 10) {
            if printer.isPrinting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在发送到打印机…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                actionButton(title: "保存", icon: "arrow.down.to.line") {
                    saveToPhone()
                }
                .liquidGlassButton()

                actionButton(title: "分享", icon: "square.and.arrow.up") {
                    prepareShare()
                }
                .liquidGlassButton()

                actionButton(title: "打印", icon: "printer") {
                    printLabel()
                }
                .liquidGlassProminentButton()
                .tint(Theme.brand)
                .disabled(printer.isPrinting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.bar)
    }

    /// 三个按钮共用同一套排版，避免长文案的那一个被挤得比别的更大。
    private func actionButton(title: String,
                              icon: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }

    // MARK: - 手势

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(scaleAnchor * value.magnification, 1), maxScale)
            }
            .onEnded { _ in
                scaleAnchor = scale
            }
    }

    private func resetZoom() {
        withAnimation(.snappy) {
            scale = 1
            scaleAnchor = 1
        }
    }

    /// 等比缩放到「完全装得进 available」的尺寸（只缩不放）。
    private func fitSize(_ size: CGSize, into available: CGSize) -> CGSize {
        // 留出 14pt×2 的 padding
        let w = max(available.width - 28, 1)
        let h = max(available.height - 28, 1)
        guard size.width > 0, size.height > 0 else { return CGSize(width: w, height: h) }
        let k = min(w / size.width, h / size.height)
        return CGSize(width: size.width * k, height: size.height * k)
    }

    // MARK: - 渲染

    private func renderPreview() {
        guard image == nil else { return }
        guard let rendered = PDFRasterizer.firstPageImage(from: payload.pdfData, maxPixel: 1600) else {
            notice = Notice(title: "预览失败", body: "标签文件无法解析，请返回重新生成。")
            return
        }
        image = rendered
        inkRatio = PDFRasterizer.inkRatio(of: rendered)
    }

    // MARK: - 保存 / 分享

    private func saveToPhone() {
        do {
            let path = try PdfSaver.save(payload.pdfData, fileName: payload.fileName)
            notice = Notice(title: "已保存",
                            body: "位置：\n\(path)\n\n也可在「文件」App → 我的 iPhone → 效期管理系统 中查看。")
        } catch {
            notice = Notice(title: "保存失败", body: error.localizedDescription)
        }
    }

    private func prepareShare() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(payload.fileName)
        do {
            try payload.pdfData.write(to: url, options: .atomic)
            shareURL = url
            showShare = true
        } catch {
            notice = Notice(title: "分享失败", body: error.localizedDescription)
        }
    }

    // MARK: - 打印

    private func printLabel() {
        guard printer.isConnected else {
            notice = Notice(title: "还没有连接打印机",
                            body: "请到「打印机」标签页扫描并连接硕方 T50 Pro，再回来打印。")
            return
        }
        printer.printLabel(pdf: payload.pdfData,
                           fileName: payload.fileName,
                           copies: copies,
                           density: density,
                           paperType: paperType,
                           record: payload.draft.record) { ok, message in
            if ok {
                notice = Notice(title: "已发送到打印机",
                                body: "份数 \(copies) · 浓度 \(density == 0 ? "自动" : "\(density)")")
            } else {
                notice = Notice(title: "打印失败",
                                body: message?.isEmpty == false ? message! : "请检查打印机状态后重试。")
            }
        }
    }
}

/// 系统分享面板（UIActivityViewController 包装）。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ v: UIActivityViewController, context: Context) {}
}
