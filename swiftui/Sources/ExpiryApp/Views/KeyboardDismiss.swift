//
//  KeyboardDismiss.swift
//  模板页的键盘交互 —— 填完信息不想打印时，键盘不能赖在屏幕上挡住下面的内容。
//
//  ★★★ 2026-10-10（第二十轮·本次）**整条自造链路已删除，全部交回第一方**。
//
//     用户两轮反馈把问题彻底钉死了：
//       「点击或滑动屏幕任意位置收回键盘（要求流畅，使用苹果官方工具）……
//         比如键盘上右下角是『回车』，点击回车后可以流畅收回，要的是这个效果」
//       「不要增加冗余代码，需要检查代码是否存在重复」
//
//     ★ 用户的直觉**完全正确**，而且指出的正是根因：
//
//     【一、回车为什么丝滑】按回车时，UIKit 把结果**直接喂给 SwiftUI 的焦点系统**，
//        「识别触摸 → 改焦点 → 收键盘动画」发生在**同一次触摸事务**里，中间没有第三方。
//
//     【二、我们之前为什么不丝滑】上一轮搭的链路是：
//         window 上的 UITapGestureRecognizer  →  FocusCoordinator（全局 @Published）
//           →  onChange 单向抄回页面的 @FocusState  →  SwiftUI 才收键盘
//       这是**三跳、跨事务**的间接链：手势要等触摸**结束**才回调，写完全局值还要等
//       下一次 SwiftUI 更新周期才同步进页面，键盘动画因此在触摸结束后才起步 ——
//       观感就是「慢半拍 / 不跟手」，也就是用户说的「没有流畅动画」。
//
//     【三、这一层还替系统越权代管】那个 window 手势为了让输入框能正常聚焦，
//       对 `UIControl`（含 DatePicker）一律 `return false` 不接管。
//       而 `.compact` DatePicker 弹的是 UIKit 私有 popover，它**关闭的条件正是
//       「用户在弹层之外产生了一次触摸」** —— 我们把这次触摸判成"不归我管"，
//       系统那边就等于"什么都没发生"，于是弹层永远等不到关闭条件：
//       **这就是用户反复报的「点击后日期选项栏无收回」**。
//       （同一族问题即 iOS 17.1 那个著名的 DatePicker 回归。）
//
//     ➜ 定案：**收键盘这件事不写任何 UIKit 手势、不留任何全局状态**。
//       · 滑动 → `.scrollDismissesKeyboard(.interactively)`（系统识别器，零自研代码）
//       · 点空白 → 容器上的**局部** `.onTapGesture { focus = nil }`
//         （与 DatePicker 的 `.simultaneousGesture` 是同族机制：不抢控件、不劫持弹层）
//       两条路都**直接写页面自己的 `@FocusState`**，一步到位 —— 和回车同一条路径。
//
//     ⚠️ 本文件**刻意只剩一个 `ViewModifier`**。曾经存在过的
//        `SoftKeyboard` / `FocusCoordinator` / `KeyboardWatcher` /
//        `TapOutsideKeyboardDismisser` / `DismissKeyboardOnTap` / `WindowHookView`
//        **全部删除**，别再写回来（用户明确要求"不要冗余代码"）。
//     ⚠️ 别再往 window 上挂任何手势 —— 它会吞掉系统弹层（DatePicker）的关闭条件。
//     ⚠️ 别再引入 `UIPanGestureRecognizer` / `UISwipeGestureRecognizer` 收键盘 ——
//        系统识别器会与它「二选一」，既可能让 `.scrollDismissesKeyboard` 失效，
//        又会吞掉 `DatePicker` 的点击（第十八轮踩过）。

import SwiftUI

// MARK: - 一行挂载

/// 带输入框的页面统一挂这个：滑动收起 + 点空白收起。
///
/// ★ 两条路径**都是苹果第一方的**，且都直接驱动页面自己的 `@FocusState`：
///
/// 1. **滑动**：`.scrollDismissesKeyboard(.interactively)`
///    键盘**跟着手指逐帧走**，拖到哪收到哪 —— 这就是「流畅动画」本身。
///    ⚠️ 别改回 `.immediately`：它的语义是「滚动一开始就立刻收起」
///       = 瞬间消失、无动画（第十八、十九轮连否两次）。
///
/// 2. **点空白**：`.contentShape` + `.onTapGesture` 把整块可滚动区域变成可点区域，
///    点一下就把焦点置 `nil`。
///    ⚠️ 为什么不用 window 级手势：那会**替系统越权代管**触摸，
///       导致 DatePicker 弹层收不起来（见文件头「三」）。
///    ⚠️ 为什么必须 `contentShape`：`List` 的空白处本身不接收点击，
///       不加这句点空白会毫无反应。
///    ⚠️ **这是 `.onTapGesture` 不能挂 `List` 行上的唯一例外** ——
///       挂在**整块容器**上是安全的：`List` 行内的 `TextField` / `Picker` /
///       `Button` 都是 UIControl 系，它们**自己就消费点击**，不会把事件
///       冒泡给容器手势；只有真正点在空白处（无控件可消费）时才轮到我们。
///       而"挂在行上"会因为同一个行使上有 `TextField` 而互相抢 —— 第十五轮的坑。
///
/// - Parameter focus: 页面自己的 `@FocusState` 绑定。**直接写它**，一步到位，
///   不经过任何中转层 —— 与「按回车收键盘」走的是同一条内部路径。
struct KeyboardDismissModifier: ViewModifier {
    var focus: FocusState<AnyHashable?>.Binding

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                // ★ 第一方收键盘：清空焦点 → SwiftUI 自己播系统键盘动画。
                //   不需要任何兜底，也不需要判断"有没有第一响应者"。
                focus.wrappedValue = nil
            }
    }
}
