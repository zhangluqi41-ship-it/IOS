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

    /// 单张磁贴：卡片 + 右上角「固定」快捷键 + **系统拖放（健康 App 同款）**。
    ///
    /// ★★★ 2026-10-19（用户指出：「这是健康 app 的磁贴，你说动不了？这就是我动了的样子」）
    ///   ➜ 我之前判断错了：健康 App 的磁贴**确实可以拖动**，用的是系统拖放。
    ///   ➜ 这里同样用系统拖放（`.onDrag` + `.onDrop(delegate:)`）；
    ///     关键是把 preview 换成**轻量视图** —— 之前拿整张 GroupBox 卡片当 preview，
    ///     每帧重渲染导致卡顿，看起来像"不跟手"。
    ///   ➜ 源位置的半透明残影由**系统**渲染（和健康 App 里一模一样），我不再手工改 opacity。
    private func tile(_ route: TemplateRoute) -> some View {
        tileCore(route)
            .onDrag {
                dragging = route
                return NSItemProvider(object: route.key as NSString)
            } preview: {
                dragPreview(for: route)
            }
            .onDrop(of: [.text], delegate: TileDropDelegate(
                item: route,
                order: $order,
                dragging: $dragging,
                dropTarget: $dropTarget,
                justDropped: $justDropped
            ))
    }

    /// 拖动时跟手的那个"小卡片" —— **刻意做轻**：纯色圆角 + 图标 + 标题。
    /// （用完整卡片的 GroupBox/NavigationLink/材质渲染，会拖慢跟手。）
    private func dragPreview(for route: TemplateRoute) -> some View {
        HStack(spacing: 10) {
            Image(systemName: route.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(route.tint)
                .frame(width: 34, height: 34)
                .background(route.fill, in: RoundedRectangle(cornerRadius: 9))
            Text(route.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(width: 170)
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

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        ForEach(order, id: \.self) { route in
                            tile(route)
                        }
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
        // ★★★ 2026-10-19（用户第 1 条）：「白天模式下**完全看不见磁贴**」
        //   根因：`GroupBox` 是"靠间距分组"的容器，**浅色模式下它自己几乎不画背景**
        //   （页面底色 `systemGroupedBackground` 与它完全融为一体，没有任何卡片边界）。
        //   ➜ 垫一层**系统语义色** `secondarySystemGroupedBackground`
        //     （浅色=白卡、深色=#1C1C1E），自动跟随外观，不是写死的颜色。
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    TemplatesTab(path: .constant(NavigationPath()))
}


// MARK: - 拖放代理（系统拖放，落点反馈 + 换位）

/// 磁贴拖放的落点反馈与换位。
///
/// ★ 为什么用 `DropDelegate` 而不是 `.dropDestination(for:)`：
///   后者会在磁贴右上角画一个系统的**「+」角标**（用户明确否掉）。
///   代理方式完全由我们控制 —— 只有"变淡 + 上移"的让位提示。
struct TileDropDelegate: DropDelegate {
    let item: TemplateRoute
    @Binding var order: [TemplateRoute]
    @Binding var dragging: TemplateRoute?
    @Binding var dropTarget: TemplateRoute?
    @Binding var justDropped: TemplateRoute?

    /// 手指进入某张磁贴：只做"让位"提示，**不实时重排**（用户要求「不用完全移动」）。
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
    ///
    /// ★ 2026-10-19（用户 bug）：「移动磁贴后有些磁贴会突然消失」
    ///   → **先把拖动状态清干净，再重排**；换位不成功（同位置）则什么都不做、自动回原位。
    func performDrop(info: DropInfo) -> Bool {
        let from = dragging
        withAnimation(.snappy(duration: 0.15)) {
            dropTarget = nil
            dragging = nil
        }
        guard let from,
              let fromIndex = order.firstIndex(of: from),
              let toIndex = order.firstIndex(of: item),
              fromIndex != toIndex else { return false }

        // 刚放下的那张不加过渡动画（松手直接落在新格），其余磁贴平滑移动。
        justDropped = from
        withAnimation(.snappy(duration: 0.22)) {
            let moved = order.remove(at: fromIndex)
            order.insert(moved, at: toIndex)
        }
        Prefs.templateOrder = order.map(\.key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            justDropped = nil
        }
        return true
    }
}
