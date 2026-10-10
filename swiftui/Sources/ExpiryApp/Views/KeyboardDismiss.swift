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
//  ★★★ 2026-10-10 第七轮（第十七轮）修正**滚动收键盘**的方向判定 —— 用户反馈：
//     「点击或滚动输入框以外任意位置都应隐藏键盘，目前**滚动无法隐藏键盘**」
//
//     根因：兜底手势 `SwipeDownKeyboardDismisser` 的名字与实现都只认
//     「**向下**」主导的拖动（`translation.y > 40`）—— 用户**向上滚动**列表时
//     完全不触发；再加上 `.scrollDismissesKeyboard(.interactively)` 在挂了
//     keyboard toolbar 的页面上本就失效 → 表现为「怎么滚都收不起键盘」。
//
//     ➜ 更名 `ScrollKeyboardDismisser`，判定放宽为「**任意方向**的垂直滚动」
//       都收起键盘（仅排除纯横向滑动，避免误伤滑动删行）。
//
//  ★★★ 2026-10-10（第十八轮）用户两条反馈把问题指向了同一件事：
//     「滑动收回时**存在明显卡顿**，是否存在**未使用苹果第一方协议**？」
//     「日历选择页面收回后完全不影响画面滚动，继续质疑是否正常使用第一方协议？」
//
//     ★ 用户的直觉是对的，而且这正是卡顿的**真正根因**：
//
//     一、`ScrollKeyboardDismisser` 是**我们自己写的 UIPanGestureRecognizer**，
//         装在整个 window 上。它在 `.changed` 阶段**每一次触摸移动**都会：
//           ① 回调进 Swift（跨语言边界）；
//           ② 读两遍 `translation(in:)` + `velocity(in:)`（每次都做一次
//              坐标系换算，UIKit 内部还要回溯手势状态）；
//           ③ 命中阈值就跨进程发一次 `resignFirstResponder`。
//         这些活儿全都跑在**主线程**上，而主线程此刻正忙着驱动滚动 +
//         键盘的跟随动画 —— 于是滚动肉眼可见地一顿一顿。
//
//     二、更重要的是：它和系统的键盘拖拽/滚动识别链**并存**，
//         系统在 60fps 的滚动回调里还要额外调度我们这条第三方手势 →
//         识别器竞争本身就是开销。
//
//     ➜ 正解 = **删掉自研手势，回归纯粹的苹果第一方协议**
//       `.scrollDismissesKeyboard(...)`，输入完全交给 UIKit 的滚动识别器，
//       零 Swift 回调、零额外手势、零跨边界调用。
//
//  ★★★ 2026-10-10（第十九轮·本次）用户再报两条，逼出最终答案：
//     「收回键盘是**瞬间收回，并无流畅动画**」
//     「『完成』按钮也不需要，逻辑上是点击或滑动屏幕任意位置，流畅收起键盘」
//
//     ★ 这两条合起来说明：**上一轮选 `.immediately` 是错的**。
//       `.immediately` 的语义就是「滚动一开始就**立刻**收起键盘」
//       —— 字面上就是**瞬间、无动画**，正是用户看到的观感。
//
//     ➜ 最终定案 = **`.interactively`**：
//       键盘**跟着手指逐帧走**，拖到哪收到哪 —— 这就是「流畅动画」本身。
//       ⚠️ 第十八轮曾以「`.interactively` 逐帧跟随最吃主线程」为由放弃它，
//          但那次卡顿的**真凶是自研 pan 手势**（已被删除），不是 `.interactively`。
//          现在手势没了，`.interactively` 只剩系统自己一条链路 → 不再卡。
//
//     ⚠️ 别再改回 `.immediately`：它 = 瞬间消失、无动画（用户明确否定）。
//     ⚠️ 也别再写 `UIPanGestureRecognizer`：自研手势会被系统识别器「二选一」，
//        反而让 `.interactively` 失效，还可能吞掉 `DatePicker` 的点击
//        （本轮那个「日期点不开」的重大 bug 就有它一份）。

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

// MARK: - 第一方聚焦：让键盘收起带上系统动画

