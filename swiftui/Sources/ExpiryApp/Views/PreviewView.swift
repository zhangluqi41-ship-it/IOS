//
//  PreviewView.swift
//  标签预览 —— 位图自绘预览 + 保存到手机 + 分享 + 直接打印。
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
    @State private var zoomed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewArea
                actionBar
            }
            .navigationTitle("标签预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
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
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 12) {
                if let image {
                    // 下面两种写法分开，避免 nil 尺寸的 frame 把布局压塌
                    if zoomed {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: image.size.width, height: image.size.height)
                            .background(Color.white)
                            .onTapGesture { withAnimation(.snappy) { zoomed = false } }
                            .padding(.horizontal, 8)
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                            .onTapGesture { withAnimation(.snappy) { zoomed = true } }
                            .padding(.horizontal, 20)
                    }
                } else {
                    ProgressView("正在渲染标签…")
                        .frame(height: 180)
                }

                Text(zoomed ? "点标签缩小" : "50 × 30 mm · 点标签放大")
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .frame(maxHeight: .infinity)
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

            HStack(spacing: 12) {
                Button {
                    saveToPhone()
                } label: {
                    Label("保存到手机", systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .liquidGlassButton()

                Button {
                    prepareShare()
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .liquidGlassButton()

                Button {
                    printLabel()
                } label: {
                    Label("打印", systemImage: "printer")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .liquidGlassProminentButton()
                .tint(Theme.brand)
                .disabled(printer.isPrinting)
            }
            .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.bar)
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
