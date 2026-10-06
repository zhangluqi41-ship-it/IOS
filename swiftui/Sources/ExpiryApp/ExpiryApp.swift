//
//  ExpiryApp.swift
//  效期管理系统 —— 纯 SwiftUI 重写版
//
//  iOS 26 Liquid Glass：底栏 / 导航栏 / 按钮 / sheet / alert 等系统控件
//  用 Xcode 26 SDK 编译即自动获得液态玻璃材质，无需额外代码。
//

import SwiftUI
import UserNotifications

@main
struct ExpiryApp: App {

    @StateObject private var store = ExpiryStore.shared

    init() {
        // 前台也能弹出到期提醒（默认前台是静默的）
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                // ★ 强制简体中文 + 公历：
                //   否则系统日期选择器会按设备语言显示英文月份 / 星期，
                //   设备把日历设成佛历 / 民国纪年时取出的年月日也是错的。
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                .environment(\.calendar, AppCalendar.shared)
                .tint(Theme.brand)
        }
    }
}

/// 让本地通知在 App 处于前台时也以横幅 + 声音呈现。
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification)
    async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }
}
