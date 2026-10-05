//
//  PreviewView.swift
//  标签预览 —— PDF 展示 + 保存到手机 + 分享 + 一键打印。
//

import PDFKit
import SwiftUI
import UIKit

struct PreviewView: View {
    let pdfData: Data
    let fileName: String

    @Environment(\.dismiss) private var dismiss
    @State private var saveAlert = false
    @State private var saveMessage = ""
    @State private var showShare = false
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PDFKitView(data: pdfData)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 12) {
                    Button {
                        saveToPhone()
                    } label: {
                        Label("保存到手机", systemImage: "arrow.down.to.line")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)

                    Button {
                        printLabel()
                    } label: {
                        Label("一键打印", systemImage: "printer")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.brand)
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
            .alert(saveMessage, isPresented: $saveAlert) {
                Button("好", role: .cancel) {}
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func saveToPhone() {
        do {
            let path = try PdfSaver.save(pdfData, fileName: fileName)
            saveMessage = "已保存到：\n\(path)\n\n也可在「文件」App → 我的 iPhone → 效期管理系统 中查看。"
        } catch {
            saveMessage = "保存失败：\(error.localizedDescription)"
        }
        saveAlert = true
    }

    private func prepareShare() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try pdfData.write(to: tmp, options: .atomic)
            shareURL = tmp
            showShare = true
        } catch {
            saveMessage = "分享失败：\(error.localizedDescription)"
            saveAlert = true
        }
    }

    private func printLabel() {
        // 打印逻辑由 PrinterService 处理（后续接入硕方 SDK）。
        PrintCoordinator.shared.print(pdfData: pdfData, fileName: fileName)
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
