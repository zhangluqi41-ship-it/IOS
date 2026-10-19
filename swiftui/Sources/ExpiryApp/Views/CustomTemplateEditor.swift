import SwiftUI

// MARK: - 自定义模板编辑器（v2：一屏树形，不再逐层翻页）
//
// ★★★ 2026-10-19（用户）：
//   「不需要这么多层的选项，应该点开后就是（打印页）这种类型的页面」
//   ➜ 原来编辑菜单是 `NavigationLink` 一层层点进去（模板 → 桃浓缩汁 → 子项…），
//     建个三级菜单要点好几次、还看不到全貌。
//   ➜ 现在：**一屏列出整棵树**（缩进表示层级），点某一行的铅笔直接弹窗改它。

struct CustomTemplateEditor: View {
    let original: CustomTemplate?
    let onSave: (CustomTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomTemplate
    /// 正在编辑的节点（用索引路径定位，避免在树里搬 Binding）。
    @State private var editingPath: NodePath?

    init(original: CustomTemplate?, onSave: @escaping (CustomTemplate) -> Void) {
        self.original = original
        self.onSave = onSave
        _draft = State(initialValue: original ?? CustomTemplate(name: ""))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("点击输入模板名称", text: $draft.name)

                    // ★★★ 2026-10-19（用户）：「这里**没有天数**，增加功能」
                    //   ➜ 根因：`Section` 的 **footer 只支持纯文本**，把 `Toggle`/`Stepper`
                    //     塞进 footer 里 Stepper 根本不会渲染（Toggle 侥幸显示出来了）。
                    //   ➜ 现在整组放进 Section 的**正文**：开关 + 天数步进器都在这张卡片里。
                    Toggle("设建议天数", isOn: Binding(
                        get: { draft.defaultDays != nil },
                        set: { on in
                            draft.defaultDays = on ? (draft.defaultDays ?? 3) : nil
                            // 模板本身设了天数 → 锁定在第 0 层，下面各级的天数开关全部禁用。
                            draft.timeLevel = on ? 0 : nil
                        }
                    ))

                    if draft.defaultDays != nil {
                        Stepper(value: Binding(
                            get: { draft.defaultDays ?? 3 },
                            set: { draft.defaultDays = max(1, $0) }
                        ), in: 1...365) {
                            HStack {
                                Text("天数")
                                Spacer()
                                Text("\(draft.defaultDays ?? 3) 天")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                } header: {
                    Text("模板名称")
                } footer: {
                    if draft.defaultDays != nil {
                        Text("设在这里，下面各级菜单就不用再设天数了（它们会继承这个值）。")
                    }
                }

                // ★★★ 2026-10-19（用户）：「图标设置占用太大了，可以**单独开一个子菜单**来设置，
                //   同时在设置颜色时**增加一个预览**」
                //   ➜ 图标 40 个 + 两组色板全部收进 `TemplateAppearanceEditor`，
                //     主页只留这一行（带当前外观的小预览）。
                Section {
                    NavigationLink {
                        TemplateAppearanceEditor(icon: $draft.icon,
                                                 tintName: $draft.tintName,
                                                 iconColorName: $draft.iconColorName,
                                                 previewTitle: draft.name)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: draft.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(CustomTemplate.color(named: draft.iconColorName))
                                .frame(width: 32, height: 32)
                                .background(
                                    CustomTemplate.color(named: draft.tintName),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            Text("图标与颜色")
                            Spacer()
                        }
                    }
                }

                // ★ 2026-10-19（用户）：新建模板页加两个功能开关。
                Section {
                    Toggle("使用制备功能", isOn: $draft.usePrep)

                    // ★ 2026-10-19（用户）：「**懒人一键保质期**，然后选择顺延的天数」
                    //   ★ 同日追加：「**有制备功能后就不需要懒人保质期了**，因为打印出来的
                    //     没有保质期信息。打开制备信息，懒人保质期变灰色」
                    Toggle("懒人一键保质期", isOn: Binding(
                        get: { draft.lazyDays != nil },
                        set: { on in draft.lazyDays = on ? (draft.lazyDays ?? 7) : nil }
                    ))
                    .disabled(draft.usePrep)
                    if let days = draft.lazyDays {
                        Stepper(value: Binding(
                            get: { days },
                            set: { draft.lazyDays = max(1, $0) }
                        ), in: 1...365) {
                            HStack {
                                Text("顺延天数")
                                Spacer()
                                Text("\(days) 天")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    Toggle("扫描二维码二次制备", isOn: $draft.useSecondary)

                    if draft.useSecondary {
                        // ★ 2026-10-19（用户）：「开启扫描功能后这里应该是**选择绑定的模板**」
                        Picker("绑定模板", selection: $draft.sourceTemplateID) {
                            Text("未选择").tag(UUID?.none)
                            ForEach(otherTemplates) { t in
                                Text(t.name).tag(Optional(t.id))
                            }
                        }
                        .pickerStyle(.menu)

                        // ★ 2026-10-19（用户）：「这个**绑定模板是可以选到下面的子菜单**的」
                        if let source = otherTemplates.first(where: { $0.id == draft.sourceTemplateID }),
                           !source.allPaths.isEmpty {
                            Picker("绑定到", selection: $draft.sourceNodePath) {
                                Text("整个模板").tag([String]())
                                ForEach(source.allPaths, id: \.self) { path in
                                    Text(path.joined(separator: " · ")).tag(path)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                } header: {
                    Text("功能")
                } footer: {
                    if draft.usePrep {
                        Text("开：标签用「制备时间 / 完成时间 / 最佳使用时间」三行（同康普茶）。"
                             + "关：用「开封时间 / 原始保质期 / 最佳使用时间」。")
                    }
                    if draft.useSecondary {
                        if draft.sourceTemplateID == nil {
                            Text("请选择「绑定模板」—— 只有那个模板打出来的标签，扫码时才会进到这里。")
                                .foregroundStyle(.orange)
                        } else {
                            Text("扫到「\(otherTemplates.first { $0.id == draft.sourceTemplateID }?.name ?? "")」"
                                 + "的标签 → 完成时间 = 扫描时刻 + \(draft.defaultDays ?? 3) 天（用上面的建议天数），"
                                 + "最佳使用时间沿用原标签。")
                        }
                    }
                }

                // ★★★ 2026-10-19（用户）：「**和下面命名规则功能冲突，不需要**」
                //   → 删掉「命名带模板名称」这个开关；要不要带模板名，
                //     直接在「命名规则」里点按「模板名」字段决定。
                // ★★★ 2026-10-19（用户）：「还是增加**名称自定义**吧，顺序啊，"‑"用哪些名称连接
                //   都可以自己来选择」→ 点按字段拼顺序 + 选连接符。
                Section {
                    // 已选顺序
                    if draft.titleParts.isEmpty {
                        Text("默认规则（按菜单路径拼）")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(draft.titleParts.enumerated()), id: \.offset) { index, part in
                            HStack {
                                Text("\(index + 1). \(part.rawValue)")
                                Spacer()
                                Button {
                                    draft.titleParts.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 点按添加
                    Text("点按添加字段")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                        ForEach(availableParts) { part in
                            Button {
                                draft.titleParts.append(part)
                            } label: {
                                Text(part.rawValue)
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color(uiColor: .tertiarySystemFill),
                                                in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // 连接符
                    Picker("连接符", selection: $draft.titleSeparator) {
                        Text("短横线  -").tag("-")
                        Text("中点  ·").tag("·")
                        Text("空格").tag(" ")
                        Text("下划线  _").tag("_")
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("命名规则")
                } footer: {
                    if draft.titleParts.isEmpty {
                        Text("没有添加字段时按默认规则：空菜单是「模板名-手输名」，有菜单是菜单路径。")
                    } else {
                        Text("标题按上面的顺序拼接，仅取当前已选到的层级；连接符用「\(draft.titleSeparator)」。")
                    }
                }

                Section {
                    // ★ 一屏展示整棵树：缩进 = 层级，右侧显示天数，点铅笔弹窗改。
                    ForEach(flattened(), id: \.pathKey) { row in
                        rowView(row)
                    }
                    Button {
                        draft.nodes.append(CustomNode(name: ""))
                    } label: {
                        Label("添加菜单项", systemImage: "plus.circle")
                    }
                } header: {
                    Text("菜单")
                } footer: {
                    if hasUnnamedNode {
                        Text("有菜单项还没填名字，填好才能保存。")
                            .foregroundStyle(.red)
                    } else {
                        Text("缩进表示层级（最多 3 层子菜单）。每一级都可以设建议天数；"
                             + "打印时选中哪一级，就用那一级的建议天数（从打印当天往后算）。")
                    }
                }
            }
            .navigationTitle(original == nil ? "新建模板" : "编辑模板")
            .navigationBarTitleDisplayMode(.inline)
            // ★★★ 2026-10-19（用户）：「新建模板**能够下拉退出。不应该这样**，否则输入的
            //   信息都丢失了。**不要有这种手势操作**」
            //   ➜ 关掉 sheet 的 interactive dismiss，只能点「取消」或「保存」离开。
            .interactiveDismissDisabled(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                    // ★ 菜单整体可以为空（= 前缀模板，打印时手输物料名）；
                    //   但只要建了菜单，**每一项都必须有名字** —— 不能留"未命名"
                    //   （否则打印页的下拉里会出现一个空选项，用户实测要求禁止）。
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || hasUnnamedNode)
                }
            }
            .sheet(item: $editingPath) { path in
                CustomNodeSheet(
                    node: Binding(
                        get: { node(at: path.indices) ?? CustomNode(name: "") },
                        set: { newValue in update(at: path.indices) { $0 = newValue } }
                    ),
                    level: path.indices.count,
                    canAddChild: path.indices.count < CustomNode.maxDepth,
                    // ★ 用户规则：天数**只出现在某一层**。还没定时随便哪层都能设；
                    //   一旦定了，其他层的开关就禁用（避免同一棵树里时间出现在两个层级）。
                    canSetDays: draft.timeLevel == nil || draft.timeLevel == path.indices.count,
                    lockedLevel: draft.timeLevel
                )
                .onDisappear { syncTimeLevel() }
            }
        }
    }

    /// ★★★ 2026-10-19（用户）：「**如果设置了几层，就显示出几层**……如果扫二维码二次制备
    ///   绑定了母标签，那么这里面才会有源标签标题……**而不是甩一堆可能是空值的选项出来**」
    ///   ➜ 命名规则里只列**当前模板真的取得到值**的字段：
    ///     · 层数按实际菜单深度；空菜单时第一层 = 手输名（所以仍显示「第一层」）；
    ///     · 「原标签标题」只在开了二次制备且绑定了母模板时出现；
    ///     · 「手输名称」不单独列（空菜单时「第一层」就是它，有菜单时根本没输入框）。
    private var availableParts: [TitlePart] {
        var parts: [TitlePart] = [.template]
        let depth = maxDepth(of: draft.nodes)
        if depth == 0 {
            parts.append(.level1)          // 空菜单：第一层 = 手输物料名
        } else {
            if depth >= 1 { parts.append(.level1) }
            if depth >= 2 { parts.append(.level2) }
            if depth >= 3 { parts.append(.level3) }
        }
        if draft.useSecondary, draft.sourceTemplateID != nil {
            parts.append(.source)
        }
        return parts
    }

    /// 菜单树的最大深度（0 = 没有菜单）。
    private func maxDepth(of nodes: [CustomNode]) -> Int {
        guard !nodes.isEmpty else { return 0 }
        return 1 + (nodes.map { maxDepth(of: $0.children) }.max() ?? 0)
    }

    /// 可以绑定为「源模板」的其他模板（排除自己）。
    private var otherTemplates: [CustomTemplate] {
        CustomTemplateStore.all.filter { $0.id != draft.id }
    }

    /// 树里是否存在「名字为空」的节点。
    ///
    /// ★ 2026-10-19（用户）：「**不能允许创建的时候存在未命名的菜单**」
    ///   → 保存按钮在存在空节点时禁用。
    private var hasUnnamedNode: Bool {
        flattened().contains {
            $0.node.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// 扫全树，把"唯一有天数的那一层"记到 `timeLevel`。
    private func syncTimeLevel() {
        var levels = Set<Int>()
        for row in flattened() where row.node.days != nil {
            levels.insert(row.level + 1)      // level 是 0-based → 层号 +1
        }
        draft.timeLevel = levels.count == 1 ? levels.first : nil
    }

    // MARK: 行

    @ViewBuilder
    private func rowView(_ row: FlatRow) -> some View {
        HStack(spacing: 8) {
            if row.level > 0 {
                // 缩进用固定宽度，比全角空格更整齐。
                Color.clear.frame(width: CGFloat(row.level) * 16, height: 1)
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(row.node.name.isEmpty ? "未命名" : row.node.name)
                .foregroundStyle(row.node.name.isEmpty ? .secondary : .primary)
            Spacer(minLength: 8)
            if let days = row.node.days {
                Text("\(days) 天")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                editingPath = NodePath(indices: row.path)
            } label: {
                Image(systemName: "pencil")
                    .font(.footnote)
                    .foregroundStyle(Theme.brand)
            }
            .buttonStyle(.plain)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                remove(at: row.path)
            } label: {
                Image(systemName: "trash")
            }
            .tint(.red)
        }
    }

    // MARK: 树操作（索引路径）

    private struct FlatRow {
        let node: CustomNode
        let path: [Int]
        let level: Int
        var pathKey: String { path.map(String.init).joined(separator: "/") }
    }

    private func flattened(_ nodes: [CustomNode]? = nil,
                           path: [Int] = [],
                           level: Int = 0) -> [FlatRow] {
        let list = nodes ?? draft.nodes
        return list.enumerated().flatMap { index, node -> [FlatRow] in
            let p = path + [index]
            return [FlatRow(node: node, path: p, level: level)]
                + flattened(node.children, path: p, level: level + 1)
        }
    }

    private func node(at indices: [Int]) -> CustomNode? {
        var list = draft.nodes
        var target: CustomNode?
        for i in indices.indices {
            let idx = indices[i]
            guard list.indices.contains(idx) else { return nil }
            if i == indices.count - 1 {
                target = list[idx]
            } else {
                list = list[idx].children
            }
        }
        return target
    }

    private func update(at indices: [Int], _ transform: (inout CustomNode) -> Void) {
        guard !indices.isEmpty else { return }
        mutate(&draft.nodes, indices, transform)
    }

    private func mutate(_ nodes: inout [CustomNode], _ indices: [Int],
                        _ transform: (inout CustomNode) -> Void) {
        guard let first = indices.first, nodes.indices.contains(first) else { return }
        if indices.count == 1 {
            transform(&nodes[first])
        } else {
            mutate(&nodes[first].children, Array(indices.dropFirst()), transform)
        }
    }

    private func remove(at path: [Int]) {
        guard !path.isEmpty else { return }
        var nodes = draft.nodes
        removeMutate(&nodes, path)
        withAnimation(.default) { draft.nodes = nodes }
    }

    private func removeMutate(_ nodes: inout [CustomNode], _ indices: [Int]) {
        guard let first = indices.first, nodes.indices.contains(first) else { return }
        if indices.count == 1 {
            nodes.remove(at: first)
        } else {
            removeMutate(&nodes[first].children, Array(indices.dropFirst()))
        }
    }

    /// ★ 2026-10-19（用户）：「**增加图标数量**」→ 16 → 40 个（5 行 × 8）。
    static let iconChoices = [
        "square.grid.2x2", "shippingbox", "drop", "leaf", "flame", "snowflake",
        "cup.and.saucer", "carrot", "fish", "birthday.cake", "fork.knife", "barcode",
        "thermometer", "clock", "tag", "bag", "cart", "archivebox", "tray", "cylinder",
        "cube", "square.stack", "mug", "wineglass", "basket", "heart", "star", "bolt",
        "sparkles", "square.grid.3x3", "circle.hexagongrid", "doc.text", "checklist",
        "bookmark", "flag", "paintpalette", "scissors", "wrench", "hammer", "takeoutbag.and.cup.and.straw",
    ]
}

/// 节点在树里的位置（索引路径），用作 sheet 的 item。
struct NodePath: Identifiable, Hashable {
    let indices: [Int]
    var id: String { indices.map(String.init).joined(separator: "/") }
}

// MARK: - 单项编辑弹窗

struct CustomNodeSheet: View {
    @Binding var node: CustomNode
    let level: Int
    let canAddChild: Bool
    /// 这一层能不能设天数（同一模板里天数只能出现在一层）。
    let canSetDays: Bool
    /// 已经定下来的时间层（用于提示）。
    let lockedLevel: Int?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("名称") {
                    TextField("点击输入名称", text: $node.name)
                }

                Section {
                    Toggle("设建议天数", isOn: Binding(
                        get: { node.days != nil },
                        set: { on in
                            guard canSetDays else { return }
                            node.days = on ? (node.days ?? 3) : nil
                        }
                    ))
                    .disabled(!canSetDays)
                    if node.days != nil {
                        Stepper(value: Binding(
                            get: { node.days ?? 3 },
                            set: { node.days = max(1, $0) }
                        ), in: 1...365) {
                            HStack {
                                Text("天数")
                                Spacer()
                                Text("\(node.days ?? 3) 天")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    // ★ 2026-10-19（用户）：「懒人一键保质期，这个就是原始保质期」
                    //   → 上面那个 = 原始保质期；这里再加一个 = 最佳使用时间。
                    Toggle("设最佳天数", isOn: Binding(
                        get: { node.bestDays != nil },
                        set: { on in node.bestDays = on ? (node.bestDays ?? (node.days ?? 3)) : nil }
                    ))
                    if let best = node.bestDays {
                        Stepper(value: Binding(
                            get: { best },
                            set: { node.bestDays = max(1, $0) }
                        ), in: 1...365) {
                            HStack {
                                Text("最佳天数")
                                Spacer()
                                Text("\(best) 天")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                } header: {
                    Text("时间")
                } footer: {
                    if canSetDays {
                        Text("「天数」= 原始保质期，「最佳天数」= 最佳使用时间（留空就跟随原始）。")
                    } else {
                        Text("这个模板的天数设在第 \(lockedLevel ?? 0) 层，这一层不用再设"
                             + "（下级会继承上面的天数）。")
                    }
                }

                if canAddChild {
                    Section("子菜单（第 \(level + 1) 层）") {
                        // ★ 2026-10-19（用户）：「这里的名称**无法修改**」
                        //   ➜ 原来子项只是只读的 `Text`。现在换成**内联 `TextField`**，
                        //     点上去直接改名（不再嵌一层弹窗，避免递归）。
                        //   ➜ 天数不在这里改 —— 按"时间只在一个层级"的规则，子项继承上级的天数。
                        ForEach($node.children) { $child in
                            HStack(spacing: 8) {
                                TextField("未命名", text: $child.name)
                                Spacer(minLength: 8)
                                if let days = child.days {
                                    Text("\(days) 天")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            node.children.remove(atOffsets: offsets)
                        }

                        Button {
                            node.children.append(CustomNode(name: ""))
                        } label: {
                            Label("添加子项", systemImage: "plus.circle")
                        }
                    }
                }
            }
            .navigationTitle(node.name.isEmpty ? "菜单项" : node.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    CustomTemplateEditor(original: nil) { _ in }
}
