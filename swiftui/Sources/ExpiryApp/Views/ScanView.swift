//
//  ScanView.swift
//  扫码 —— AVFoundation 二维码扫描（后续完善取景框/手电筒/切换镜头）。
//  当前先占位，保证主壳可编译；完整实现见 Task #47。
//

import SwiftUI

struct ScanView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("扫码识别康普茶一发标签")
                    .font(.headline)
                Text("扫描功能开发中，稍后接入")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("扫码")
        }
    }
}

#Preview {
    ScanView()
}
