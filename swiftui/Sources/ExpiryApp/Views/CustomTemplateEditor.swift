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
                Section("模板名称") {
                    TextField("如：星巴克果汁", text: $draft.name)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(Self.iconChoices, id: \.self) { name in
                            Button { draft.icon = name } label: {
                                Image(systemName: name)
                                    .font(.system(size: 17))
                                    .frame(width: 34, height: 34)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(draft.icon == name
                                                  ? Color.accentColor.opacity(0.22)
                                                  : Color(uiColor: .tertiarySystemFill))
                                    )
                                    .foregroundStyle(draft.icon == name ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
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
                    Text("缩进表示层级（最多 3 层子菜单）。每一级都可以设建议天数；"
                         + "打印时选中哪一级，就用那一级的建议天数（从打印当天往后算）。")
                }
            }
            .navigationTitle(original == nil ? "新建模板" : "编辑模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || draft.nodes.isEmpty)
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
        var pathKey: String { path.map(String.init).joined("/") }
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

    static let iconChoices = [
        "square.grid.2x2", "shippingbox", "drop", "leaf",
        "flame", "snowflake", "cup.and.saucer", "carrot",
        "fish", "birthday.cake", "takeoutbag.and.cup.and.straw", "fork.knife",
        "thermometer", "clock", "tag", "barcode",
    ]
}

/// 节点在树里的位置（索引路径），用作 sheet 的 item。
struct NodePath: Identifiable, Hashable {
    let indices: [Int]
    var id: String { indices.map(String.init).joined("/") }
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
                    TextField("如：桃浓缩汁", text: $node.name)
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
                } header: {
                    Text("建议时间")
                } footer: {
                    if canSetDays {
                        Text("打印时选中这一级（或它的下级）就用这个天数，从打印当天往后算。")
                    } else {
                        Text("这个模板的天数设在第 \(lockedLevel ?? 0) 层，这一层不用再设"
                             + "（下级会继承上面的天数）。")
                    }
                }

                if canAddChild {
                    Section("子菜单（第 \(level + 1) 层）") {
                        ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                            HStack {
                                Text(child.name.isEmpty ? "未命名" : child.name)
                                Spacer()
                                if let days = child.days {
                                    Text("\(days) 天").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    node.children.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .tint(.red)
                            }
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
