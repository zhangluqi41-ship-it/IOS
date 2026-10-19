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
enum TemplateRoute: Hashable {
    case generic
    case kombucha
    case dairy
    case meat
    /// ★★★ 2026-10-19（用户）：「为什么自定义磁贴不能拖不能固定？之后他和现有磁贴
    ///   **应该是同一套东西**啊」
    ///   ➜ 正解就是让它也成为一种 `route` —— 拖动、固定、排序、隐藏全部自动复用同一套代码。
    ///   `id` 指向 `CustomTemplateStore` 里的模板（名字/图标都从那里取）。
    case custom(UUID)

    /// 内置的 4 个（不含自定义）。
    /// ⚠️ 有关联值后 `CaseIterable` 无法自动合成，这里手写。
    static var allCases: [TemplateRoute] { [.generic, .kombucha, .dairy, .meat] }

    /// 是不是自定义模板。
    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    /// 持久化用的稳定 key（拖动排序 / 固定 / 隐藏都用它）。
    var key: String {
        switch self {
        case .generic: return "generic"
        case .kombucha: return "kombucha"
        case .dairy: return "dairy"
        case .meat: return "meat"
        case .custom(let id): return "custom:\(id.uuidString)"
        }
    }

    static func from(key: String) -> TemplateRoute? {
        if key.hasPrefix("custom:"),
           let id = UUID(uuidString: String(key.dropFirst("custom:".count))) {
            return .custom(id)
        }
        return allCases.first { $0.key == key }
    }

    var title: String {
        switch self {
        case .generic: return "通用效期"
        case .kombucha: return "康普茶"
        case .dairy: return "奶制品"
        case .meat: return "肉类"
        case .custom(let id): return CustomTemplateStore.template(id: id)?.name ?? "已删除的模板"
        }
    }

    var subtitle: String {
        switch self {
        case .generic: return "自定标题与两个日期"
        case .kombucha: return "自动算一发二发日期"
        case .dairy: return "按品类套保质期"
        case .meat: return "冷藏 / 冷冻自动算"
        case .custom:
            return "自定义模板"
        }
    }

    var systemImage: String {
        switch self {
        case .generic: return "clock"
        case .kombucha: return "drop.fill"
        case .dairy: return "flask.fill"
        case .meat: return "fork.knife"
        case .custom(let id): return CustomTemplateStore.template(id: id)?.icon ?? "square.grid.2x2"
        }
    }

    var tint: Color {
        switch self {
        case .generic: return Theme.tplGenericTint
        case .kombucha: return Theme.tplKombuchaTint
        case .dairy: return Theme.tplDairyTint
        case .meat: return Theme.tplMeatTint
        case .custom(let id):
            // 图标颜色（自定义模板可调）。
            let template = CustomTemplateStore.template(id: id)
            return CustomTemplate.color(named: template?.iconColorName ?? "white")
        }
    }

