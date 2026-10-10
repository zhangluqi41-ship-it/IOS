//
//  AppRouter.swift
//  App 级「要去哪」的路由信箱 —— 让**外部入口**能把 App 送到指定页面。
//
//  ★★★【第十轮·用户图5】为什么要这个文件：
//    用户原话：「点击灵动岛的消息后会自动跳到 app 中，但是打开的画面是
//    上次退出时的画面。逻辑应该改为：点击灵动岛 -> 进入 APP 的效期管理界面」
//
//    在此之前工程里**完全没有路由层**：`RootView` 的 `nav.selection` 是它自己
//    的私有状态，外部（`UNUserNotificationCenterDelegate`、`onOpenURL`）
//    就算知道该去哪也**没有任何入口把指令递进去**。
//
//  ★ 为什么用单例 + `@Published` 而不是 EnvironmentObject：
//    通知回调发生在 `App` 结构体之外（`NotificationPresenter` 里），
//    拿不到 SwiftUI 的环境。用一个 `@MainActor` 单例当「信箱」最直接。
//
//  ★ 为什么 `pendingTab` 用完要清成 nil：
//    否则用户手动切到别的 Tab 后，任何一次重绘都会把它又拽回效期管理。
//

import Foundation
import SwiftUI

@MainActor
final class AppRouter: ObservableObject {

    static let shared = AppRouter()

    /// 外部要求切换到的 Tab（消费后置回 nil）。
    @Published var pendingTab: AppTab?

    /// 外部要求弹出详情的记录 id（消费后置回 nil）。
    @Published var pendingRecordID: String?

    private init() {}

    // MARK: - 投递

    /// 把 App 送到「效期管理」。
    ///
    /// - Parameter recordID: 想同时弹出详情的那条记录；不需要就传 nil。
    func goToExpiry(recordID: String? = nil) {
        pendingRecordID = recordID
        pendingTab = .expiry
    }

    /// 处理一条 deep link（来自锁定屏幕卡片 / 灵动岛的 `widgetURL`）。
    func handle(_ url: URL) {
        guard let parsed = ExpiryDeepLink.parse(url) else { return }
        guard parsed.expiry else { return }
        goToExpiry(recordID: parsed.recordID)
    }

    // MARK: - 消费

    /// 取走「要切到哪个 Tab」。取走后清空（只生效一次）。
    func takeTab() -> AppTab? {
        defer { pendingTab = nil }
        return pendingTab
    }

    /// 取走「要弹出哪条记录」。取走后清空。
    func takeRecordID() -> String? {
        defer { pendingRecordID = nil }
        return pendingRecordID
    }
}
