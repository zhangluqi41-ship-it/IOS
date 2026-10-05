//
//  PrinterMenuView.swift
//  打印机菜单 —— 已添加打印机列表 + 添加入口（后续完善）。
//  当前先占位，保证主壳可编译；完整实现见 Task #48。
//

import SwiftUI

struct PrinterMenuView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "printer")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("添加打印机")
                    .font(.headline)
                Text("打印机管理开发中，稍后接入")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("打印机")
        }
    }
}

#Preview {
    PrinterMenuView()
}
