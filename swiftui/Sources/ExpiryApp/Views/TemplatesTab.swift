//
//  TemplatesTab.swift
//  模板 Tab —— 四个模板卡片（通用效期 / 康普茶 / 奶制品 / 肉类）+ 使用流程说明。
//
//  ★ 导航采用 value-based（`NavigationLink(value:)` + `navigationDestination(for:)`），
//    因为只有 value-based 跳转才会写进父级传入的 NavigationPath；
//    首页切走 Tab 时要靠清空这个 path 回到一级菜单，destination-based 的
//    NavigationLink 不会写 path，重置会失效。
//

import SwiftUI
// `.onDrag` / `.onDrop(of: [.text], delegate:)` 需要 UTType.text
import UniformTypeIdentifiers

/// 模板二级页路由。
enum TemplateRoute: Hashable, CaseIterable {
    case generic
    case kombucha
    case dairy
    case meat

    /// 持久化用的稳定 key（拖动排序要存进 UserDefaults）。
    var key: String {
        switch self {
        case .generic: return "generic"
        case .kombucha: return "kombucha"
        case .dairy: return "dairy"
        case .meat: return "meat"
        }
    }

    static func from(key: String) -> TemplateRoute? {
        allCases.first { $0.key == key }
    }

    var title: String {
        switch self {
        case .generic: return "通用效期"
        case .kombucha: return "康普茶"
        case .dairy: return "奶制品"
        case .meat: return "肉类"
        }
    }

    var subtitle: String {
        switch self {
        case .generic: return "自定标题与两个日期"
        case .kombucha: return "自动算一发二发日期"
        case .dairy: return "按品类套保质期"
        case .meat: return "冷藏 / 冷冻自动算"
        }
    }

    var systemImage: String {
        switch self {
        case .generic: return "clock"
        case .kombucha: return "drop.fill"
        case .dairy: return "flask.fill"
        case .meat: return "fork.knife"
        }
    }

    var tint: Color {
        switch self {
        case .generic: return Theme.tplGenericTint
        case .kombucha: return Theme.tplKombuchaTint
        case .dairy: return Theme.tplDairyTint
        case .meat: return Theme.tplMeatTint
        }
    }

    var fill: Color {
        switch self {
        case .generic: return Theme.tplGenericFill
        case .kombucha: return Theme.tplKombuchaFill
        case .dairy: return Theme.tplDairyFill
        case .meat: return Theme.tplMeatFill
        }
    }
}

struct TemplatesTab: View {
    @Binding var path: NavigationPath

    /// 磁贴顺序 —— 拖动排序后写进 `Prefs.templateOrder`，下次启动保持。
    @State private var order: [TemplateRoute] = TemplatesTab.loadOrder()
    /// ★★★ 2026-10-18（用户报 bug）：固定/取消固定后**界面不立即刷新**。
    ///   根因：`isPinned` 原来直接读 `Prefs.pinnedTemplates`（UserDefaults）——
    ///   它**不是 SwiftUI 的响应式状态**。只有 `order` 变了才会重绘；
    ///   而"固定的磁贴本来就在第一位"时 `order` 不变 → 不重绘 → 图钉图标不更新。
    ///   ➜ 用 `@State` 镜像一份，任何固定操作都改它（必定触发重绘），再同步进 Prefs。
    @State private var pinnedKeys: [String] = Prefs.pinnedTemplates
    /// 同理：删除的磁贴也要响应式（toolbar 的「恢复全部」按钮靠它决定显示与否）。
    @State private var hiddenKeys: [String] = Prefs.hiddenTemplates
    // MARK: 拖动（★ 2026-10-19 回到系统第一方拖放）

    // ★ 之前"不跟手"的真因**不是** API 不行，而是我把**整张卡片**（GroupBox +
    //   NavigationLink + 材质背景）当成了拖动预览，每帧重渲染 → 卡顿。
    //   现在 `.onDrag` 的 preview 换成**轻量视图**（纯色圆角 + 图标 + 标题），
    //   拖动跟手就正常了 —— 和健康 App 那种"浮起跟手"一致。
    //   落点用 `.onDrop(delegate:)`（**不是** `.dropDestination`）：后者会画系统「+」角标。

