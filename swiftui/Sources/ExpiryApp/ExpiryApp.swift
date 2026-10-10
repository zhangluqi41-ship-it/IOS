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

/// 让本地通知在 App 处于前台时也以横幅 + 声音呈现，并把
/// 「已完成使用 / 稍后提醒」两个动作转给 `ExpiryStore`。
///
/// ★ 2026-10-09 新增 `didReceive`：
///   通知上的按钮（以及灵动岛里的按钮走的是另一条路 —— `LiveActivityIntent`）
///   都是从这里进 App 的。少接这一个方法，按钮点下去就只是「打开 App」。
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification)
    async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse)
    async {
        let content = response.notification.request.content
        let recordID = content.userInfo[ExpiryStore.userInfoRecordID] as? String

        // ★★★【第十轮·用户图5】用户点的是**通知横幅本体**（不是上面的按钮）时，
        //   把 App 送到「效期管理」。
        //
        //   用户原话：「点击灵动岛的消息后会自动跳到 app 中，但是打开的画面是
        //   上次退出时的画面。逻辑应该改为：点击灵动岛 -> 进入 APP 的效期管理界面」
        //
        //   ⚠️ 这条分支以前是**完全缺失**的 —— 默认点击只让系统把 App 拉起来，
        //     停在用户上次退出的那个页面（他截图里是「扫码」页）。
        //   ⚠️ 只在**默认点击**时路由；两个动作按钮（已完成使用 / 稍后提醒）
        //     继续走 `handleNotificationResponse`，不要顺手弹页面。
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run {
                AppRouter.shared.goToExpiry(recordID: recordID)
            }
        }

        ExpiryStore.shared.handleNotificationResponse(
            actionIdentifier: response.actionIdentifier,
            userInfo: content.userInfo)
    }
}
