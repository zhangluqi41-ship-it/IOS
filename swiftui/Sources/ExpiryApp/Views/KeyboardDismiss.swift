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
//  ★★★ 2026-10-10（第十八轮·本次）用户两条反馈把问题指向了同一件事：
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
//         键盘 `.interactively` 的跟随动画 —— 于是滚动肉眼可见地一顿一顿。
//
//     二、更重要的是：它和系统的键盘拖拽/滚动识别链**并存**，
//         系统在 60fps 的滚动回调里还要额外调度我们这条第三方手势 →
//         识别器竞争本身就是开销。
//
//     ➜ 正解 = **删掉自研手势，回归纯粹的苹果第一方协议**。
//       `.scrollDismissesKeyboard(.immediately)` —— 这一句就是系统的
//       「滚动即收键盘」，输入完全交给 UIKit 的滚动识别器，
//       零 Swift 回调、零额外手势、零跨边界调用。
//
//     ★ 为什么用 `.immediately` 而不是 `.interactively`：
//       · `.interactively` 让键盘**逐帧跟随**手指 —— 这恰恰是最吃主线程的
//         模式（每一帧都要重排列表 + 重算键盘位置），正是卡顿的来源之一；
//       · `.immediately` 是**识别到滚动就一次性收起**，由系统一手包办，
//         没有逐帧跟随 → 顺滑，行为上也完全满足「滑动即隐藏」。
//       · 代价：第十五轮说的「不跟手」是 `.immediately` 的观感；
//         但本轮用户把「顺滑」排在了「跟手」前面（「存在明显卡顿」），
//         而且卡顿的根因就是逐帧跟随 + 自研手势，所以这里选顺滑。
//
//     ⚠️ 第十七轮那个「挂了 keyboard toolbar 时 `.scrollDismissesKeyboard`
//        会失效」的观察，在**本轮删掉 accessory bar 里的「打印」之后已不成立** ——
//        accessory bar 上只剩系统自带的「完成」，不再接管拖拽链路。
//        若日后真又失效，**不要**再写 UIPanGestureRecognizer 补丁，
//        优先查是不是 `.toolbar(placement: .keyboard)` 又挂了什么自定义控件。
//
//     ⚠️ 日历/日期面板曾经是「吃掉滚动」的另一支（`.compact` 的私有 popover）
//        —— 第十八轮已改用 `Menu + DatePicker(.graphical)`（见 `DateField.swift`），
//        菜单层由系统托管，不再参与本页手势。

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
/// ★ 为什么这个**保留**（而 `ScrollKeyboardDismisser` 被删掉）：
///   收键盘这件事 SwiftUI **没有**第一方 API（没有 `.dismissKeyboardOnTap()`），
///   所以只能用 UIKit 补一个手势 —— 这是**唯一**可行的做法。
///   它与滚动无关：`cancelsTouchesInView = false` 不吃触摸，
///   且 `shouldReceive` 遇到 `UIControl` 直接返回 false（点输入框/按钮不抢）。
///   ⚠️ 它只在**触摸开始**时被系统问一次「要不要接收」（`shouldReceive`），
///      在拖动过程中**不会**被逐帧回调 —— 所以它不是滚动卡顿的来源。
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

/// 带输入框的页面统一挂这个：滑动收起 + 点空白收起。
///
/// ⚠️ 键盘上方「完成」按钮**不在这里**，而是在 `LabelActions` 里统一挂。
struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            // ★★★ 2026-10-10（第十八轮）—— **苹果第一方**的「滚动即收键盘」。
            //
            //   `.immediately`：系统滚动识别器一判定是滚动，就一次性收起键盘。
            //   全程由 UIKit 自己处理 —— 没有逐帧 Swift 回调、没有额外手势、
            //   没有跨语言边界调用，所以滚动不再被拖累（第十七轮的卡顿就是这么来的）。
            //
            //   ⚠️ 不要再改回 `.interactively`（逐帧跟随 = 最吃主线程的模式），
            //      也不要再补 `UIPanGestureRecognizer`（第十七轮的
            //      `ScrollKeyboardDismisser` 已因此删除 —— 它就是卡顿的元凶）。
            .scrollDismissesKeyboard(.immediately)
            // 点空白收键盘：SwiftUI 无对应 API，只能由 UIKit 手势补（见上）。
            .background(DismissKeyboardOnTap())
    }
}

extension View {
    /// 给模板页挂上完整的键盘收起交互。
    func keyboardDismissible() -> some View {
        modifier(KeyboardDismissModifier())
    }
}
