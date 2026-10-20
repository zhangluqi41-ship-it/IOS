import SwiftUI

// MARK: - 磁贴网格（独立子视图）
//
// ★★★ 2026-10-19（用户第三次反馈「拖动还是有卡顿」）—— 这次是**根治**。
//
//   之前的架构：`dragOffset` / `dragging` / `dropTarget` 都是 `TemplatesTab` 的 `@State`。
//   SwiftUI 的规则是「`@State` 一变，**持有它的 View 的整个 body 重算**」——
//   所以手指每移动一帧，整页（大标题、"使用流程"、所有卡片）都要重新 diff 一遍。
//   `drawingGroup()` 只省了"重绘"，省不掉"重算 + diff"。
//
//   现在：把**网格连同它的全部拖动状态**关进这个子视图。
//   · 拖动时只有 `TemplateGrid` 的 body 重算，父视图一行都不动；
//   · 父视图只在 `order` / `pinnedKeys` 真正变化（换位、固定）时才重算一次。

struct TemplateGrid: View {
    @Binding var order: [TemplateRoute]
    @Binding var pinnedKeys: [String]
    /// 删除模式：磁贴只显示红减号、禁点击、禁拖动。
    let deletingMode: Bool
    /// ★ 2026-10-19（用户）：「和删除模板一样，红色减号变成**绿色加号**」
    ///   编辑模式：磁贴右上角显示绿加号（只有自定义模板有）。
    let editingMode: Bool
    /// 删除动作交给父视图（它才持有 hiddenKeys 和自定义模板列表）。
    let onRemove: (TemplateRoute) -> Void
    /// 编辑动作也交给父视图（它持有 sheet 状态）。
    let onEdit: (TemplateRoute) -> Void

    @State private var dragging: TemplateRoute?
    /// 手指按下（不等到移动 6pt）—— 驱动"抬起"视觉。
    @State private var pressedRoute: TemplateRoute?
    @State private var dragOffset: CGSize = .zero
    /// 手指当前落在谁头上（那一下会上移 4pt 让位）。
    @State private var dropTarget: TemplateRoute?
    /// 刚放下的那张：重排瞬间不带动画，之后恢复。
    @State private var justDropped: TemplateRoute?
    /// 每张磁贴的位置（引用类型，改属性不触发重绘）。
    @State private var frameStore = TileFrameStore()

    var body: some View {
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
        // 拖动时整个网格提到最上层（zIndex 只比较兄弟）。
        .zIndex(dragging != nil ? 1 : 0)
    }

    // MARK: 单张磁贴

