//
//  RootView.swift
//  主壳：三个等规格标签（模板 / 扫码 / 打印机）。
//
//  iOS 26 上 TabView 的底栏自动就是苹果原厂 Liquid Glass（浮动玻璃条），
//  这是纯原生效果，与 Flutter 版靠 UiKitView 硬嵌的「割裂感」完全不同。
//

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            TemplatesTab()
                .tabItem {
                    Label("模板", systemImage: "square.grid.2x2")
                }

            ScanView()
                .tabItem {
                    Label("扫码", systemImage: "qrcode.viewfinder")
                }

            PrinterMenuView()
                .tabItem {
                    Label("打印机", systemImage: "printer")
                }
        }
    }
}

#Preview {
    RootView()
}