    var fill: Color {
        switch self {
        case .generic: return Theme.tplGenericFill
        case .kombucha: return Theme.tplKombuchaFill
        case .dairy: return Theme.tplDairyFill
        case .meat: return Theme.tplMeatFill
        case .custom(let id):
            // 图标块背景色（自定义模板可调）。
            let template = CustomTemplateStore.template(id: id)
            return CustomTemplate.color(named: template?.tintName ?? "blue")
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
    /// ★ 2026-10-19（用户）：「按住后（进入排序模式）并没有放大，**只有拖拽走后才放大**，
    ///   应该是**按住后只要开始能够移动就放大**」
    ///   ➜ 原来是靠 `dragging`（要移动 6pt 才置位）驱动放大，所以"按下去"那一刻没反应。
    ///   ➜ 新增 `pressedRoute`：**手指一按下就置位**（`DragGesture(minimumDistance: 0)`），
    ///     放大/抬起视觉由 `dragging || pressed` 共同驱动。
    /// 打开自定义模板编辑器（新建）。
    @State private var showTemplateEditor = false
    /// ★ 2026-10-19（用户）：「选删除时**全部磁贴右上角增加一个红色减号圆形标**」
    ///   → 进入"删除模式"：图钉换成红减号，点一下删这个磁贴；拖动暂时禁用。
    @State private var deletingMode = false
    /// ★ 2026-10-19（用户）：「和删除模板一样，红色减号变成**绿色加号**」——编辑模式。
    @State private var editingMode = false
    /// 正在编辑的自定义模板。
    @State private var editingTemplate: CustomTemplate?
    /// 自定义模板列表（改动后刷新磁贴区用）。
    @State private var customTemplates: [CustomTemplate] = CustomTemplateStore.all
    /// 手指相对起点的位移 —— 直接当 offset 用（1:1 跟手）。
    /// 每张磁贴在网格坐标空间里的位置（用来算手指落在谁头上）。
    ///
    /// ★★★ 2026-10-19（用户）：「在拖动的过程中，**时间越久，掉帧越严重**」
    ///   根因：原来是 `@State var tileFrames: [TemplateRoute: CGRect]`（**值类型**）。
    ///   拖动 → 目标让位/布局微变 → `onPreferenceChange` 写入 tileFrames →
    ///   **@State 变化触发整个 body 重绘** → 再布局 → preference 又变 → ……
    ///   每帧都在自增一轮，所以越拖越卡。
    ///   ➜ 改成 **引用类型**（class）存放：改它的属性**不会**触发 SwiftUI 重绘，
    ///     只作为"查询表"用，彻底断掉这个循环。
    /// 手指当前落在哪个磁贴上（让位提示）。
    /// 刚放下的那张 —— 重排时它不加过渡动画（松手就落在新格）。

    /// 读保存的顺序：**跳过已删除的**，并补上新增的路由。
    private static func loadOrder() -> [TemplateRoute] {
        let hidden = Set(Prefs.hiddenTemplates)
        // ★★★ 2026-10-19（用户截图发现）：出现好几个「已删除的模板」磁贴。
        //   根因：模板删掉后 `Prefs.templateOrder` 里还留着 `custom:<uuid>`，
        //   `from(key:)` 又能解析回来 → 变成**幽灵磁贴**（标题兜底成"已删除的模板"）。
        //   ➜ 过滤掉「模板已不存在」的 key。
        let saved = Prefs.templateOrder
            .compactMap { key -> TemplateRoute? in
                guard let route = TemplateRoute.from(key: key) else { return nil }
                if case .custom(let id) = route, CustomTemplateStore.template(id: id) == nil {
                    return nil
                }
                return route
            }
            .filter { !hidden.contains($0.key) }
        // 内置 4 个里缺的补上。
        let missingBuiltin = TemplateRoute.allCases
            .filter { !saved.contains($0) && !hidden.contains($0.key) }
        // ★ 自定义模板也要补进来（新建的要出现在末尾，且能和内置一起拖/固定）。
        let customs = CustomTemplateStore.all.map { TemplateRoute.custom($0.id) }
        let missingCustom = customs
            .filter { !saved.contains($0) && !hidden.contains($0.key) }
        let base = saved + missingBuiltin + missingCustom
        // ★ 固定的排最前，按**固定先后**（用户：「每个都可以固定，按固定顺序排先后」）。
        let pinned = Prefs.pinnedTemplates
            .compactMap { TemplateRoute.from(key: $0) }
            .filter { base.contains($0) }
        let final = pinned + base.filter { !pinned.contains($0) }
        // 顺手把清理后的顺序写回，幽灵 key 就此消失。
        let keys = final.map(\.key)
        if keys != Prefs.templateOrder { Prefs.templateOrder = keys }
        return final
    }

    private func remove(_ route: TemplateRoute) {
        let remaining = pinnedKeys.filter { $0 != route.key }
        withAnimation(.default) { pinnedKeys = remaining }
        Prefs.pinnedTemplates = remaining

        if case .custom(let id) = route {
            // ★ 自定义模板：**真删除**（模板数据一起删），不是像内置那样"隐藏"。
            withAnimation(.default) {
                CustomTemplateStore.delete(id: id)
                customTemplates = CustomTemplateStore.all
                order.removeAll { $0 == route }
                hiddenKeys.removeAll { $0 == route.key }
            }
            Prefs.hiddenTemplates = hiddenKeys
            Prefs.templateOrder = order.map(\.key)
            return
        }

        var hidden = hiddenKeys
        if !hidden.contains(route.key) { hidden.append(route.key) }
        withAnimation(.default) { hiddenKeys = hidden }
        Prefs.hiddenTemplates = hidden
        withAnimation(.default) {
            order.removeAll { $0 == route }
        }
        Prefs.templateOrder = order.map(\.key)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    // ★★★ 2026-10-19（用户第三次反馈「拖动还是有卡顿」）—— 根治：
                    //   网格连同它的拖动状态已经整体搬进 `TemplateGrid` 子视图。
                    //   手指移动时**只有网格重算**，本页的大标题、"使用流程"一行都不动。
                    TemplateGrid(order: $order,
                                 pinnedKeys: $pinnedKeys,
                                 deletingMode: deletingMode,
                                 editingMode: editingMode,
                                 onRemove: remove,
                                 onEdit: { route in
                                     if case .custom(let id) = route,
                                        let template = CustomTemplateStore.template(id: id) {
                                         editingTemplate = template
                                     }
                                 })
                    // ★ 2026-10-19（用户）：「在磁贴上方拖动时掉帧很严重」
                    //   拖动每帧都会重算 body，这块静态卡片也跟着重画（里面有圆角/描边/多层背景）。
                    //   `drawingGroup()` 把它光栅化缓存，拖动期间不再重新渲染。
                    howItWorks
                        .drawingGroup()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("效期打印")
            .background(Color(.systemGroupedBackground))
            .toolbar {
                if !hiddenKeys.isEmpty && !deletingMode {
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
                // ★★★ 2026-10-19（用户）：「B-2 删除磁贴入口放在『效期打印』界面的右上角，
                //   和这张图片一致的功能；同时**自定义模板**可以做了，入口也在这里」
                //   ➜ 右上角 `⋯`（和「效期管理」页同款 `ellipsis.circle`），
                //     里面两项：新建模板 / 删除磁贴（子菜单列出当前所有磁贴）。
                if deletingMode || editingMode {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            withAnimation(.default) {
                                deletingMode = false
                                editingMode = false
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
                // ★ 2026-10-19（用户）：「**删除界面不需要这个按钮**，删除时只做删除处理」
                //   → 删除模式下把 `⋯` 整个收起来，右上角只留「完成」。
                if !deletingMode && !editingMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showTemplateEditor = true
                            } label: {
                                Label("新建模板", systemImage: "plus")
                            }

                            // ★ 2026-10-19（用户）：「这里**没有编辑模板选项**，和删除模板一样，
                            //   红色减号变成**绿色加号**」
                            //   → 菜单三项：新建 / 编辑 / 删除；编辑模式 = 磁贴上显示绿加号。
                            Button {
                                withAnimation(.default) {
                                    deletingMode = false
                                    editingMode = true
                                }
                            } label: {
                                Label("编辑模板", systemImage: "square.and.pencil")
                            }

                            Button(role: .destructive) {
                                withAnimation(.default) {
                                    editingMode = false
                                    deletingMode = true
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            // ★★★ 2026-10-19（用户）：「**整个菜单都不需要**。
            //   以后只有：点击磁贴 → 进效期打印；按住磁贴 → 移动磁贴。
            //   其他手势功能都不需要，以后也不会编辑已完成的标签」
            //   → 长按弹菜单（固定/编辑）整块删除；固定仍靠右上角图钉点按。
            .sheet(item: $editingTemplate) { template in
                CustomTemplateEditor(original: template) { updated in
                    CustomTemplateStore.upsert(updated)
                    customTemplates = CustomTemplateStore.all
                    withAnimation(.default) {
                        order = Self.loadOrder()
                        editingMode = false
                    }
                }
            }
            .sheet(isPresented: $showTemplateEditor) {
                CustomTemplateEditor(original: nil) { template in
                    CustomTemplateStore.upsert(template)
                    customTemplates = CustomTemplateStore.all
                    // ★ 必须重算 order，否则新建的磁贴不会出现（order 只在 @State 初始化时算一次）。
                    withAnimation(.default) { order = Self.loadOrder() }
                }
            }
            .navigationDestination(for: TemplateRoute.self) { route in
                switch route {
                case .custom(let id):
                    // ★ 2026-10-19（用户）：「点开后**就是**『肉类』那种页面，不要多层」
                    //   → 直接进打印页，品类用下拉菜单选；标题 = 模板名。
                    if let template = CustomTemplateStore.template(id: id) {
                        CustomTemplatePage(template: template)
                    } else {
                        ContentUnavailableView("模板已删除", systemImage: "trash")
                    }
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

                // ★ 2026-10-19（用户）：「红框里的**备注不需要，删除**」
                //   → 磁贴上只留图标 + 标题，不再显示 subtitle。
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.tileRadius))
        }
        .buttonStyle(.plain)
        // ★★★ 2026-10-19（用户）：「排序模式还是会掉帧，**特别厉害**，能否渲染也用苹果第一方工具」
        //   ➜ `drawingGroup()` = 用 **Metal 把这一层栅格化成位图**（苹果第一方渲染路径）。
        //     拖动的每一帧只是移动一张现成位图，不再重新走一遍 SwiftUI 的布局/绘制/圆角/文字排版，
        //     这是 SwiftUI 里最直接的「交给系统 GPU 画」开关。
        //   ⚠️ 副作用：文字由 Metal 光栅化，极端放大时可能略软（正常 1:1 显示无感）。
        .drawingGroup()
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