/// 全局「当前聚焦的输入框」。
///
/// ★★★ 2026-10-10（第十九轮）为什么必须有它 —— 用户连续三轮反馈同一件事：
///     「收回键盘是**瞬间收回，并无流畅动画**，我依然质疑你是不是没有用第一方工具或协议」
///
///     ★ 用户的质疑**是对的**，而且根因就在本文件里：
///
///     之前收键盘走的是 `UIApplication.shared.sendAction(#selector(
///     UIResponder.resignFirstResponder), …)` —— 这是**命令式的 UIKit 收键盘**，
///     它只是让第一响应者 resign，**不带任何 SwiftUI 的转场上下文**。
///     iOS 26 的键盘收起动画由 SwiftUI 的 focus 系统驱动
///     （`@FocusState` / `focused(_:)` 是它的第一方入口），
///     绕过它 → 键盘直接「啪」地消失，也就是用户看到的「瞬间收回、没有动画」。
///
///     ➜ 正解 = **把焦点交回 SwiftUI**：全局只认一个「当前聚焦的输入框」，
///       任何要收键盘的动作（点空白 / 滚动 / 点日期）都走 `focused = nil`，
///       由 SwiftUI 自己把键盘**动画**收起。
///
///     ⚠️ `SoftKeyboard.hide()`（UIKit 的 resignFirstResponder）**不要再用来收键盘** ——
///        那正是「瞬间收回、没动画」的来源。它现在只留作最后兜底
///        （见 `dismiss()`：万一焦点状态没跟上，至少保证键盘能被收掉）。
///
/// ★ 焦点值由 `keyboardDismissible(focus:)`（`KeyboardFocus.swift`）持续同步进来。
@MainActor
final class FocusCoordinator: ObservableObject {

    static let shared = FocusCoordinator()

    /// 当前聚焦的输入框标识；`nil` = 没有聚焦（键盘应收起）。
    @Published var focused: AnyHashable?

    private init() {}

    /// 第一方收键盘：清空焦点 → SwiftUI 播系统动画收起键盘。
    ///
    /// ★ 正常路径就是「把 `focused` 置 nil」——`keyboardDismissible(focus:)`
    ///   的 `onChange` 会把 nil 写回页面的 `@FocusState`，SwiftUI 随即动画收键盘。
    ///   只有焦点状态确实没跟上的极端情况，才退到 UIKit 兜底，
    ///   保证「点空白一定能把键盘收掉」这件事不会失效。
    func dismiss() {
        focused = nil
        if Self.hasFirstResponder {
            // 走到这里说明 SwiftUI 侧没跟着收（例如某页漏了绑定）→ 兜底。
            SoftKeyboard.hide()
        }
    }

    /// 系统里是否真的有第一响应者在编辑（说明键盘该收而未收）。
    private static var hasFirstResponder: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.firstResponderIsEditing }
    }
}

private extension UIWindow {
    /// 沿 responder chain 找一找有没有正在编辑的第一响应者。
    var firstResponderIsEditing: Bool {
        func find(_ responder: UIResponder?) -> Bool {
            guard let responder else { return false }
            if responder is UITextField || responder is UITextView { return true }
            return find(responder.next)
        }
        return find(self)
    }
}

// MARK: - 键盘可见性

/// 全局键盘可见性。
///
/// ★ 用系统的 `keyboardWillShow/Hide` 通知（第一方 API）而不是自己猜，
///   顺带把键盘自己的动画时长读出来。
///
/// ⚠️ 2026-10-10（第十八轮）：`LabelActions` 已经**不再**根据这个状态
///   隐藏底部操作条（改成让「打印」一直存在、自然跟随键盘上移），
///   所以目前**没有读者**。保留它是为了：将来若又要「键盘抬起时换一条 bar」，
///   现成的第一方通知订阅不该再手写一遍；同时 `isVisible` 也是排查键盘问题的
///   唯一观测点。**别因为"没人用"就删掉。**
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
        // 动画包在这里，订阅方的收起/展开就与键盘同步。
        withAnimation(.easeInOut(duration: duration)) {
            isVisible = visible
        }
    }
}

// MARK: - 点空白收起键盘

