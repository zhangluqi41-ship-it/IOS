//
//  KeyboardDismiss.swift
//  模板页的键盘交互 —— 填完信息不想打印时，键盘不能赖在屏幕上挡住下面的内容。
//
//  ─────────────── 六轮反复的最终结论（v1.1.7 · 第二十三轮） ───────────────
//
//  用户从第十八轮到第二十三轮，连续六轮报同一件事，每一轮我都在
//  **自己实现一遍收键盘**，每一轮都被否：
//
//    第 18 轮：自绘 `UIPanGestureRecognizer`            → 滑动卡顿
//    第 19 轮：`window` 上的 `UITapGestureRecognizer`
//              + 全局 `FocusCoordinator`（三跳跨事务）  → 瞬间收回、无动画
//    第 20 轮：`SoftKeyboard.hide()`（`resignFirstResponder`）→ 依然无动画
//    第 21 轮：容器上 `.contentShape` + `.onTapGesture` → 点能收、滑不能收
//    第 22 轮：把上面那个删掉                            → 点、滑**全都无响应**
//    第 23 轮：改成"只点末尾那一行"                      → 用户要的是"**任意位置**"
//
//  ★★★ 第 23 轮（本次）终于找齐了三件事的**真实因果**：
//
//   ① 「滑动收不了键盘」的真正原因**不是手势被抢** —— 而是
//      **`List` 内容不满一屏、根本滚不动**！
//      模板页内容（名称/操作人/日期/打印）一屏就显示完了，
//      `.scrollDismissesKeyboard` 没有滚动事件可响应，自然"滑也没反应"。
//      ➜ 这条只能靠"点"来兜底，不能指望滚动。
//
//   ② 「点也不能收」的真正原因 = 我把命中区**做得太小**：
//      第 22 轮只在 `List` 末尾放了一行「收起键盘」按钮，
//      用户点页面其他空白处当然没反应。用户的原话一直是
//      「**点击屏幕任意位置**」，我却把它缩成了"点那一行"。
//
//   ③ 「日期点完不收」的真正原因 = 第 22 轮把"选完自动收"整个放弃了。
//      原生 `.compact` 的浮层**只能靠"点外面"关**，且它还会飘到屏幕上方
//      （用户截图）。所以"选完自动收"**必须回来** —— 但要用对方法。
//
//  ➜ 最终定案（两个部件分工明确，都不与系统抢）：
//
//   【点】`BackgroundTapDismisser` —— 用**第一方 UIKit 手势**铺在页面底层：
//        · `cancelsTouchesInView = false` → **绝不吞掉**按钮/输入框的触摸；
//        · `shouldReceive` 遇到 `UIControl` 返回 `false` → 点控件不触发收起；
//        · 挂在**背景层**（`List` 之下），滚动时手指落在 `List` 上，
//          手势**根本收不到**触摸 → **完全不影响滚动**（第 21 轮的病根就是这个）。
//
//   【滑】`.scrollDismissesKeyboard(.interactively)` 保持不变 ——
//        内容够长时它就是最好的方案；内容短（滚不动）时由【点】兜底。
//
//  ⚠️ 墓碑（别再写回来）：
//     · **`List` 容器上**挂 `.contentShape` + `.onTapGesture`（抢滚动手势，第 21 轮）；
//     · `window` 级手势（会吞掉系统弹层的关闭条件，第 19 轮）；
//     · `resignFirstResponder` / `SoftKeyboard.hide()`（无转场动画，第 20 轮）；
//     · `.id()` 重建控件（会连带销毁正在弹的日期浮层，第 22 轮）。
//

import SwiftUI
import UIKit

// MARK: - 背景层：点任意空白收键盘

/// 铺在页面**最底层**的透明层：点它 = 收键盘。
///
/// ★ 为什么用 UIKit 手势而不是 SwiftUI 的 `.onTapGesture`：
///   SwiftUI 的手势一旦挂在容器上，就会**参与命中测试**并吃掉触摸，
///   导致 `List`（底层 `UIScrollView`）收不到 pan → 滚动失效。
///   UIKit 手势 + `cancelsTouchesInView = false` + `shouldReceive` 过滤，
///   才能做到「点空白接管、点控件放行、滚动完全不受影响」。
///
/// ★ 为什么它铺在底层就不会影响滚动：
///   它只占 `List` **背后**的区域。手指落在 `List` 的可滚动内容上时，
///   触摸由 `List` 消费，这层根本收不到事件 —— 零竞争。
///   手指落在 `List` 之外的空白（分组间距、底部区域）时才轮到它。
struct BackgroundTapDismisser: UIViewRepresentable {
    var onTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = PassthroughView()
        // ★ 透明、不吃布局、不遮挡 —— 只负责收触摸。
        view.backgroundColor = .clear
        view.isOpaque = false

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        // ★★★ 这两行是"不抢控件"的关键：
        //   `cancelsTouchesInView = false` —— 命中后**不取消**已投递给控件的触摸，
        //     所以按钮/输入框照常收到自己的事件（收键盘与控件响应可以同时发生）。
        //   `delegate.shouldReceive` —— 手指落在 `UIControl`（按钮/输入框/开关）上时
        //     直接**返回 false**，手势根本不激活，控件完全按原生行为走。
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    /// 只在"没点到控件"时放行的手势代理。
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void

        init(onTap: @escaping () -> Void) { self.onTap = onTap }

        @objc func handleTap() { onTap() }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            // ★ 点在系统控件上 → 不接管（让输入框继续输入、按钮继续响应）。
            //   沿视图链往上找，任一祖先是 `UIControl` 就放行。
            var node: UIView? = touch.view
            while let current = node {
                if current is UIControl { return false }
                node = current.superview
            }
            return true
        }
    }

    /// 只接管"自己这一层"的触摸，其余一律穿透给下层视图。
    ///
    /// ★ 关键：`hitTest` 只在"点到自己身上"时返回 `self`，
    ///   这样它既是可靠的点击目标，又不会把 `List` 的触摸拦下来。
    final class PassthroughView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let hit = super.hitTest(point, with: event)
            return hit === self ? self : hit
        }
    }
}

// MARK: - 一行挂载

/// 带输入框的页面统一挂这个。
///
/// - Parameter focus: 页面自己的 `@FocusState` 绑定。
struct KeyboardDismissModifier: ViewModifier {
    var focus: FocusState<AnyHashable?>.Binding

    func body(content: Content) -> some View {
        content
            // ★ 苹果第一方的「滑动收键盘」。
            //   `.interactively`：键盘**跟着手指逐帧走**，拖到哪收到哪 = 流畅动画。
            //   ⚠️ 别改回 `.immediately`（滚动一开始就瞬间收起，无动画，被用户连否两次）。
            //   ⚠️ 模板页内容常常**不满一屏**（滚不动）→ 这条不会触发，
            //      所以「点任意空白收键盘」由 `BackgroundTapDismisser` 兜底。
            .scrollDismissesKeyboard(.interactively)
            // ★ 「点屏幕任意位置收键盘」—— 铺在底层，不碰 `List`、不碰滚动。
            .background(
                BackgroundTapDismisser {
                    // ★ 第一方收键盘：与按回车走同一条路径 → 有系统动画。
                    focus.wrappedValue = nil
                }
                .ignoresSafeArea()
            )
    }
}
