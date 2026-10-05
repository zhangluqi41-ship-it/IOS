//
//  ExpiryApp.swift
//  效期管理系统 —— 纯 SwiftUI 重写版
//
//  iOS 26 Liquid Glass：底栏 / 导航栏 / 按钮 / sheet / alert 等系统控件
//  用 Xcode 26 SDK 编译即自动获得液态玻璃材质，无需额外代码。
//

import SwiftUI

@main
struct ExpiryApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.brand)
        }
    }
}
