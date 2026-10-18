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
// `.onDrop(of: [.text], delegate:)` 需要 UTType
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
    /// ★ 2026-10-18（用户订正）：「长按应该**先呼出选项**，长按后移动才是移动」
    ///   → `moving == false` 时长按弹系统菜单；在菜单里选「移动排序」才进入拖动。
    @State private var moving = false
    /// ★★★ 2026-10-18（用户报 bug）：固定/取消固定后**界面不立即刷新**。
    ///   根因：`isPinned` 原来直接读 `Prefs.pinnedTemplates`（UserDefaults）——
    ///   它**不是 SwiftUI 的响应式状态**。只有 `order` 变了才会重绘；
    ///   而"固定的磁贴本来就在第一位"时 `order` 不变 → 不重绘 → 图钉图标不更新。
    ///   ➜ 用 `@State` 镜像一份，任何固定操作都改它（必定触发重绘），再同步进 Prefs。
    @State private var pinnedKeys: [String] = Prefs.pinnedTemplates
    /// 同理：删除的磁贴也要响应式（toolbar 的「恢复全部」按钮靠它决定显示与否）。
    @State private var hiddenKeys: [String] = Prefs.hiddenTemplates
    @State private var dragging: TemplateRoute?
    @State private var dropTarget: TemplateRoute?

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

    /// 单张磁贴：卡片 + 右上角菜单 + **长按先弹菜单 / 选「移动排序」后才可拖**。
    ///
    /// ★★★ 2026-10-18 用户两次订正后的最终口径：
    ///   · 「按住的时候会**消失不见**……而且存在 bug，消失后**点不出来**」
    ///     → 根因：`.onDrag` 一长按就触发，`dragging` 被设上，但**松手在空白处没有回调**
    ///       （`performDrop` 不会调用）→ `dragging` 永远不清 → 磁贴永久透明、点不动。
    ///   · 「长按应该**先呼出选项**，长按后移动才是移动」
    ///     → 现在：**普通模式只挂 `.contextMenu`**（长按弹系统菜单，绝不改状态、不可能卡死）；
    ///       在菜单里选「**移动排序**」→ `moving = true` → **这时才挂 `.onDrag`**。
    ///     （iOS 里 `onDrag` 和 `contextMenu` 抢同一个长按手势，同时挂必然坏掉一个。）
    @ViewBuilder
    private func tile(_ route: TemplateRoute) -> some View {
        if moving {
            tileCore(route)
                .onDrag {
                    dragging = route
                    return NSItemProvider(object: route.key as NSString)
                } preview: {
                    card(for: route).frame(width: 160)
                }
                .onDrop(of: [.text], delegate: TileDropDelegate(
                    item: route,
                    order: $order,
                    dragging: $dragging,
                    dropTarget: $dropTarget
                ))
        } else {
            tileCore(route)
                .contextMenu {
                    Button {
                        togglePin(route)
                    } label: {
                        Label(isPinned(route) ? "取消固定" : "固定",
                              systemImage: isPinned(route) ? "pin.slash" : "pin")
                    }
                    Button {
                        withAnimation(.snappy) { moving = true }
                    } label: {
                        Label("移动排序", systemImage: "arrow.up.arrow.down")
                    }
                    Button(role: .destructive) {
                        remove(route)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
        }
    }

    private func tileCore(_ route: TemplateRoute) -> some View {
        let isDragging = dragging == route
        let isTarget = dropTarget == route
        return ZStack(alignment: .topTrailing) {
            card(for: route)
                // ① 拖起源消失（不是半透明分身）
                .opacity(isDragging ? 0 : 1)
                // ② 目标：变淡 + 轻微上移（"让位趋势"）
                .opacity(isTarget ? 0.5 : 1)
                .offset(y: isTarget ? -5 : 0)
                .animation(.snappy(duration: 0.18), value: isTarget)
                .animation(.snappy(duration: 0.18), value: isDragging)

            // ③ 右上角小按钮：显示固定状态，点开是**系统 Menu**（固定 / 删除）。
            Menu {
                Button {
                    togglePin(route)
                } label: {
                    Label(isPinned(route) ? "取消固定" : "固定",
                          systemImage: isPinned(route) ? "pin.slash" : "pin")
                }
                Button(role: .destructive) {
                    remove(route)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: isPinned(route) ? "pin.fill" : "ellipsis")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isPinned(route) ? Theme.brand : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .opacity(isDragging ? 0 : 1)
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
        withAnimation(.snappy) { pinnedKeys = pinned }
        Prefs.pinnedTemplates = pinned
        applyPinOrder()
    }

    /// 按固定顺序把固定的磁贴排到最前（其余保持原有相对顺序）。
    private func applyPinOrder() {
        let pinned = pinnedKeys.compactMap { TemplateRoute.from(key: $0) }
        let rest = order.filter { !pinned.contains($0) }
        withAnimation(.snappy) { order = pinned + rest }
        Prefs.templateOrder = order.map(\.key)
    }

    /// 删除（隐藏）磁贴 —— 记进 `Prefs.hiddenTemplates`，可用「恢复全部」找回。
    private func remove(_ route: TemplateRoute) {
        let remaining = pinnedKeys.filter { $0 != route.key }
        withAnimation(.snappy) { pinnedKeys = remaining }
        Prefs.pinnedTemplates = remaining
        var hidden = hiddenKeys
        if !hidden.contains(route.key) { hidden.append(route.key) }
        withAnimation(.snappy) { hiddenKeys = hidden }
        Prefs.hiddenTemplates = hidden
        withAnimation(.snappy) {
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

                    if moving {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.draw")
                                .font(.footnote)
                            Text("按住磁贴拖动排序")
                                .font(.footnote)
                            Spacer(minLength: 8)
                            Button("完成") {
                                withAnimation(.snappy) {
                                    moving = false
                                    dragging = nil
                                    dropTarget = nil
                                }
                            }
                            .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        ForEach(order, id: \.self) { route in
                            tile(route)
                        }
                    }
                    // ★ 兜底：拖到**磁贴之间的空白**松手时，`performDrop` 不会被调用，
                    //   `dragging` 会残留 → 那张磁贴永远透明、点不动（用户报的 bug）。
                    //   这里在网格层接住一次 drop，无论如何都把状态清掉。
                    //   ⚠️ 必须显式写 `isTargeted:perform:` —— 只写 `{ _ in }` 时编译器会把
                    //     尾随闭包匹配到 `onDrop(of:delegate:)` 的 `delegate` 上（编译报错）。
                    .onDrop(of: [.text],
                            isTargeted: nil,
                            perform: { _ in
                        dragging = nil
                        dropTarget = nil
                        return false
                    })

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
                            withAnimation(.snappy) {
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
/// ★★★ 2026-10-18 定版（用户确认「A. GroupBox（系统容器）」）：
///   磁贴容器改用**苹果系统自带的 `GroupBox`** ——
///   背景、圆角、内边距**全部由系统渲染**，这里只负责内容排版。
///   ❌ 不要再用 `.background(..., in: RoundedRectangle(...))` 自己画卡片外形
///     （那是"用系统色块拼一个卡片"，不是系统组件）。
///   ❌ 右上角的圆形箭头已按用户要求删除（他看不懂那是什么）。
///   ✅ 长按拖动排序：外层 `.draggable` / `.dropDestination`（见 `TemplatesTab`）。
struct TemplateCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let fill: Color
    let route: TemplateRoute

    var body: some View {
        GroupBox {
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
                // 让整块内容区都能点（否则只有文字本身响应）。
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    TemplatesTab(path: .constant(NavigationPath()))
}


// MARK: - 拖放代理（★ 2026-10-18 用户第 2 条）

/// 磁贴拖放的落点反馈与重排。
///
/// ★ 为什么不用 `.dropDestination(for:)`：那个 API 会在磁贴右上角画一个**「+」角标**
///   （用户：「现在移动的时候如果是能够成功替换，右上角有加号，修改成**透明度减少**」）。
///   `DropDelegate` 完全由我们控制，没有那个角标。
struct TileDropDelegate: DropDelegate {
    let item: TemplateRoute
    @Binding var order: [TemplateRoute]
    @Binding var dragging: TemplateRoute?
    @Binding var dropTarget: TemplateRoute?

    /// 进入某个磁贴：只做"趋势"反馈，**不实时重排**（用户要求「不用完全移动」）。
    func dropEntered(info: DropInfo) {
        withAnimation(.snappy(duration: 0.18)) { dropTarget = item }
    }

    func dropExited(info: DropInfo) {
        if dropTarget == item {
            withAnimation(.snappy(duration: 0.18)) { dropTarget = nil }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    /// 松手才真正换位置。
    func performDrop(info: DropInfo) -> Bool {
        defer {
            withAnimation(.snappy(duration: 0.18)) { dropTarget = nil }
            dragging = nil
        }
        guard let from = dragging,
              let fromIndex = order.firstIndex(of: from),
              let toIndex = order.firstIndex(of: item),
              fromIndex != toIndex else { return false }
        withAnimation(.snappy) {
            let moved = order.remove(at: fromIndex)
            order.insert(moved, at: toIndex)
        }
        Prefs.templateOrder = order.map(\.key)
        return true
    }
}