    private func tile(_ route: TemplateRoute) -> some View {
        let isDragging = dragging == route
        let isLifted = isDragging || pressedRoute == route
        return tileCore(route)
            .opacity(isDragging ? 0.85 : 1)
            .scaleEffect(isLifted ? 1.06 : 1)
            // 只作用于前面的 scale/opacity。
            .animation(.default, value: isLifted)
            // offset 在 animation 之后 → 拖动中位移不带动画 = 1:1 跟手。
            .offset(isDragging ? dragOffset : .zero)
            // 松手后用系统默认动画把 offset 归零（从手指落点滑到新格）。
            .animation(isDragging ? nil : .default, value: dragOffset)
            .zIndex(isDragging ? 2 : (justDropped == route ? 1 : 0))
            // ★★★ 2026-10-20（用户）：「**按住就被拖动，导致完全无法下滑**。
            //   应该：按住保持一段时间才能拖动，保证下滑功能正常」
            //   ➜ 原来是 `DragGesture(minimumDistance: 6)` 直接抢手势，手指一动就进入拖动，
            //     ScrollView 永远收不到滚动 → 页面滑不动。
            //   ➜ 改成 **`LongPressGesture(0.4s).sequenced(before: DragGesture)`**：
            //     没长按够 0.4 秒时前置手势**失败**，手势让给外层 ScrollView → 正常滚动；
            //     长按够 0.4 秒才接管后续位移 → 拖动排序。
            //
            //   ⚠️⚠️ 2026-10-20 回归修复（用户报「**史诗级 bug**：图标点击不能进、编辑删除全失效」）：
            //   之前用的是 **`highPriorityGesture`** —— 它的优先级**高于子视图**，
            //   连 `NavigationLink` 的点击和右上角 Button 都被它吞掉，磁贴变成"只能拖、不能点"。
            //   ➜ 换成 **`simultaneousGesture`**：与子视图手势**同时**识别，
            //     Button / NavigationLink 照常响应；拖动手势要长按 0.4s 才成立，
            //     所以正常滑动和点击都不受干扰。
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .sequenced(before: DragGesture(minimumDistance: 0,
                                                   coordinateSpace: .named("tileGrid")))
                    .onChanged { value in
                        // ★★★ 2026-10-20（用户）：「**被固定住的图标就应该移动不了**……
                        //   固定应该是调整了优先的位置之后就锁定位置了，除非点击解除固定」
                        guard !deletingMode, !editingMode, !isPinned(route) else { return }
                        switch value {
                        case .first(true):
                            // 长按达成：进入"已抓起"状态（视觉放大），还没开始位移。
                            if dragging != route { dragging = route }
                        case .second(true, let drag):
                            guard let drag else { return }
                            if dragging != route { dragging = route }
                            dragOffset = drag.translation
                            // 固定项不当落点 —— 否则把它挤开就"锁不住位置"了。
                            let hit = frameStore.frames.first {
                                $0.key != route
                                    && !isPinned($0.key)
                                    && $0.value.contains(drag.location)
                            }?.key
                            // 不加 withAnimation：拖动中每帧开动画事务会堆叠、加剧掉帧。
                            if hit != dropTarget { dropTarget = hit }
                        default:
                            break
                        }
                    }
                    .onEnded { _ in
                        guard !deletingMode, !editingMode, !isPinned(route) else { return }
                        // 只是长按没拖动 / 拖完松手，都走同一个收尾。
                        if dragging == route { finishDrag(from: route) }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("tileGrid"))
                    .onChanged { _ in
                        guard !deletingMode, !editingMode else { return }
                        if pressedRoute != route { pressedRoute = route }
                    }
                    .onEnded { _ in
                        pressedRoute = nil
                    }
            )
    }

    /// 磁贴本体：卡片 + 右上角按钮（删除模式下是红减号，平时是固定图钉）。
    private func tileCore(_ route: TemplateRoute) -> some View {
        let isTarget = dropTarget == route
        let pinned = isPinned(route)
        return ZStack(alignment: .topTrailing) {
            card(for: route)
                // 删除模式下禁用 NavigationLink（点本体不跳转）。
                .disabled(deletingMode || editingMode)
                // 目标只轻微上移（不让它变淡）。
                .offset(y: isTarget ? -4 : 0)
                .animation(.default, value: isTarget)
                // 刚放下的那张重排时不带动画。
                .animation(justDropped == route ? nil : .default, value: order)

            if deletingMode {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button {
                        onRemove(route)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
            } else if editingMode {
                // 编辑模式：只有自定义模板能编辑（内置的没有可改的内容）。
                if route.isCustom {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Button {
                            onEdit(route)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .green)
                                .frame(width: 28, height: 28)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                }
            } else {
                Button {
                    togglePin(route)
                } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(pinned ? Color.white : Color.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(pinned ? Theme.brand : Color(.tertiarySystemFill))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }

    /// 磁贴卡片（只有图标 + 标题，没有副标题）。
    private func card(for route: TemplateRoute) -> some View {
        TemplateCard(title: route.title,
                     systemImage: route.systemImage,
                     tint: route.tint,
                     fill: route.fill,
                     route: route)
        // Metal 光栅化：拖动时只移动位图，不重走布局/圆角/文字排版。
        .drawingGroup()
    }

    // MARK: 状态操作

    private func isPinned(_ route: TemplateRoute) -> Bool {
        pinnedKeys.contains(route.key)
    }

    private func togglePin(_ route: TemplateRoute) {
        var pinned = pinnedKeys
        if let index = pinned.firstIndex(of: route.key) {
            pinned.remove(at: index)
        } else {
            pinned.append(route.key)
        }
        withAnimation(.default) { pinnedKeys = pinned }
        Prefs.pinnedTemplates = pinned

        // 按固定顺序重排（固定的排前面）。
        let pinnedRoutes = pinned.compactMap { TemplateRoute.from(key: $0) }
        let rest = order.filter { !pinnedRoutes.contains($0) }
        withAnimation(.default) { order = pinnedRoutes + rest }
        Prefs.templateOrder = order.map(\.key)
    }

    /// 松手：换位 + 清所有拖动状态。
    private func finishDrag(from route: TemplateRoute) {
        let target = dropTarget
        justDropped = route

        // ① 先结束拖动 → 下一步 offset 归零会走 `.default` 过渡。
        withAnimation(.default) {
            dragging = nil
            dropTarget = nil
        }
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
}
