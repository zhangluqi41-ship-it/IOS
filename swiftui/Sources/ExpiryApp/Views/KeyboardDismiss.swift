//
//  KeyboardDismiss.swift
//  模板页的键盘交互 —— 填完信息不想打印时，键盘不能赖在屏幕上挡住下面的内容。
//
//  ─────────────────── 五轮反复的最终结论（v1.1.6） ───────────────────
//
//  用户从第十八轮到第二十一轮，连续五轮报同一件事，而每一轮我都在
//  **自己实现一遍收键盘**，每一轮都被否：
//
//    第 18 轮：自绘 `UIPanGestureRecognizer`          → 滑动卡顿
//    第 19 轮：`window` 上的 `UITapGestureRecognizer`
//              + 全局 `FocusCoordinator`（三跳跨事务）→ 瞬间收回、无动画
//    第 20 轮：`SoftKeyboard.hide()`（`resignFirstResponder`）→ 依然无动画
//    第 21 轮：容器上 `.contentShape` + `.onTapGesture` → 点能收、滑不能收
//    第 22 轮：把上面那个删掉                            → 点、滑**全都无响应**
//
//  ★★★ 每一轮的失败都是同一个原因：**"自己实现" = 代理系统本该做的事**，
//     一旦代理就要处理命中测试、手势优先级、通信、时序 —— 必然写歪。
//
//  ★★★ 第 22 轮（本次）的根因，恰恰是"删多了"：
//      `.contentShape` 提供的不只是"扩大点击区"，它还是让这块区域
//      **能接收触摸**的前提。一删，容器就完全不参与命中测试了 ——
//      所以「点也不能收、滑也不能收，完全无响应」。
//
//  ➜ 最终定案 = **不碰容器，只碰"每一行"**：
//     收键盘这件事本质上只发生在**用户点到某一行**的时候，所以：
//       · 空白／静态行 → 点一下收键盘（`.contentShape` 挂在**行**上，是行级、无副作用）；
//       · 输入框行     → 点了当然不收（要继续打字）；
//       · `List` 滚动  → `.scrollDismissesKeyboard(.interactively)` 系统负责。
//     这样既不与滚动竞争（没碰容器），也不会"完全无响应"（行自己接收触摸）。
//
//  ⚠️ 墓碑（别再写回来）：`UIPanGestureRecognizer` / `window` 手势 /
//     `FocusCoordinator` / `SoftKeyboard.hide()` / **容器级** `.contentShape`。

import SwiftUI

// MARK: - 收键盘的专用区

/// 「收起键盘」区：`List` 最末尾的一段，点它 = 收键盘。
///
/// ★ 为什么这么做（而不是"点 List 任意空白处"）：
///   容器级手势（`.contentShape` 挂 `List` 上）会与 `List` 的滚动手势**抢触摸** ——
///   命中矩形在 layout 阶段就固定，手指一落就被揽住，滚动识别器收不到 pan，
///   `.scrollDismissesKeyboard` 于是**永远不触发**（第 21 轮踩的坑）。
///   所以：**碰行，不碰容器**。
///
/// ★ 为什么它自己不会重蹈覆辙：
///   它是一行**普通的 `List` 行**，`.contentShape` 只挂在这一个 `frame` 内 ——
///   手指点在别处根本轮不到它，滚动也完全不受影响。
///   （`.contentShape(Rectangle())` 在这里的作用：`Color.clear` 本身**不参与命中测试**，
///     必须显式声明"这块矩形可点"，否则又是"点了没反应"。）
///
/// - Parameter focus: 页面自己的 `@FocusState` 绑定，直接写 `nil`（与按回车同一条路径）。
struct KeyboardDismissRow: View {
    var focus: FocusState<AnyHashable?>.Binding

    var body: some View {
        Button {
            focus.wrappedValue = nil
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.chevron.compact.down")
                Text("收起键盘")
                Spacer()
            }
            // ★ 撑满整行宽度：`Button` 在 `List` 行里默认只占内容宽度，
            //   不加这句就只有左侧一小块能点。
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // ★ 系统强调色 —— 与页面里其他可点条目一致（不覆写颜色）。
        .foregroundStyle(.secondary)
    }
}

// MARK: - 一行挂载

/// 带输入框的页面统一挂这个：**只挂第一方的滑动收键盘**。
///
/// ★ 点空白收键盘由页面在 `List` 末尾放一段 `KeyboardDismissRow` 负责 ——
///   那是**行级**的、局部的，不像容器级手势那样会与滚动竞争。
///
/// - Parameter focus: 页面自己的 `@FocusState` 绑定。
struct KeyboardDismissModifier: ViewModifier {
    var focus: FocusState<AnyHashable?>.Binding

    func body(content: Content) -> some View {
        content
            // ★ 苹果第一方的「滑动收键盘」。
            //   `.interactively`：键盘**跟着手指逐帧走**，拖到哪收到哪 = 流畅动画。
            //   ⚠️ 别改回 `.immediately`（滚动一开始就瞬间收起，无动画，被用户连否两次）。
            //   ⚠️ 绝不要在容器上再挂 `.contentShape` / 手势 —— 会与这条系统识别器竞争。
            .scrollDismissesKeyboard(.interactively)
    }
}
