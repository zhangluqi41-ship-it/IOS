//
//  DatePickerDismissal.swift
//  主动收起「已经弹出的」系统日期浮层。
//
//  ★★ 为什么需要它：
//     `.compact` / `.graphical` 样式的 `DatePicker` 弹出的日历属于 UIKit
//     自己管理的浮层（`UIDatePicker` 的 `_UIDatePickerView` popover），
//     SwiftUI 没有暴露「选中即关闭」的开关。
//
//     社区通行解法是改 `.id` 让 DatePicker 整体重建 —— 但那条路有硬伤：
//     滚轮每落定一个年/月/日，`date` 就变一次 → `.id` 立刻换新 →
//     **面板当场被销毁**，用户体验就是「选完年月马上就消失」。
//     这正是 2026-10-09 用户反馈的第 2 条。
//
//  ★ 本文件的解法：
//     不去重建、不去监听 date 的中间态，而是在**用户确实点中某一天之后**，
//     反向找到那个已经展示出来的 `UIDatePicker`，调用它内部的 dismiss。
//     面板于是活在「用户自己决定何时确认」的节奏里 —— 翻年翻月不会被打断。
//
//  ⚠️ 为什么单独放一个文件（而不是塞进 DateField.swift）：
//     它 import UIKit 且用 `UIApplication.shared`，是**主 App 专属**代码。
//     `ExpiryWidget` 扩展也编译 `Sources/ExpiryApp/Theme.swift`（为了品牌色），
//     如果这个文件混进那个目标，会连带把扩展编崩 —— 所以在 `project.yml`
//     里用 `excludes` 把它排除出扩展目标（见该文件 `ExpiryWidget.sources`）。
//
//  ⚠️ 依赖的是 UIKit 私有结构，`_UIDatePickerView` 这类名字**不能硬编码**：
//     这里只做「在视图树里找 `UIDatePicker` → 顺父链找带 `present` 语义的
//     view controller」两层通用查找，任何一层找不到就**静默失败**（不崩、
//     不报错、不 log）——最坏情况退化成「用户再点一下空白处才收」，
//     这正是 iOS 的默认行为，不会更差。
//

import SwiftUI
import UIKit

enum DatePickerDismissal {

    /// 冷却窗口（秒）。
    ///
    /// ★ 存在的意义：`UIDatePicker` 在**刚弹出**时会先发一次初值回调，
    ///   如果不加冷却，用户刚点开面板、手还没落在某一天上，就被自己收掉了。
    ///   0.35s 足够让「打开」与「选择」两个动作在时间上分开，
    ///   同时短到让人感知不到。
    private static let cooldown: TimeInterval = 0.35

    /// 上一次主动收起的时间戳（避免连续触发）。
    private static var lastDismiss: Date = .distantPast

    /// 用户「选中了一天」之后调用 —— 把当前展示的日期浮层收掉。
    static func dismissAfterSelection() {
        let now = Date()
        guard now.timeIntervalSince(lastDismiss) > cooldown else { return }
        lastDismiss = now

        // 延后一帧：此时 SwiftUI 已经处理完 binding 写入，
        // 浮层处在稳定状态，再去遍历视图树最稳。
        DispatchQueue.main.async {
            guard let picker = findPresentedDatePicker(in: keyWindow()) else { return }
            dismissAncestor(of: picker)
        }
    }

    // MARK: - 私有

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    /// 在视图树里广度优先找 `UIDatePicker`。
    ///
    /// ★ 只找**已经上屏**的那个（`window != nil`）—— 日历浮层里的那个才是；
    ///   列表里还没展开的 DatePicker 也是 UIDatePicker，但没收的必要。
    private static func findPresentedDatePicker(in window: UIWindow?) -> UIDatePicker? {
        guard let root = window else { return nil }
        var queue: [UIView] = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let picker = view as? UIDatePicker, picker.window != nil {
                return picker
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// 顺父链找到承载浮层的 view controller，把浮层收掉。
    ///
    /// ★ 日期浮层由 UIKit 内部的一个 presentation 容器承载，SDK 没有公开
    ///   它的类型名。这里用 `parent` 链找**第一个 `presentedViewController`
    ///   非空的** —— 那个就是浮层容器；对它 dismiss 即等价于「点空白处」。
    private static func dismissAncestor(of view: UIView) {
        var responder: UIResponder? = view
        while let current = responder {
            if let vc = current as? UIViewController,
               let presented = vc.presentedViewController {
                presented.dismiss(animated: true)
                return
            }
            responder = current.next
        }
    }
}
