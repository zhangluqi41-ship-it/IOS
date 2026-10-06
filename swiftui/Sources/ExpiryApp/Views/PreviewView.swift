//
//  PreviewView.swift
//  标签预览 —— PDF 展示 + 保存到手机 + 分享 + 一键打印（真实打印）。
//

import PDFKit
import SwiftUI
import UIKit

struct PreviewView: View {
    let pdfData: Data
    let fileName: String

    @ObservedObject private var printer = PrinterService.shared

    @Environment(\.dismiss) private var dismiss
    @State private var noticeTitle = ""
    @State private var noticeBody = ""
    @State private var showNotice = false
    @State private var showShare = false
    @State private var shareURL: URL?

    @AppStorage("printCopies") private var copies: Int = 1
    @AppStorage("printDensity") private var density: Int = 0
    @AppStorage("paperType") private var paperType: Int = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PDFKitView(data: pdfData)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if printer.isPrinting {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在发送到打印机…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
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
                        printLabel()
                    } label: {
                        Label("一键打印", systemImage: "printer")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .liquidGlassProminentButton()
                    .tint(Theme.brand)
                    .disabled(printer.isPrinting)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .navigationTitle("标签预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        prepareShare()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .alert(noticeTitle, isPresented: $showNotice) {
                Button("好", role: .cancel) {}
            } message: {
                Text(noticeBody)
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    // MARK: - 保存 / 分享

    private func saveToPhone() {
        do {
            let path = try PdfSaver.save(pdfData, fileName: fileName)
            notice("已保存", "位置：\n\(path)\n\n也可在「文件」App → 我的 iPhone → 效期管理系统 中查看。")
        } catch {
            notice("保存失败", error.localizedDescription)
        }
    }

    private func prepareShare() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try pdfData.write(to: tmp, options: .atomic)
            shareURL = tmp
            showShare = true
        } catch {
            notice("分享失败", error.localizedDescription)
        }
    }

    // MARK: - 打印

    private func printLabel() {
        guard printer.isConnected else {
            notice("还没有连接打印机",
                   "请到「打印机」标签页扫描并连接硕方 T50 Pro，再回来打印。")
            return
        }
        printer.printLabel(pdf: pdfData,
                           fileName: fileName,
                           copies: copies,
                           density: density,
                           paperType: paperType) { ok, message in
            if ok {
                notice("已发送到打印机", "份数 \(copies) · 浓度 \(density == 0 ? "自动" : "\(density)")")
            } else {
                notice("打印失败", message?.isEmpty == false ? message! : "请检查打印机状态后重试。")
            }
        }
    }

    private func notice(_ title: String, _ body: String) {
        noticeTitle = title
        noticeBody = body
        showNotice = true
    }
}

/// PDFKit 预览。
struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .systemGroupedBackground
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document == nil {
            view.document = PDFDocument(data: data)
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
