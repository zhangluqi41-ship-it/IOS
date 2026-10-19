import SwiftUI

// MARK: - 扫描原标签（二次制备）
//
// ★ 2026-10-19（用户）：「扫描二维码二次制备」——扫一张已有标签，
//   从中取「标题 + 最佳使用时间」，用来续做第二次制备（同康普茶二发）。
//
// 复用 `ScanView` 里的 `QRScannerModel` + `ScannerCameraView`（同一套相机管线），
// 只是把识别到的文本交给 `LabelTemplate.parseCustomQr` 解析，成功就回调并关闭。

struct SecondaryScanView: View {
    /// 解析成功：(原标签标题, 原标签的最佳使用时间)
    let onScanned: (String, Date) -> Void

    @StateObject private var scanner = QRScannerModel()
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScannerCameraView(session: scanner.session, interestSide: 220)
                    .ignoresSafeArea()

                // 取景框
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 220, height: 220)

                VStack {
                    Spacer()
                    Text(errorText ?? "把原标签的二维码对准取景框")
                        .font(.subheadline)
                        .foregroundStyle(errorText == nil ? Color.white.opacity(0.85) : Color.orange)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 40)
                }
            }
            .navigationTitle("扫描原标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                scanner.start()
            }
            .onDisappear {
                scanner.stop()
            }
            .onChange(of: scanner.lastCode) { _, code in
                guard let code else { return }
                if let parsed = LabelTemplate.parseCustomQr(code) {
                    scanner.stop()
                    onScanned(parsed.title, parsed.bestBefore)
                    dismiss()
                } else {
                    // 认出来不是本 App 的标签：提示后继续扫。
                    errorText = "这不是效期标签的二维码"
                    scanner.resume()
                }
            }
        }
    }
}
