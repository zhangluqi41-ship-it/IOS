//
//  KeyboardFocus.swift
//  收键盘的「一行挂载」入口（2026-10-10 第二十一轮重写）。
//
//  ★★★ 这个文件现在短到只有一个函数 —— 因为**中间层全被拆掉了**。
//
//     用户从第十八轮到第二十一轮连续反馈同一件事「收键盘不流畅」，
//     每一轮我都在"加一层"（全局协调器 / window 手势 / contentShape + onTapGesture），
//     每一轮都被否掉。第二十一轮用户一句话点破：
//       「要求最高的苹果流畅度……自造工具的全部优化成 iOS 第一方的」
//
//     ➜ 结论：**收键盘不需要我们写任何代码。**
//       · 滑动 → `.scrollDismissesKeyboard(.interactively)`（一行修饰符）
//       · 点空白 → `List`/`UICollectionView` 的内建行为（零代码）
//       两者都是系统原生行为，**根本不用"实现"**。
//
//     而在此之前所有出问题的地方，都是因为**我们自己去代理了系统本该做的事**：
//     代理 = 必然要处理优先级、通信、时序 → 必然写歪 → 必然不流畅。
//
//  ⚠️ 没有「不带 focus 的简版」—— 所有模板页都必须传 `focus:`。
//     它同时是"这个页面有输入焦点"的编译期契约，也是将来需要程序化失焦时的入口。
//

import SwiftUI

extension View {
    /// 给模板页挂上键盘交互（**纯第一方，零自造代码**）。
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
