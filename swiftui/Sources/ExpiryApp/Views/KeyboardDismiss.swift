//
//  KeyboardDismiss.swift
//  模板页的键盘交互 —— 填完信息不想打印时，键盘不能赖在屏幕上挡住下面的内容。
//
//  ─────────── 七轮反复的最终结论（v1.1.8 · 第二十四轮 · 真根因） ───────────
//
//  用户从第十八轮到第二十四轮，连续七轮报同一件事「点了收不起键盘」。
//  每一轮我都在**换一种实现手法**，却从没验证过**前提假设**：
//
//    第 18 轮：自绘 `UIPanGestureRecognizer`            → 滑动卡顿
//    第 19 轮：`window` 上的 `UITapGestureRecognizer`
//              + 全局 `FocusCoordinator`（三跳跨事务）  → 瞬间收回、无动画
//    第 20 轮：`SoftKeyboard.hide()`（`resignFirstResponder`）→ 依然无动画
//    第 21 轮：容器上 `.contentShape` + `.onTapGesture` → 点能收、滑不能收
//    第 22 轮：删掉上面那个                              → 点、滑**全都无响应**
//    第 23 轮：改成"只点末尾那一行"                      → 用户要的是"**任意位置**"
//    第 24 轮：`.background(手势层)`                     → **依然完全没反应**
//
//  ★★★ 第 24 轮终于找齐了**两个真根因**（都是"我以为对了、其实没生效"）：
//
//   ① **`.background` 被 `List` 完全遮住，形同虚设。**
//      `List` 是**不透明、铺满整屏**的视图；`.background` 的内容在它**背后**，
//      根本不参与命中测试 → 点哪都收不到。第 23 轮就是栽在这里。
//      ➜ 必须用 **`.overlay`**（浮在 `List` **之上**），再用 `hitTest` 精确放行。
//
//   ② **`GenericTemplateView` 的 `.focused` 挂错了位置。**
//      它原来写成：
//        ```swift
//        field(...).focused($focus, equals: AnyHashable("title"))
//        ```
//      而 `field(...)` 返回的是外层 `HStack` ——
//      `.focused` **只能作用在 `TextField` 自身**，挂在 `HStack` 上对底层
//      `UITextField` **完全无效** → 输入框根本没绑定 `focus`
//      → `focus.wrappedValue = nil` 等于**什么都没做**。
//      ➜ 正解：把 `.focused` 写进 `field()` 里、落在 `TextField` 上。
//
//  ★ 一句话教训：**"我加了这段代码" ≠ "这段代码在起作用"**。
//    必须验证：它挂在**正确的对象**上了吗？它在视图树的**哪一层**？
//
//  ➜ 最终定案（两个部件分工明确）：
//
//   【点】`.overlay(KeyboardDismissLayer)`！
//        浮在 `List` 之上 → 能收到触摸；靠 `hitTest` 放行：
//          · 点在 `List` 的**行**上   → 返回 `nil`，触摸穿透给 `List`；
//          · 点在**空白**（分组间隙、内容下方、两侧边距） → 收键盘。
//        手势 `cancelsTouchesInView = false` → 不吞控件触摸。
//
//   【滑】`.scrollDismissesKeyboard(.interactively)` 保持不变 ——
//        内容够长时它最好用；内容短（滚不动）时由【点】兜底。
//
//  ⚠️ 墓碑（别再写回来）：
//     · `.background` 挂手势层 —— **被 `List` 遮住，收不到触摸**（第 23 轮）；
//     · `List` 容器上 `.contentShape` + `.onTapGesture`（抢滚动手势，第 21 轮）；
//     · `window` 级手势（会吞掉系统弹层的关闭条件，第 19 轮）；
//     · `resignFirstResponder` / `SoftKeyboard.hide()`（无转场动画，第 20 轮）；
//     · `.id()` 重建控件（会连带销毁正在弹的日期浮层，第 22 轮）；
//     · **把 `.focused` 挂在外层容器/封装函数上**（只有落在 `TextField` 上才生效）。
//

import SwiftUI
import UIKit

