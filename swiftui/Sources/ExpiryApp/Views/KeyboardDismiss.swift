//
//  KeyboardDismiss.swift
//  模板页的键盘交互 —— 填完信息不想打印时，键盘不能赖在屏幕上挡住下面的内容。
//
//  ★★★ 2026-10-10（第二十一轮·本次）**修好「滑动收键盘」**。
//
//     用户复验 v1.1.4：
//       「点击屏幕收回键盘了，并且很流畅 ✅ —— 但是**滑动屏幕并没有收回键盘**，需要修改」
//
//     ★ 根因 = 上一轮我给容器加的 **`.contentShape(Rectangle())`**。
//
//       我当时的理由是"`List` 空白处不接收点击，不加就点空白没反应"——
//       这个判断只对了一半：`.contentShape` **确实**能扩大点击区，
//       但它同时会把这个区域变成一个**在 layout 阶段就固定的命中矩形**，
//       于是它与 `List` 内部的**滚动手势**发生竞争：
//         手指落下 → 命中矩形把触摸先揽住 → `List` 的 `UIScrollView`
//         收不到那次 pan → `.scrollDismissesKeyboard` **永不触发**。
//       表现就是用户看到的：**点能收、滑不能收**。
//
//     ➜ 正解 = **去掉 `.contentShape`，把「点空白」交给系统自己**。
//       `List` 底层是 `UICollectionView`，它有**内建的键盘收起行为**：
//       点/拖空白处时系统自己会收键盘 —— 这本来就是第一方的默认行为。
//       ⚠️ 之前之所以"点空白没反应"，是因为**我们自己写的 window 手势把它搅乱了**
//          （已删除）；window 手势一去掉，系统默认行为就回来了。
//       ➜ 所以本文件现在**只剩一行第一方修饰符**。
//
//     ⚠️ 这也解释了为什么"点空白"在 v1.1.4 能生效 —— 是我们那条 `.onTapGesture`
//        在起作用；但它顺手把滚动也吃掉了。现在换成系统的默认行为，两者兼得。
//
//  ⚠️ 历史上被删掉、**绝不要再写回来**的东西（每一样都踩过坑）：
//     · `window` 上的 `UITapGestureRecognizer` —— 吞掉系统弹层的关闭条件；
//     · `FocusCoordinator` 全局单例 —— 三跳跨事务，键盘动画慢半拍；
//     · `SoftKeyboard.hide()`（`resignFirstResponder`）—— 不带转场上下文，键盘瞬间消失；
//     · `UIPanGestureRecognizer` —— 与系统滚动识别器二选一，两败俱伤；
//     · `.contentShape` + `.onTapGesture` —— 吃滚动（就是本次修的这条）。

import SwiftUI

// MARK: - 一行挂载

/// 带输入框的页面统一挂这个。
///
/// ★ 收键盘**只走苹果第一方的两条既有行为**，不新增任何手势、不拦任何触摸：
///
/// 1. **滑动** → `.scrollDismissesKeyboard(.interactively)`
///    键盘**跟着手指逐帧走**，拖到哪收到哪 —— 这就是「流畅动画」本身。
///    ⚠️ 别改回 `.immediately`（滚动一开始就瞬间收起，无动画，被用户连否两次）。
///
/// 2. **点空白** → `List`（底层 `UICollectionView`）的**内建行为**，无需我们写代码。
///    ⚠️ 一定不要为了"扩大点击范围"再挂 `.contentShape` / `.onTapGesture` ——
///       那会与滚动识别器竞争，导致**滑动收不了键盘**（本次用户报的就是这个）。
///
/// - Parameter focus: 页面自己的 `@FocusState` 绑定。**保留形参是为了两个用途**：
///   ① 让调用点保持"这个页面有输入焦点"的语义（编译器也会检查页面确实持有它）；
///   ② 将来若确实需要程序化失焦（例如提交后收键盘），直接写 `focus.wrappedValue = nil`
///      即可 —— 那是第一方做法，和按回车同一条路径。
struct KeyboardDismissModifier: ViewModifier {
    var focus: FocusState<AnyHashable?>.Binding

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
    }
}
