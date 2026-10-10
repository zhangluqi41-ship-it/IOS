//
//  KeyboardFocus.swift
//  第一方收键盘的「一行挂载」入口（2026-10-10 第十九轮）。
//
//  ★ 为什么单独一个文件：
//     `@FocusState` 的类型会传染 —— 只要 `MakerField` 收一个焦点绑定，
//     所有想用它、又想支持收键盘的页面都必须持有 `@FocusState`。
//     把这个「一行挂载」方法单独放，比塞进 `KeyboardDismiss.swift`
//     （那里全是 UIKit 手势）更好找。
//
//  ⚠️ 没有「不带 focus 的简版」—— 所有七个模板页都必须传 `focus:`。
//     提供简版会诱使人误用回「UIKit 瞬间收起、没动画」的老路（用户否定过三次）。
//

import SwiftUI

extension View {
    /// 给模板页挂上完整的键盘收起交互（**第一方焦点版**）。
    ///
    /// - Parameter focus: 页面的 `@FocusState<AnyHashable?>` 绑定。
    ///   本方法把它的当前值同步进 `FocusCoordinator`，之后
    ///   「点空白 / 滚动」收键盘都会走 `focused = nil` ——
    ///   由 SwiftUI 播**系统键盘动画**（而不是瞬间消失）。
    ///
    /// 用法：
    /// ```swift
    /// @FocusState private var focus: AnyHashable?
    /// ...
    /// List { TextField(...).focused($focus, equals: AnyHashable("title")) }
    ///     .keyboardDismissible(focus: $focus)
    /// ```
    func keyboardDismissible(focus: FocusState<AnyHashable?>.Binding) -> some View {
        modifier(KeyboardDismissModifier())
            .onChange(of: focus.wrappedValue) { _, _ in
                // ★ 只在变化时把新值抄给全局协调器（UIKit 手势靠它驱动焦点）。
                FocusCoordinator.shared.focused = focus.wrappedValue
            }
    }
}