    /// 正在拖的磁贴。
    @State private var dragging: TemplateRoute?
    /// ★ 2026-10-19（用户）：「按住后（进入排序模式）并没有放大，**只有拖拽走后才放大**，
    ///   应该是**按住后只要开始能够移动就放大**」
    ///   ➜ 原来是靠 `dragging`（要移动 6pt 才置位）驱动放大，所以"按下去"那一刻没反应。
    ///   ➜ 新增 `pressedRoute`：**手指一按下就置位**（`DragGesture(minimumDistance: 0)`），
    ///     放大/抬起视觉由 `dragging || pressed` 共同驱动。
    @State private var pressedRoute: TemplateRoute?
    /// 手指相对起点的位移 —— 直接当 offset 用（1:1 跟手）。
    @State private var dragOffset: CGSize = .zero
    /// 每张磁贴在网格坐标空间里的位置（用来算手指落在谁头上）。
    ///
    /// ★★★ 2026-10-19（用户）：「在拖动的过程中，**时间越久，掉帧越严重**」
    ///   根因：原来是 `@State var tileFrames: [TemplateRoute: CGRect]`（**值类型**）。
    ///   拖动 → 目标让位/布局微变 → `onPreferenceChange` 写入 tileFrames →
    ///   **@State 变化触发整个 body 重绘** → 再布局 → preference 又变 → ……
    ///   每帧都在自增一轮，所以越拖越卡。
    ///   ➜ 改成 **引用类型**（class）存放：改它的属性**不会**触发 SwiftUI 重绘，
    ///     只作为"查询表"用，彻底断掉这个循环。
    @State private var frameStore = TileFrameStore()
    /// 手指当前落在哪个磁贴上（让位提示）。
    @State private var dropTarget: TemplateRoute?
    /// 刚放下的那张 —— 重排时它不加过渡动画（松手就落在新格）。
    @State private var justDropped: TemplateRoute?

    /// 读保存的顺序：**跳过已删除的**，并补上新增的路由。
    private static func loadOrder() -> [TemplateRoute] {
        let hidden = Set(Prefs.hiddenTemplates)
        let saved = Prefs.templateOrder
            .compactMap { TemplateRoute.from(key: $0) }
            .filter { !hidden.contains($0.key) }
        let missing = TemplateRoute.allCases
            .filter { !saved.contains($0) && !hidden.contains($0.key) }
        let base = saved + missing
        // ★ 固定的排最前，按**固定先后**（用户：「每个都可以固定，按固定顺序排先后」）。
        let pinned = Prefs.pinnedTemplates
            .compactMap { TemplateRoute.from(key: $0) }
            .filter { base.contains($0) }
        return pinned + base.filter { !pinned.contains($0) }
    }

    // MARK: 磁贴（拖动 + 长按菜单 + 固定）

