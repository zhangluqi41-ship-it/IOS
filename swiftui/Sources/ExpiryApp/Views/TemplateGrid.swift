import SwiftUI

// MARK: - 磁贴网格（系统拖放版）
//
// ★★★ 2026-10-20（用户）：**改用苹果第一方的拖放 API**（`.draggable` + `.dropDestination`）
//
//   之前那一套是**自己写手势规则**（`LongPressGesture.sequenced(before: DragGesture)`
//   + 手动 offset / frame 命中检测 / 手动换位 / 手动收尾），代价是：
//     · `highPriorityGesture` 吞掉所有点击（v1.1.52 的史诗级 bug）；
//     · 换 `simultaneousGesture` 又导致"松手顺带进模板页"。
//   ➜ 现在全部交给系统：
//     · `.draggable` 负责"抓起 + 跟手预览"，长按时长、投影、缩放都是系统的；
//     · `.dropDestination` 负责"放到谁身上"，命中判定也是系统的；
//     · 我们只做一件事：**松手后把自己移到目标位置**。
//
//   ⚠️ 系统的取舍（用户已确认接受）：
//     · 拖动中**不实时让位**，目标位置只高亮，松手才换位；
//     · 长按约 0.5 秒启动，无法调整；
//     · 拖到屏幕边缘**不会自动滚动**；
//     · 预览由系统渲染（加投影 + 轻微缩放）。

struct TemplateGrid: View {
    @Binding var order: [TemplateRoute]
    @Binding var pinnedKeys: [String]
    /// 删除模式：磁贴只显示红减号、禁点击、禁拖动。
    let deletingMode: Bool
    /// 编辑模式：磁贴右上角显示绿加号（只有自定义模板有）。
    let editingMode: Bool
    let onRemove: (TemplateRoute) -> Void
    let onEdit: (TemplateRoute) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            ForEach(order, id: \.self) { route in
                // 固定项 / 删除模式 / 编辑模式 → 不给拖放能力。
                // 用 if 分支而不是条件 modifier（SwiftUI 没有"条件挂 gesture"的写法）。
                if isPinned(route) || deletingMode || editingMode {
                    tileCore(route)
                } else {
                    tileCore(route)
                        .draggable(route.key) {
                            // 拖动时跟手的预览：就是这张卡片本身。
                            card(for: route)
                                .frame(width: 160, height: 96)
                                .opacity(0.95)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            handleDrop(items, onto: route)
                        }
                }
            }
        }
    }

    /// 松手：把拖来的那张插到目标位置。
    private func handleDrop(_ items: [String], onto target: TemplateRoute) -> Bool {
        guard let key = items.first,
              let from = TemplateRoute.from(key: key),
              from != target,
              let fromIndex = order.firstIndex(of: from),
              let toIndex = order.firstIndex(of: target) else { return false }

        withAnimation(.default) {
            let moved = order.remove(at: fromIndex)
            order.insert(moved, at: toIndex)
        }
        Prefs.templateOrder = order.map(\.key)
        return true
    }

    /// 磁贴本体：卡片 + 右上角按钮（删除模式红减号 / 编辑模式绿加号 / 平时固定图钉）。
    private func tileCore(_ route: TemplateRoute) -> some View {
        ZStack(alignment: .topTrailing) {
            card(for: route)
                .disabled(deletingMode || editingMode)

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
                    Image(systemName: isPinned(route) ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isPinned(route) ? Color.white : Color.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(isPinned(route) ? Theme.brand : Color(.tertiarySystemFill))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }

    /// 磁贴卡片（只有图标 + 标题）。
    private func card(for route: TemplateRoute) -> some View {
        TemplateCard(title: route.title,
                     systemImage: route.systemImage,
                     tint: route.tint,
                     fill: route.fill,
                     route: route)
        .drawingGroup()
    }

    private func isPinned(_ route: TemplateRoute) -> Bool {
        pinnedKeys.contains(route.key)
    }

    /// 固定 / 取消固定（先固定的排前面）。
    private func togglePin(_ route: TemplateRoute) {
        var pinned = pinnedKeys
        if let index = pinned.firstIndex(of: route.key) {
            pinned.remove(at: index)
        } else {
            pinned.append(route.key)
        }
        withAnimation(.default) { pinnedKeys = pinned }
        Prefs.pinnedTemplates = pinned

        let pinnedRoutes = pinned.compactMap { TemplateRoute.from(key: $0) }
        let rest = order.filter { !pinnedRoutes.contains($0) }
        withAnimation(.default) { order = pinnedRoutes + rest }
        Prefs.templateOrder = order.map(\.key)
    }
}
