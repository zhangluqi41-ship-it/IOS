//
//  KeyboardDismiss.swift
//  模板页的键盘交互 —— 填完信息不想打印时，键盘不能赖在屏幕上挡住下面的内容。
//
//  提供三种收起方式（用户要求「点屏幕或滑动屏幕自动隐藏键盘」）：
//    ① 滑动列表     → `.scrollDismissesKeyboard(.interactively)`
//    ② 点屏幕任意处 → 挂在 **window** 上的 UITapGestureRecognizer
//    ③ 键盘上方「完成」按钮（第一方 ToolbarItemGroup(placement: .keyboard)，
//       由 `LabelActions` 统一挂，和「打印」并排 —— 见下面「2026-10-09 改动」）
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
//  ★★ 2026-10-09 改动（用户反馈「动画生硬」+「完成和打印两个按钮重叠」）：
//     1. `.immediately` → `.interactively`。
//        `.immediately` 是「手指一动就把键盘整块抽走」，观感就是很生硬的
//        一记闪跳；`.interactively` 让键盘**跟着手指走**，拖到哪收到哪，
//        这才是 iOS 系统键盘该有的手感。
//     2. 键盘弹起时，底部那条「打印」操作条**就地淡出并收起**，
//        同时把「打印」搬到键盘上方的第一方 accessory bar 里，
//        和「完成」并排 —— 两个按钮从此不可能再重叠。
//        键盘隐藏的时长从 `keyboardAnimationDurationUserInfoKey` 读出来，
//        用它驱动动画，操作条才会和键盘同步起落，不会各走各的。
//

import Combine
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

// MARK: - 键盘可见性

/// 全局键盘可见性。
///
/// ★ 用系统的 `keyboardWillShow/Hide` 通知（第一方 API）而不是自己猜，
///   顺带把键盘自己的动画时长读出来 —— 底部操作条要和键盘**同一条时间线**
///   起落，否则看起来就是「按钮自己乱动」（用户说的「动画生硬」）。
///
/// 做成单例：所有模板页共享同一份状态，不需要各自注册一遍观察者。
final class KeyboardWatcher: ObservableObject {

    static let shared = KeyboardWatcher()

    /// 键盘当前是否可见。
    @Published private(set) var isVisible = false
    /// 键盘这次动画的时长（秒），用于让我们的动画与其对齐。
    @Published private(set) var duration: Double = 0.25

    private init() {
        let center = NotificationCenter.default
        // 闭包捕获 self 用 weak，观察者活到进程结束（单例），无需移除。
        center.addObserver(forName: UIResponder.keyboardWillShowNotification,
                           object: nil, queue: .main) { [weak self] note in
            self?.apply(note, visible: true)
        }
        center.addObserver(forName: UIResponder.keyboardWillHideNotification,
                           object: nil, queue: .main) { [weak self] note in
            self?.apply(note, visible: false)
        }
    }

    private func apply(_ note: Notification, visible: Bool) {
        let raw = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        duration = raw ?? 0.25
        guard isVisible != visible else { return }
        // 动画包在这里，底部操作条的收起/展开就与键盘同步。
        withAnimation(.easeInOut(duration: duration)) {
            isVisible = visible
        }
    }
}

// MARK: - 滑动收起键盘

/// 「往下拖列表收起键盘」的兜底手势。
///
/// ★★ 2026-10-09（第三轮）为什么必须自己做一个 —— 用户反馈：
///    「之前有确认，在输入名称等呼出系统键盘后，在屏幕其他位置点击或滑动，
///      收回键盘。目前只保留点击收回，没有滑动收回功能」
///
///    根因：`LabelActions` 在**同一个 List** 上挂了
///    `.toolbar { ToolbarItemGroup(placement: .keyboard) }`（键盘上方那条
///    「完成 / 打印」accessory bar）。这条 accessory bar 会接管/打断
///    `.scrollDismissesKeyboard(.interactively)` 依赖的那套拖拽识别链路 ——
///    1.0.1 之前没有这条 toolbar 时滑动是好的，加了之后滑动就失效了。
///
///    SwiftUI 没有提供「在同一视图上同时保留 keyboard accessory 与
///    scroll-dismiss」的开关，所以这里直接用 UIKit 补一个**独立的**
///    `UIPanGestureRecognizer`：它只观察、不拦截（`cancelsTouchesInView = false`），
///    一旦识别到「手指主要向下拖动」，就收起键盘。
///    ➜ 与 `.scrollDismissesKeyboard` 是「叠加」而非「二选一」，
///      两者谁生效都能达到目的，也不影响列表本身的滚动。
final class SwipeDownKeyboardDismisser: NSObject, UIGestureRecognizerDelegate {

    static let shared = SwipeDownKeyboardDismisser()

    private let patched = NSHashTable<UIWindow>.weakObjects()

    func install(on window: UIWindow) {
        guard !patched.contains(window) else { return }
        patched.add(window)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        // ★ 关键：不吃掉这次手势，列表照常滚动、输入框照常拖动光标。
        pan.cancelsTouchesInView = false
        // 键盘收起由 `.interactively` 或这里任一触发即可，不必抢优先级。
        pan.delegate = self
        window.addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended || gesture.state == .changed else { return }
        let translation = gesture.translation(in: gesture.view)
        let velocity = gesture.velocity(in: gesture.view)
        // 判据：「向下」的位移或速度占绝对主导，才认为是「往下拖收键盘」。
        // 横向滑动（比如滑动删行）、轻微斜拖不触发，避免误伤。
        let downward = translation.y > 40 || velocity.y > 600
        let dominant = abs(translation.y) > abs(translation.x)
        guard downward, dominant else { return }
        SoftKeyboard.hide()
    }

    // MARK: - 不干预交互

    /// ★ 允许与其它手势（列表滚动、行内按钮）同时识别。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
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
            // ★ 2026-10-09 第三轮：滑动收键盘的兜底手势。
            SwipeDownKeyboardDismisser.shared.install(on: window)
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

/// 带输入框的页面统一挂这个：滑动收起 + 点空白收起。
///
/// ⚠️ 键盘上方「完成」与「打印」两个按钮**不在这里**，而是在
///   `LabelActions` 里统一挂 —— 那里才有 `printNow`。
///   两处各挂一个 `.toolbar(placement: .keyboard)` 虽然也能编译，
///   但会变成两条独立 accessory bar，反而更容易出怪相。
struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            // ★ 跟着手指走，而不是整块闪走 —— 见文件头 2026-10-09 说明。
            //
            // ⚠️ 2026-10-09 第三轮：单靠这一句在**挂了 keyboard toolbar 的页面**
            //    上会失效（见 `SwipeDownKeyboardDismisser` 的说明）。
            //    所以保留它作为「正常情况下的第一选择」，同时由
            //    `DismissKeyboardOnTap` 装的那个 pan 手势兜底 ——
            //    两者叠加，任一可用即可，不冲突。
            .scrollDismissesKeyboard(.interactively)
            .background(DismissKeyboardOnTap())
    }
}

extension View {
    /// 给模板页挂上完整的键盘收起交互。
    func keyboardDismissible() -> some View {
        modifier(KeyboardDismissModifier())
    }
}