    /// 单张磁贴：卡片 + 右上角「固定」快捷键 + **整张磁贴跟手拖动**。
    ///
    /// ★★★ 2026-10-19（用户两次订正后的结论）：
    ///   · 「移动的时候截图出来个这玩意是啥？」（那个巨大的 "kombucha"）
    ///     → 那是 `.onDrag` 的**系统 fallback**：当 preview 渲染异常时，
    ///       系统会拿 `NSItemProvider` 里的**字符串内容**当拖拽预览，于是显示成一串大字。
    ///   · 「移动的不是磁贴是个缩略图，**应该是磁贴跟我走**」
    ///     → `.onDrag` 的 preview **必然是系统生成的快照**，做不到"整张磁贴跟手"。
    ///   ➜ 结论：**只能用 `DragGesture` + `offset`**（唯一能让视图本体跟手的方案）。
    ///
    /// ★ 上次用 DragGesture「不跟手」的真因（已修）：
    ///   我把 `.animation(_:value: isDragging)` 放在了 `.offset` **之后** ——
    ///   于是 `isDragging` 翻转那一帧，`offset` 被从 0 动画到当前位移（0.18s 滑过去），
    ///   看起来就是"慢半拍"。现在 **`.offset` 放在 `.animation` 之后**，位移永不被动画化。
    private func tile(_ route: TemplateRoute) -> some View {
        let isDragging = dragging == route
        // 抬起态：**手指按下就算**（不用等移动 6pt），拖动中当然也算。
        let isLifted = isDragging || pressedRoute == route
        return tileCore(route)
            // ★★★ 2026-10-19（用户）：「**正在被我拖动的变半透明**，
            //   你把没被我拖动的、准备让位的那个变成半透明了」
            //   ➜ 半透明只加在**被拖的那张**身上（iOS 标准：拿起来的东西是半透明的）。
            .opacity(isDragging ? 0.85 : 1)
            .scaleEffect(isLifted ? 1.06 : 1)
            .shadow(color: .black.opacity(isLifted ? 0.25 : 0),
                    radius: isLifted ? 14 : 0, y: isLifted ? 8 : 0)
            // ⚠️ 这个 animation **只能**作用在它前面（scale/shadow）。
            // ★ 用户：「整个磁贴能否使用**苹果官方系统默认动画**」
            //   ➜ `.default` 就是系统默认曲线 + 时长，不再用我自定义的 `.snappy`。
            .animation(.default, value: isLifted)
            // ★ offset 在 animation 之后 → 拖动中位移变化不带过渡 = 1:1 跟手。
            .offset(isDragging ? dragOffset : .zero)
            // ★★★ 2026-10-19（用户）：「图标移动的时候，现在是**瞬间移动**，
            //   能不能改的自然、线性一些？」
            //   ➜ 拖动中（isDragging = true）→ animation 为 nil（跟手零延迟）；
            //     松手后（isDragging = false）→ 用 `.easeOut(0.22)` 让 offset 从
            //     **手指落点**平滑归零，于是磁贴是「从松手位置滑到新格」，
            //     而不是"啪"地闪现。
            //   ⚠️ 重排那一步仍是**瞬间**的（`justDropped` 让这张不带 order 动画），
            //     所以不会出现"从老位置滑过去"。
            .animation(isDragging ? nil : .default, value: dragOffset)
            // ★★★ 2026-10-19（用户）：「替换的时候图层应该是**我手上的磁贴在最上图层**，
            //   被迫移动的图标在下图层；现在我松手后，被迫移动的图标跑到上图层了」
            //   根因：`zIndex` 只在 `isDragging` 时为 1，松手立刻归 0 →
            //   重排后它会和"被挤开的那张"同层，而 SwiftUI 的绘制顺序 = ForEach 声明顺序，
            //   排到后面的兄弟会盖住它。
            //   ➜ 松手后用 `justDropped` 再维持 **0.45 秒**的上层（紧接着的动画期），
            //     动画结束自动回落到普通层。
            .zIndex(isDragging ? 2 : (justDropped == route ? 1 : 0))
            // ★★★ 2026-10-19（用户 bug）：「按住完全不能拖动，松手后会移动」
            //   根因：磁贴内部是 `NavigationLink`（点击进模板页），它的**内层点击手势
            //   优先级高于**外层的 `.gesture` → 拖动被它吃掉，一松手就当成"点击"跳页了。
            //   ➜ 换成 **`.highPriorityGesture`**：拖动优先识别；
            //     `minimumDistance: 6` 保证「没移动」时它直接失败、把点击还给 NavigationLink。
            .highPriorityGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named("tileGrid"))
                    .onChanged { value in
                        if dragging != route {
                            // ⚠️ 不要 withAnimation：否则 offset 会从 0 滑到当前位置。
                            dragging = route
                        }
                        dragOffset = value.translation
                        let hit = frameStore.frames.first {
                            $0.key != route && $0.value.contains(value.location)
                        }?.key
                        // ★ 不加 withAnimation：拖动中每次变化都开一个动画事务会堆叠、加剧掉帧。
                        //   目标只是轻微上移 4pt，直接改值即可。
                        if hit != dropTarget { dropTarget = hit }
                    }
                    .onEnded { _ in
                        finishDrag(from: route)
                    }
            )
            // ★ 手指一按下就进入"抬起"视觉（放大 + 投影）；松手复原。
            //   用 `simultaneousGesture` 同时识别：不抢点击（进模板页）、也不抢拖动。
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("tileGrid"))
                    .onChanged { _ in
                        if pressedRoute != route { pressedRoute = route }
                    }
                    .onEnded { _ in
                        pressedRoute = nil
                    }
            )
    }

    /// 松手：换位 + 清所有拖动状态。
    ///
    /// ★ 先复位状态、再重排（上次的 bug：先重排会带着"透明/变淡"渲染，看起来像消失）；
    ///   换位不成功（同位置）则什么都不做 —— 磁贴自动回到原位。
    private func finishDrag(from route: TemplateRoute) {
        let target = dropTarget
        justDropped = route

        // ① 先结束拖动（isDragging = false）—— 让下一行 dragOffset 的变化走 `.easeOut` 过渡。
        withAnimation(.default) {
            dragging = nil
            dropTarget = nil
        }
        // ② offset 归零：因为上面 isDragging 已为 false，这一步会从**手指落点**平滑滑到新格。
        dragOffset = .zero

        if let target,
           let fromIndex = order.firstIndex(of: route),
           let toIndex = order.firstIndex(of: target),
           fromIndex != toIndex {
            withAnimation(.default) {
                let moved = order.remove(at: fromIndex)
                order.insert(moved, at: toIndex)
            }
            Prefs.templateOrder = order.map(\.key)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            justDropped = nil
        }
    }

    /// 磁贴本体：卡片 + 右上角「固定」快捷键。
    ///
    /// ⚠️ 2026-10-19 补回：清理 `finishDrag` 时误删了这段（导致 `cannot find 'tileCore'` 编译失败）。
    private func tileCore(_ route: TemplateRoute) -> some View {
        let isTarget = dropTarget == route
        let pinned = isPinned(route)
        return ZStack(alignment: .topTrailing) {
            card(for: route)
                // ★ 2026-10-19（用户）：目标**不要变半透明**（半透明只属于被拖的那张），
                //   这里只保留一点点上移，作为"它要让位了"的提示。
                .offset(y: isTarget ? -4 : 0)
                .animation(.default, value: isTarget)
                // 重排时：刚放下的那张不带动画（直接落到新格），其余走系统默认动画。
                .animation(justDropped == route ? nil : .default, value: order)

            // 右上角「固定」快捷键：**点一下直接切换**（不弹任何菜单）。
            //
            // ★ 2026-10-19（用户）：「固定增加**圆形外框**，里面做**对比色区分**，
            //   整个圆形都是按键范围」
            //   ➜ 圆形底：固定 = 品牌蓝实心 + 白图标；未固定 = 浅灰实心 + 灰图标。
            //   ➜ 点击范围 = **整个 28pt 圆**（`contentShape(Circle())` 加在带背景的容器上）。
            Button {
                togglePin(route)
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(pinned ? Color.white : Color.secondary)
                    .frame(width: 28, height: 28)
                    // ★ 2026-10-19（用户）：「**不要外面的描边，只要按钮背景色**」
                    //   ➜ 去掉 `strokeBorder` 那一圈，只留实心圆形底。
                    .background(
                        Circle().fill(pinned ? Theme.brand : Color(.tertiarySystemFill))
                    )
                    // ★ 整个圆都是热区（不只是图标那 11pt）。
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }

    private func isPinned(_ route: TemplateRoute) -> Bool {
        pinnedKeys.contains(route.key)
    }

    /// 固定 / 取消固定。
    ///
    /// ★ 2026-10-18 用户订正：「固定只能最多选 1 个，不应该，**每个都可以固定，
    ///   **按固定顺序排先后**」
    ///   ➜ 存成数组：**先固定的排前面**，后固定的排后面。
    private func togglePin(_ route: TemplateRoute) {
        var pinned = pinnedKeys
        if let index = pinned.firstIndex(of: route.key) {
            pinned.remove(at: index)
        } else {
            pinned.append(route.key)
        }
        // 先改 @State（保证界面立刻重绘），再落盘。
        withAnimation(.default) { pinnedKeys = pinned }
        Prefs.pinnedTemplates = pinned
        applyPinOrder()
    }

    /// 按固定顺序把固定的磁贴排到最前（其余保持原有相对顺序）。
    private func applyPinOrder() {
        let pinned = pinnedKeys.compactMap { TemplateRoute.from(key: $0) }
        let rest = order.filter { !pinned.contains($0) }
        withAnimation(.default) { order = pinned + rest }
        Prefs.templateOrder = order.map(\.key)
    }

    /// 删除（隐藏）磁贴 —— 记进 `Prefs.hiddenTemplates`，可用「恢复全部」找回。
    private func remove(_ route: TemplateRoute) {
        let remaining = pinnedKeys.filter { $0 != route.key }
        withAnimation(.default) { pinnedKeys = remaining }
        Prefs.pinnedTemplates = remaining
        var hidden = hiddenKeys
        if !hidden.contains(route.key) { hidden.append(route.key) }
        withAnimation(.default) { hiddenKeys = hidden }
        Prefs.hiddenTemplates = hidden
        withAnimation(.default) {
            order.removeAll { $0 == route }
        }
        Prefs.templateOrder = order.map(\.key)
    }

    /// 按路由生成一张磁贴（4 张卡片的元数据都收在 `TemplateRoute` 里了）。
    private func card(for route: TemplateRoute) -> some View {
        TemplateCard(title: route.title,
                     subtitle: route.subtitle,
                     systemImage: route.systemImage,
                     tint: route.tint,
                     fill: route.fill,
                     route: route)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        ForEach(order, id: \.self) { route in
                            tile(route)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: TileFrameKey.self,
                                            value: [route: geo.frame(in: .named("tileGrid"))]
                                        )
                                    }
                                )
                        }
                    }
                    .coordinateSpace(name: "tileGrid")
                    .onPreferenceChange(TileFrameKey.self) { frames in
                        // 只更新引用类型的属性 —— 不会引起重绘。
                        frameStore.frames = frames
                    }
                    howItWorks
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("效期打印")
            .background(Color(.systemGroupedBackground))
            .toolbar {
                if !hiddenKeys.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("恢复全部") {
                            withAnimation(.default) {
                                hiddenKeys = []
                                Prefs.hiddenTemplates = []
                                order = Self.loadOrder()
                            }
                        }
                        .font(.footnote)
                    }
                }
            }
            .navigationDestination(for: TemplateRoute.self) { route in
                switch route {
                case .generic:
                    GenericTemplateView()
                case .kombucha:
                    KombuchaTemplateView()
                case .dairy:
                    DairyTemplateView()
                case .meat:
                    MeatTemplateView()
                }
            }
        }
    }

    private var header: some View {
        Text("选择一个模板开始制作标签")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("使用流程")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                step(1, "选择模板", "按要标注的品类进入对应模板")
                Divider()
                step(2, "填写信息", "物料名称、操作人与日期")
                Divider()
                step(3, "打印标签", "底部「打印」一键出纸")
            }
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }

    private func step(_ n: Int, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(n)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Theme.brand)
                .frame(width: 24, height: 24)
                .background(Theme.brand.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
}

