//
//  KeyboardDismiss.swift
//  模板页的键盘交互 —— 填完信息不想打印时，键盘不能赖在屏幕上挡住下面的内容。
//
//  提供三种收起方式（用户要求「点屏幕或滑动屏幕自动隐藏键盘」）：
//    ① 滑动列表     → `.scrollDismissesKeyboard(.immediately)`
//    ② 点屏幕任意处 → 挂在 **window** 上的 UITapGestureRecognizer
//    ③ 键盘上方「完成」按钮（iOS 标准做法，兜底）
//
//  ★★ 为什么不用 `.onTapGesture` / `.simultaneousGesture(TapGesture())`：
//     把手指手势挂在 List 上会和 TextField 争抢 ——
//     轻则点输入框时键盘「闪一下」（刚聚焦就被手势收掉，表现为根本打不出字），
//     重则 List 直接吃掉这次点击、输入框根本聚焦不上。
//     所以改成往 window 上挂 `UITapGestureRecognizer`，并设
//     `cancelsTouchesInView = false`（**不吃掉这次触摸**）：
//     TextField 的聚焦 / 光标拖动、按钮点击照常生效，只是在同一次点击结束时
//     额外把键盘收起来 —— 这正是「点屏幕自动隐藏键盘」想要的效果。
//

import SwiftUI
import UIKit

/// 收起键盘的工具。
///
/// ★ 类型名刻意不叫 `Keyboard` —— 避免和系统框架里可能存在的同名类型撞上
///   导致解析歧义（这类问题只在编译期暴露，本机没有 Xcode 不好排查）。
enum SoftKeyboard {
    /// 收起键盘（对当前第一响应者 resign）。
    static func hide() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

/// 「点空白收起键盘」的安装器。
///
/// ★ 做成单例并记住装过的 window：SwiftUI 会反复创建/销毁 background 视图，
///   如果每次都挂一个手势，同一个 window 上很快会叠上一串 ——
///   功能上无害（都是收起键盘），但会白占内存、也让行为难以推理。
final class TapOutsideKeyboardDismisser: NSObject, UIGestureRecognizerDelegate {

    static let shared = TapOutsideKeyboardDismisser()

    /// 已经装过的 window（弱引用，window 没了自动移除）。
    private let patched = NSHashTable<UIWindow>.weakObjects()

    func install(on window: UIWindow) {
        guard !patched.contains(window) else { return }
        patched.add(window)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        // ★ 关键：不让手势吃掉这次触摸，输入框才能正常聚焦。
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        SoftKeyboard.hide()
    }

    // MARK: - 只对「点空白」生效

    /// ★ 点在有交互能力的东西上（输入框、按钮、开关、日期选择器…）时**不抢**，
    ///   否则会出现「点输入框的同时把键盘收掉」→ 根本聚焦不上，
    ///   或者「点快捷档位按钮时键盘一起收了」这类副作用。
    ///   只有点在真正的空白 / 静态文本上才收起键盘。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        var node = touch.view
        while let current = node {
            // UITextField / UIButton / UISwitch / UIDatePicker 全是 UIControl 的子类。
            if current is UIControl { return false }
            if current is UITextView { return false }
            // SwiftUI 的 TextField 有时包在私有容器里，按类型名兜一刀。
            if String(describing: type(of: current)).contains("TextField") { return false }
            node = current.superview
        }
        return true
    }
}

/// 把「点空白收起键盘」接到当前 window 上。放进任意 `.background()` 即可。
struct DismissKeyboardOnTap: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView {
        let view = WindowHookView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onWindow = { window in
            TapOutsideKeyboardDismisser.shared.install(on: window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// 一个零尺寸的探针视图，只为在「被挂进视图树」那一刻拿到 window。
private final class WindowHookView: UIView {
    var onWindow: ((UIWindow) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window { onWindow?(window) }
    }
}

// MARK: - 一行挂载

/// 带输入框的页面统一挂这个：滑动收起 + 点空白收起 + 键盘上方「完成」。
struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.immediately)
            .background(DismissKeyboardOnTap())
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { SoftKeyboard.hide() }
                }
            }
    }
}

extension View {
    /// 给模板页挂上完整的键盘收起交互。
    func keyboardDismissible() -> some View {
        modifier(KeyboardDismissModifier())
    }
}
