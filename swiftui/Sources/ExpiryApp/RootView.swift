//
//  RootView.swift
//  主壳：四个一级页签（效期打印 / 扫码 / 效期管理 / 打印机）。
//
//  ★ 导航语义（用户明确要求）：
//    切走某个 Tab 时，把**被切走的那个 Tab** 的导航栈重置到根。
//    否则「模板 → 二级页 → 切到打印机 → 切回模板」会停在二级页。
//    要做到这一点，四个 NavigationStack 必须用显式 path 绑定，
//    且页面跳转必须走 value-based（`navigationDestination(for:)`）——
//    只有 value-based 导航才会写进 NavigationPath，重置才生效。
//

import SwiftUI

/// 四个一级页签。
enum AppTab: Hashable {
    case templates
    case scan
    case expiry
    case printer
}

struct RootView: View {
    @State private var selection: AppTab = .templates

    @State private var templatesPath = NavigationPath()
    @State private var scanPath = NavigationPath()
    @State private var expiryPath = NavigationPath()
    @State private var printerPath = NavigationPath()

    @ObservedObject private var store = ExpiryStore.shared

    var body: some View {
        TabView(selection: $selection) {
            Tab("效期打印", systemImage: "square.grid.2x2", value: AppTab.templates) {
                TemplatesTab(path: $templatesPath)
            }
            Tab("扫码", systemImage: "qrcode.viewfinder", value: AppTab.scan) {
                ScanView(path: $scanPath)
            }
            Tab("效期管理", systemImage: "calendar.badge.clock", value: AppTab.expiry) {
                ExpiryListView(path: $expiryPath)
            }
            .badge(store.alertingCount)
            Tab("打印机", systemImage: "printer", value: AppTab.printer) {
                PrinterMenuView(path: $printerPath)
            }
        }
        .onChange(of: selection) { old, new in
            guard old != new else { return }
            // 离开哪个 Tab，就把哪个 Tab 归位到一级菜单。
            resetToRoot(old)
        }
    }

    private func resetToRoot(_ tab: AppTab) {
        switch tab {
        case .templates:
            if !templatesPath.isEmpty { templatesPath = NavigationPath() }
        case .scan:
            if !scanPath.isEmpty { scanPath = NavigationPath() }
        case .expiry:
            if !expiryPath.isEmpty { expiryPath = NavigationPath() }
        case .printer:
            if !printerPath.isEmpty { printerPath = NavigationPath() }
        }
    }
}

#Preview {
    RootView()
}
