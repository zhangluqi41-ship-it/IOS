//
//  RootView.swift
//  主壳：三个等规格标签（模板 / 扫码 / 打印机）。
//
//  使用 iOS 18+ 的 Tab API（规格 5.1）：Liquid Glass 标签栏由系统自动提供，
//  零代码继承；同时享受系统自适应行为（窗口变窄自动收进溢出菜单等）。
//

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("模板", systemImage: "square.grid.2x2") {
                TemplatesTab()
            }
            Tab("扫码", systemImage: "qrcode.viewfinder") {
                ScanView()
            }
            Tab("打印机", systemImage: "printer") {
                PrinterMenuView()
            }
        }
    }
}

#Preview {
    RootView()
}
