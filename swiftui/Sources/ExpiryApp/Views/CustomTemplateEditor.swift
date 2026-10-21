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
                    Toggle("设最佳使用时间", isOn: Binding(
                        get: { draft.defaultDays != nil },
                        set: { on in
                            draft.defaultDays = on ? (draft.defaultDays ?? 3) : nil
                        }
                    ))

                    if let days = draft.defaultDays {
                        Stepper(value: Binding(
                            get: { days },
                            set: { draft.defaultDays = max(1, $0) }
                        ), in: 1...365) {
                            HStack {
                                Text("最佳天数")
                                Spacer()
                                Text("\(days) 天")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }

                    // ★★★ 2026-10-20（用户）：「把**懒人一键保质期**改名为**无保质期**，
                    //   下面再增加一栏**设原始保质期**，数据绑定到原始保质期中」
                    //   +「开启制备功能后，设原始保质期和无保质期**都变灰色无法点击**」
                    //   +「无保质期和设原始保质期只能二选一，选了其中一个，另一个
                    //      **在任何一个层级都是灰色**」
                    // ★★★ 2026-10-20（用户）：「扫描二维码功能开启后，**原始保质期应该是扫描上一个
                    //   标签的延续，不应该发生改变**。所以打开扫描二维码功能后，**所有的原始保质期的
                    //   输入和开关全部变成灰色，不可按**」
                    Toggle("无保质期", isOn: $draft.noExpiry)
                        .disabled(draft.usePrep || draft.useSecondary || anyOriginalDays)

                    Toggle("设原始保质期", isOn: Binding(
                        get: { draft.originalDays != nil },
                        set: { on in
                            draft.originalDays = on ? (draft.originalDays ?? 30) : nil
                        }
                    ))
                    .disabled(draft.usePrep || draft.useSecondary || anyNoExpiry)

                    if let days = draft.originalDays {
                        Stepper(value: Binding(
                            get: { days },
                            set: { draft.originalDays = max(1, $0) }
                        ), in: 1...3650) {
                            HStack {
                                Text("原始天数")
                                Spacer()
                                Text("\(days) 天")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .disabled(draft.usePrep || draft.useSecondary)
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
                        // ★★★ 2026-10-20（用户）：「打开制备开关的时候，**懒人的按钮应该弹回**、
                        //   变灰，而不是直接变灰」
                        //   ➜ 打开制备时把 `noExpiry` 关掉 → Toggle 自己弹回"关"，再跟着变灰。
                        .onChange(of: draft.usePrep) { _, isOn in
                            if isOn {
                                draft.noExpiry = false
                                draft.originalDays = nil   // 制备模式没有"原始保质期"
                            }
                        }

                    // ★★★ 2026-10-20（用户）：「开启制备功能后**没有需要制备的天数，
                    //   应该增加制备天数设置**」→ 制备版式的完成时间 = 制备 + prepDays。
                    if draft.usePrep {
                        Stepper(value: $draft.prepDays, in: 1...365) {
                            HStack {
                                Text("制备天数")
                                Spacer()
                                Text("\(draft.prepDays) 天")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }

                    Toggle("扫描二维码二次制备", isOn: $draft.useSecondary)

                    if draft.useSecondary {
                        // ★★★ 2026-10-21（用户）：「开关名称修改"**不需要修改模板名**"。
                        //   打开这个功能后不需要输入模板名，因为他是开启扫码二次制备才有的规则，
                        //   所以不会影响到正常模板」
                        //   ➜ 开关语义反转：**开 = 不需要改**（needsManualName = false）。
                        Toggle("不需要修改模板名", isOn: Binding(
                            get: { !draft.needsManualName },
                            set: { draft.needsManualName = !$0 }
                        ))

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
                            // ★★★ 2026-10-20（用户）：「**绑定是不是没有带原标签等级制度？
                            //   这个绑定到应该是按等级区分**」+ 手绘树形：
                            //     绑定到 ─ 冷藏 ─ 猪肉
                            //            └ 冷冻（整个菜单）
                            //   ➜ 原来是把所有路径拍平成一个列表（"冷藏 · 猪肉"），看不出层级。
                            //   ➜ 改成**逐层 Picker**：每层都能选「整个XX」或继续往下钻，
                            //     `sourceNodePath` 就是选出来的那一串名字。
                            bindingLevelPickers(source: source)
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
                    anyNoExpiry: anyNoExpiry,
                    anyOriginalDays: anyOriginalDays,
                    templateLocksExpiry: draft.usePrep || draft.useSecondary
                )
            }
        }
    }

    /// 「绑定到」的逐层选择器（树形展开，每层可选"整个这一层"或继续下钻）。
    ///
    /// ★ 2026-10-20（用户）手绘结构：
    ///   绑定到 ─ 冷藏 ─ 猪肉
    ///          └ 冷冻（整个菜单）
    @ViewBuilder
    private func bindingLevelPickers(source: CustomTemplate) -> some View {
        // 当前已经选到的节点链
        let chain: [CustomNode] = {
            var result: [CustomNode] = []
            var level = source.nodes
            for name in draft.sourceNodePath {
                guard let node = level.first(where: { $0.name == name }) else { break }
                result.append(node)
                level = node.children
            }
            return result
        }()

        // 每一层一个 Picker（最多 3 层）
        ForEach(0..<CustomNode.maxDepth, id: \.self) { level in
            if level == 0 || chain.count >= level {
                let options = level == 0 ? source.nodes : chain[level - 1].children
                if !options.isEmpty {
                    Picker(level == 0 ? "绑定到" : "└ 第 \(level + 1) 层",
                           selection: bindingForLevel(level, chain: chain)) {
                        Text(level == 0 ? "整个模板" : "整个「\(chain[level - 1].name)」")
                            .tag("")
                        ForEach(options) { node in
                            Text(node.name).tag(node.name)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    /// 第 `level` 层选中的名字（写到 `sourceNodePath[level]`，同时截断更深的层）。
    private func bindingForLevel(_ level: Int, chain: [CustomNode]) -> Binding<String> {
        Binding(
            get: {
                level < draft.sourceNodePath.count ? draft.sourceNodePath[level] : ""
            },
            set: { newValue in
                var path = Array(draft.sourceNodePath.prefix(level))
                if !newValue.isEmpty { path.append(newValue) }
                draft.sourceNodePath = path
            }
        )
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
            // ★★★ 2026-10-21（用户）：「如果打开了"**不需要修改模板名**"，下方菜单项也没新增，
            //   **就不应该存在第一层**」→ 手输被关掉后，"第一层"取不到值，直接不出现。
            if draft.needsManualName {
                parts.append(.level1)      // 空菜单 + 需要手输：第一层 = 手输物料名
            }
        } else {
            if depth >= 1 { parts.append(.level1) }
            if depth >= 2 { parts.append(.level2) }
            if depth >= 3 { parts.append(.level3) }
        }
        if draft.useSecondary, draft.sourceTemplateID != nil {
            // ★★★ 2026-10-21（用户报：「康普茶原标签有两级，**新康普茶、红茶**，但是打印出来
            //   **只有第一个层级，第二个层级没有**」）——
            //   真因：原来按「绑定模板的菜单深度」算原标签层数。但**「红茶」是手输的**
            //   （原模板没开「不需要修改模板名」），它不在菜单树里 → `maxDepth` 只有 1
            //   → 「原标签第二层」根本不出现在字段列表里。
            //   ➜ 原标签的段数**运行时才知道**（模板名 + 菜单各层 + 手输名，最多 3 段），
            //     所以这里**固定给满 3 层**，让用户在编辑器里就能配到。
            if draft.sourceTemplateID != nil {
                parts.append(.sourceLevel1)
                parts.append(.sourceLevel2)
                parts.append(.sourceLevel3)
            }
        }
        return parts
    }

    /// 菜单树的最大深度（0 = 没有菜单）。
    private func maxDepth(of nodes: [CustomNode]) -> Int {
        guard !nodes.isEmpty else { return 0 }
        return 1 + (nodes.map { maxDepth(of: $0.children) }.max() ?? 0)
    }

    /// 可以绑定为「源模板」的其他模板（排除自己）。
    /// 整棵树（含模板级）里有没有任何一项开了「无保质期」。
    private var anyNoExpiry: Bool {
        draft.noExpiry || hasNode(draft.nodes) { $0.noExpiry }
    }

    /// 整棵树（含模板级）里有没有任何一项设了「原始保质期」。
    private var anyOriginalDays: Bool {
        draft.originalDays != nil || hasNode(draft.nodes) { $0.originalDays != nil }
    }

    private func hasNode(_ nodes: [CustomNode], where predicate: (CustomNode) -> Bool) -> Bool {
        for node in nodes {
            if predicate(node) { return true }
            if hasNode(node.children, where: predicate) { return true }
        }
        return false
    }

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
    /// ★ 全局：整棵树里有没有任何一项开了「无保质期」/ 设了「原始保质期」——
    ///   这两项**只能二选一**，任一层选了另一个，所有层都灰。
    let anyNoExpiry: Bool
    let anyOriginalDays: Bool
    /// 模板开了「使用制备功能」或「扫描二维码二次制备」→ 所有层级的原始保质期相关控件都禁用。
    let templateLocksExpiry: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("名称") {
                    TextField("点击输入名称", text: $node.name)
                }

                Section {
                    Toggle("设最佳使用时间", isOn: Binding(
                        get: { node.days != nil },
                        set: { on in
                            node.days = on ? (node.days ?? 3) : nil
                        }
                    ))
                    if node.days != nil {
                        Stepper(value: Binding(
                            get: { node.days ?? 3 },
                            set: { node.days = max(1, $0) }
                        ), in: 1...365) {
                            HStack {
                                Text("最佳天数")
                                Spacer()
                                Text("\(node.days ?? 3) 天")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    // ★★★ 2026-10-20（用户）：「最佳使用时间下面**也增加无保质期和设原始保质期**，
                    //   功能和前面一样」+ 二选一互斥（跨层级生效）。
                    Toggle("无保质期", isOn: $node.noExpiry)
                        .disabled(anyOriginalDays || templateLocksExpiry)

                    Toggle("设原始保质期", isOn: Binding(
                        get: { node.originalDays != nil },
                        set: { on in node.originalDays = on ? (node.originalDays ?? 30) : nil }
                    ))
                    .disabled(anyNoExpiry || templateLocksExpiry)

                    if let days = node.originalDays {
                        Stepper(value: Binding(
                            get: { days },
                            set: { node.originalDays = max(1, $0) }
                        ), in: 1...3650) {
                            HStack {
                                Text("原始天数")
                                Spacer()
                                Text("\(days) 天")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .disabled(templateLocksExpiry)
                    }
                } header: {
                    Text("时间")
                } footer: {
                    Text("打印时按**最深的选中层**往上找：这一级设了就用它，没设就继承上级。")
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