/// 「点空白收起键盘」的安装器。
///
/// ★ 为什么这个**必须保留**（不能用纯 SwiftUI 替代）：
///   收键盘这件事**没有**第一方 SwiftUI 修饰符（不存在 `.dismissKeyboardOnTap()`）。
///   `.onTapGesture` 挂在 `List` 上会与 `TextField` **抢手势**
///   （轻则点输入框键盘闪一下打不出字）—— 这是第十五轮实测过的坑，
///   所以只能用 UIKit 补一个**只观察、不拦截**的手势。
///
/// ★★★ 2026-10-10（第十九轮）关键修正：手势本身没问题，**问题在它调用了什么**。
///   以前它直接调 UIKit 的 `resignFirstResponder` → 键盘**瞬间消失、没有动画**
///   （用户连续三轮反馈的同一个问题：「收回键盘是瞬间收回，并无流畅动画」）。
///   ➜ 现在改走 `FocusCoordinator.dismiss()` —— **第一方 `@FocusState` 收键盘**，
///     由 SwiftUI 播系统动画。
///
/// ⚠️ 这个手势只挂在 window 上、`cancelsTouchesInView = false`，
///    在**触摸开始**时被系统问一次 `shouldReceive`，拖动过程中**不会**被逐帧回调，
///    所以它**不是**滚动卡顿的来源（第十八轮删掉的是另一个 pan 手势）。
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
        // ★ 走第一方焦点，键盘才会「流畅收起」而不是瞬间消失。
        FocusCoordinator.shared.dismiss()
    }

    // MARK: - 只对「点空白」生效

    /// ★ 点在有交互能力的东西上（输入框、按钮、开关、日期选择器…）时**不抢**，
    ///   否则会出现「点输入框的同时把键盘收掉」→ 根本聚焦不上，
    ///   或者「点快捷档位按钮时键盘一起收了」这类副作用。
    ///   只有点在真正的空白 / 静态文本上才收起键盘。
    ///
    /// ★ 这段**必须保留** —— 它同时是「日期选择器点得开」的保险
    ///   （历史教训：window 级手势会把 `DatePicker` 的点击吞掉）。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        var node = touch.view
        while let current = node {
            // UITextField / UIButton / UISwitch / UIDatePicker / UIKit 菜单宿主
            // 全是 UIControl 的子类 —— 交给它们自己处理，我们不收键盘。
            if current is UIControl { return false }
            if current is UITextView { return false }
            // SwiftUI 的 TextField / DatePicker 有时包在私有容器里，按类型名兜一刀。
            let name = String(describing: type(of: current))
            if name.contains("TextField") || name.contains("DatePicker") { return false }
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

/// 带输入框的页面统一挂这个：滑动收起 + 点空白收起。
///
/// ⚠️ 键盘上方**不挂任何东西**（`ToolbarItemGroup(placement: .keyboard)`
///   在第十九轮被彻底移除，见 `LabelActions`）。
struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            // ★★★ 苹果第一方的「滑动收键盘」。
            //
            //   `.interactively`：键盘**跟着手指逐帧走**，拖到哪收到哪 ——
            //   这就是用户要的「流畅动画」（`.immediately` 是瞬间消失，已被否定）。
            //
            //   ⚠️ 2026-10-10（第十九轮）定案：`.immediately` ✗ / `.interactively` ✓。
            //      第十八轮误以为「逐帧跟随吃主线程」，其实那次卡顿的真凶是
            //      自研 `UIPanGestureRecognizer`（已删除）。
            //   ⚠️ 别再补 `UIPanGestureRecognizer` —— 它会与这条系统识别器
            //      「二选一」，既可能让本句失效，又会吞掉 `DatePicker` 的点击。
            .scrollDismissesKeyboard(.interactively)
            // 点空白收键盘：SwiftUI 无对应 API，只能由 UIKit 手势补（见上）。
            .background(DismissKeyboardOnTap())
    }
}

// ⚠️ 带 `focus:` 的 `keyboardDismissible(...)` 在 `KeyboardFocus.swift`。
//    那个版本会把焦点同步给 `FocusCoordinator`，从而让「点空白 / 滚动」
//    都能走**第一方 `@FocusState`** 收键盘（有系统动画）。
//    **所有七个模板页都用带 focus 的版本** —— 本文件不再提供无参版本，
//    免得有人误用回「瞬间收起、没动画」的老路。