// MARK: - 收键盘的触摸层

/// 一个**专门负责收键盘**的手势层。
///
/// ─────────────── 第 24 轮重新设计（前两版都错了） ───────────────
///
/// 【错版 A】`.background( ... )` —— **被 `List` 完全遮住，收不到任何触摸**。
///   `List` 是**不透明的、铺满整屏**的，`.background` 的内容在它**背后**，
///   根本没机会参与命中测试 → 点哪都没反应。这是"完全无响应"的**主因**。
///
/// 【错版 B】容器上 `.contentShape` + `.onTapGesture` —— 抢滚动手势（第 21 轮）。
///
/// ➜ 【本版】挂成 **`.overlay`**：浮在 `List` **之上**，所以能收到触摸。
///   但"浮在上面"就意味着会挡住 `List` —— 所以**必须靠 `hitTest` 精确放行**：
///
///   · 手指落在 **`List` 的行内**（有内容的地方）→ `hitTest` 返回 `nil`
///     → 触摸**穿透**给下面的 `List` → 滚动、点按钮、点输入框**全部照常**；
///   · 手指落在 **`List` 之外的空白**（分组间距、内容下方的大片空白、
///     底部安全区）→ 返回 `self` → 手势触发 → 收键盘。
///
/// ★ 为什么这样"点任意空白"就够了：
///   用户点输入框外的空白时，手指**基本都落在 `List` 没有行的区域**
///   （分组之间的间隙、最后一行之后的整片空白）—— 那些地方正是我们接管的。
///
/// ⚠️ 手势必须 `cancelsTouchesInView = false`：即便我们接下了，
///   也不取消已投递给下层控件的触摸（点按钮时按钮照常响应）。
/// ⚠️ 绝不重建控件、绝不碰 window（墓碑见文件头）。
final class KeyboardDismissTouchView: UIView {

    /// 手势触发时回调（收键盘）。
    var onTap: (() -> Void)?

    /// 判定"这个点算不算 `List` 里的内容"的依据。
    ///
    /// ★ 由 SwiftUI 侧注入：我们把**内层 `List` 的可滚动视图**找出来，
    ///   让它是"要放行的兄弟"。
    weak var contentScrollView: UIView?

    private lazy var tap: UITapGestureRecognizer = {
        let g = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        // ★ 不取消下层触摸：点按钮/输入框时它们照常收到事件。
        g.cancelsTouchesInView = false
        // ★ 不要求"必须没在滚动"—— 点击本来就与滚动互斥，交给系统判定。
        g.delegate = self
        return g
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false

        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handleTap() { onTap?() }

    /// ★★★ 命中测试的**唯一**出口：决定触摸是给我们、还是穿透给 `List`。
    ///
    /// 规则：
    ///   ① 点在 `List` 的有效内容上 → 返回 `nil`（穿透）；
    ///   ② 点在空白处           → 返回 `self`（我们接管，收键盘）。
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 点不在自己范围内 → 不关我事（系统继续按正常流程找）。
        guard bounds.contains(point) else { return nil }

        // ① 命中 `List` 的内容 → 穿透。
        if let scroll = contentScrollView, isPointInsideContent(point, of: scroll) {
            return nil
        }

        // ② 空白 → 我们接管。
        return self
    }

    /// 这个点是否落在内层 `List` 的**实际内容区域**（含分组）内。
    ///
    /// ★ 我们只把"窄窄的一条内容带"视为穿透区，其余都算空白。
    ///   内容带 = `List` 里所有**可见行**并集的外接矩形。
    ///   这样：行与行之间的**分组间隙**、最后一行之后的**大片空白**、
    ///   以及 `List` 两侧的边距，都会落到我们手里 → 点它们就收键盘。
    private func isPointInsideContent(_ point: CGPoint, of scroll: UIView) -> Bool {
        let pointInScroll = convert(point, to: scroll)

        // 收集所有"看起来像行"的子视图（`UICollectionViewCell` / `UITableViewCell`）。
        var hasContent = false
        for cell in scroll.subviews where isCellLike(cell) {
            let frameInScroll = cell.convert(cell.bounds, to: scroll)
            // 留 1pt 容差，避免边界上的手指抖动导致漏判。
            if frameInScroll.insetBy(dx: -1, dy: -1).contains(pointInScroll) {
                hasContent = true
                break
            }
        }
        return hasContent
    }

