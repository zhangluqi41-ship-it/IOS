//
//  KeyboardFocus.swift
//  收键盘的「一行挂载」入口（2026-10-10 第二十轮重写）。
//
//  ★★★ 为什么这个文件变得这么短 —— 因为中间层被拆了。
//
//     上一轮（v1.1.3）这里还有个 `onChange(of: focus.wrappedValue)`，
//     作用是把页面焦点**抄给全局的 `FocusCoordinator`**，
//     好让挂在 window 上的 UIKit 手势能反过来驱动页面焦点。
//
//     ★ 那条链路是**三跳、跨事务**的（手势 → 全局值 → 抄回页面 → 收键盘），
//       键盘动画因此总要等触摸结束后的下一轮更新才起步 → 用户看到的「不流畅」。
//       而按回车时 UIKit 是**直接**改 SwiftUI 焦点的，同一次事务内完成 → 丝滑。
//
//     ➜ 现在**没有任何中转**：`.onTapGesture { focus = nil }` 直接写页面自己的
//       `@FocusState`，一步到位，和回车同路。
//     ⚠️ `FocusCoordinator` 已随本条链路一并删除，别再引入任何等价物
//        （用户明确要求「不要增加冗余代码」）。
//
//  ⚠️ 没有「不带 focus 的简版」—— 所有模板页都必须传 `focus:`。
//     收键盘必须知道"该清哪个焦点"，没有别的办法拿到它。
//

import SwiftUI

extension View {
    /// 给模板页挂上完整的键盘收起交互（**纯第一方，无中转层**）。
    ///
    /// - Parameter focus: 页面自己的 `@FocusState<AnyHashable?>` 绑定。
    ///
    /// 用法：
    /// ```swift
    /// @FocusState private var focus: AnyHashable?
    /// ...
    /// List { TextField(...).focused($focus, equals: AnyHashable("title")) }
    ///     .keyboardDismissible(focus: $focus)
    /// ```
    func keyboardDismissible(focus: FocusState<AnyHashable?>.Binding) -> some View {
        modifier(KeyboardDismissModifier(focus: focus))
    }
}