/// 模板磁贴。
///
/// ★★★ 2026-10-19 定版（**不再用 `GroupBox`**）：
///   实测证据——浅色模式下磁贴背景「完全不见了」：
///   `GroupBox` 在**浅色模式画的就是页面背景色**（`systemGroupedBackground`），
///   所以无论我在它外面叠什么颜色都被它盖住；深色模式能看见只是因为它比纯黑亮一点。
///   ➜ 苹果「健康」App 的卡片本来就是**自己画的**：系统语义色 + 圆角，没有用 GroupBox。
///     这里照它的做法来：
///       `Color(.secondarySystemGroupedBackground)`（浅色=白、深色=#1C1C1E）
///       + `RoundedRectangle(cornerRadius: Theme.tileRadius)`（22）。
struct TemplateCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let fill: Color
    let route: TemplateRoute

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(fill, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.tileRadius))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TemplatesTab(path: .constant(NavigationPath()))
}


// MARK: - 磁贴位置收集（DragGesture 方案）

/// 收集每张磁贴在网格坐标空间里的 frame —— 松手/拖动中用它在算"手指落在哪张磁贴上"。
struct TileFrameKey: PreferenceKey {
    static var defaultValue: [TemplateRoute: CGRect] = [:]
    static func reduce(value: inout [TemplateRoute: CGRect],
                       nextValue: () -> [TemplateRoute: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}


// MARK: - 磁贴位置查询表

/// 用 **class** 持有每张磁贴的位置。
///
/// ★ 关键：它是引用类型 —— 在 `onPreferenceChange` 里改 `frames` **不会**触发
///   SwiftUI 重绘，从而避免「布局→记录→重绘→再布局」的无限循环（拖动越久越卡）。
final class TileFrameStore {
    var frames: [TemplateRoute: CGRect] = [:]
}
