//
//  ExpiryWidgetBundle.swift
//  Widget 扩展入口。
//
//  ★ 这个扩展目前只提供灵动岛（Live Activity）一种 widget。
//
//  ★ 为什么必须单独一个 target：Live Activity 的 UI 由 WidgetKit 扩展渲染，
//    宿主 App 里没法内联 —— 这是 ActivityKit 的硬性结构要求。
//
//  ★ 为什么不需要 App Group：扩展渲染用的全部内容都由 `ContentState` 带过来，
//    它从不读 App 的数据。（按钮回写走 `LiveActivityIntent`，在主 App 进程执行。）
//

import SwiftUI
import WidgetKit

@main
struct ExpiryWidgetBundle: WidgetBundle {
    var body: some Widget {
        ExpiryLiveActivityWidget()
    }
}