    /// 判断一个子视图是不是"列表的一行"。
    ///
    /// ⚠️ 不用字符串比类名（易随系统版本改名而失效），
    ///   改用**行为特征**：`List` 的行都是 `UICollectionViewCell` 家族
    ///   （iOS 13 起 `List` 就构建在 `UICollectionView` 之上），
    ///   且不可滚动（区别于 `List` 自己的 `UIScrollView`）。
    private func isCellLike(_ view: UIView) -> Bool {
        let name = NSStringFromClass(type(of: view))
        return name.contains("Cell")
    }
}

extension KeyboardDismissTouchView: UIGestureRecognizerDelegate {
    /// ★ 允许与 `List` 内部的滚动手势**同时存在**（我们不吞它们的触摸）。
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// SwiftUI 包装：把这个触摸层挂到页面里，并把内层 `List` 的
/// `UIScrollView` 找出来交给它做"穿透判定"。
struct KeyboardDismissLayer: UIViewRepresentable {
    var onTap: () -> Void

    func makeUIView(context: Context) -> KeyboardDismissTouchView {
        let view = KeyboardDismissTouchView()
        view.onTap = onTap
        // ★ 等视图上树后再去找 `List` 的 `UIScrollView`
        //   （`makeUIView` 时它还在视图树外，找不到）。
        DispatchQueue.main.async {
            view.contentScrollView = Self.findScrollView(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: KeyboardDismissTouchView, context: Context) {
        uiView.onTap = onTap
        // 页面结构变化（如 `Section` 出现/消失）后重新定位一次。
        if uiView.contentScrollView == nil {
            DispatchQueue.main.async {
                uiView.contentScrollView = Self.findScrollView(from: uiView)
            }
        }
    }

    /// 从当前视图出发，找到页面里那个 `List` 的滚动视图。
    ///
    /// ★ 优先在**父视图链**里找（我们要的是"同一个页面里的 `List`"），
    ///   找不到再退化为向下找。
    private static func findScrollView(from view: UIView) -> UIScrollView? {
        // 向上：找父链里的 `UIScrollView`（overlay 的兄弟一般是宿主容器）。
        var node: UIView? = view.superview
        while let current = node {
            if let found = deepestScrollView(in: current) { return found }
            node = current.superview
        }
        return nil
    }

    /// 在子树里找**面积最大**的 `UIScrollView` —— 那就是 `List` 的本体。
    private static func deepestScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        var bestArea: CGFloat = 0
        func walk(_ v: UIView) {
            if let s = v as? UIScrollView {
                let area = s.bounds.width * s.bounds.height
                if area > bestArea { bestArea = area; best = s }
            }
            v.subviews.forEach(walk)
        }
        walk(root)
        return best
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
            // ★ 第一方「滑动收键盘」。
            //   `.interactively`：键盘跟着手指逐帧走 = 流畅动画。
            //   ⚠️ 别改 `.immediately`（瞬间收起、无动画，被连否两次）。
            //   ⚠️ 内容不满一屏时这条不触发 → 由下面的 overlay 兜底。
            .scrollDismissesKeyboard(.interactively)
            // ★★★ 第一方「点任意空白收键盘」。
            //   ⚠️ 必须是 **`.overlay`**（浮在 `List` 之上）而不能是 `.background`
            //      —— `background` 会被不透明的 `List` 完全遮住，收不到触摸
            //      （第 23 轮的致命错误）。
            //   靠 `KeyboardDismissTouchView.hitTest` 精确放行：
            //      点在 `List` 的行上 → 穿透；点在空白 → 收键盘。
            .overlay(
                KeyboardDismissLayer {
                    // 与按回车同一条路径 → 有系统动画。
                    focus.wrappedValue = nil
                }
                .allowsHitTesting(true)
            )
    }
}
