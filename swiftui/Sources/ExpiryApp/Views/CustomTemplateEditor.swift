import SwiftUI

// MARK: - 自定义模板编辑器
//
// ★★★ 2026-10-19 新增（第 2 步：编辑器）。
//
// 交互口径：
//   · 顶部改模板名 / 图标 / 颜色；
//   · 下面是**菜单树**：每一行是一个节点，点进去改名字、设建议天数、加子项；
//   · 层级上限 3 层子菜单（`CustomNode.maxDepth`），到了最深层不再显示"添加子项"。

struct CustomTemplateEditor: View {
    /// 传入 nil = 新建。
    let original: CustomTemplate?
    let onSave: (CustomTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomTemplate
    @State private var iconPickerOpen = false

    init(original: CustomTemplate?, onSave: @escaping (CustomTemplate) -> Void) {
        self.original = original
        self.onSave = onSave
        _draft = State(initialValue: original ?? CustomTemplate(name: ""))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("模板名称") {
                    TextField("如：解冻", text: $draft.name)
                }

                Section("图标") {
                    // 一排常用图标，点选即可（不做图标库，够用就行）。
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(Self.iconChoices, id: \.self) { name in
                            Button {
                                draft.icon = name
                            } label: {
                                Image(systemName: name)
                                    .font(.system(size: 17))
                                    .frame(width: 34, height: 34)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(draft.icon == name
                                                  ? Color.accentColor.opacity(0.22)
                                                  : Color(.tertiarySystemFill))
                                    )
                                    .foregroundStyle(draft.icon == name ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    CustomNodeListEditor(nodes: $draft.nodes, level: 1)
                } header: {
                    Text("菜单")
                } footer: {
                    Text("每一级都可以设「建议天数」；打印时选中哪一级，就用那一级的天数"
                         + "（从**打印当天**往后算）。最多 3 层子菜单。")
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
        }
    }

    /// 可选的图标（够覆盖常见物料就行）。
    static let iconChoices = [
        "square.grid.2x2", "shippingbox", "drop", "leaf",
        "flame", "snowflake", "cup.and.saucer", "carrot",
        "fish", "birthday.cake", "takeoutbag.and.cup.and.straw", "fork.knife",
        "thermometer", "clock", "tag", "barcode",
    ]
}

// MARK: - 节点列表（可递归）

struct CustomNodeListEditor: View {
    @Binding var nodes: [CustomNode]
    let level: Int

    var body: some View {
        ForEach($nodes) { $node in
            NavigationLink {
                // ★ 必须用 `AnyView` 打断递归：`CustomNodeListEditor` ↔ `CustomNodeEditor`
                //   互相嵌套，SwiftUI 的 View 是泛型，直接写会**类型无限展开**（编译不过）。
                AnyView(CustomNodeEditor(node: $node, level: level))
            } label: {
                HStack(spacing: 8) {
                    Text(node.name.isEmpty ? "未命名" : node.name)
                        .foregroundStyle(node.name.isEmpty ? .secondary : .primary)
                    Spacer(minLength: 8)
                    if let days = node.days {
                        Text("\(days) 天")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !node.children.isEmpty {
                        Text("\(node.children.count) 子项")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .onDelete { offsets in nodes.remove(atOffsets: offsets) }

        Button {
            nodes.append(CustomNode(name: ""))
        } label: {
            Label("添加菜单项", systemImage: "plus.circle")
        }
    }
}

// MARK: - 单个节点的编辑

struct CustomNodeEditor: View {
    @Binding var node: CustomNode
    let level: Int

    var body: some View {
        List {
            Section("名称") {
                TextField("如：猪肉", text: $node.name)
            }

            Section {
                Toggle("设建议天数", isOn: Binding(
                    get: { node.days != nil },
                    set: { on in node.days = on ? (node.days ?? 3) : nil }
                ))
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
                Text("打印时选中这一级，就用这个天数（从打印当天往后算）。")
            }

            // 只有在还允许加深时才显示子菜单编辑（最多 3 层子菜单）。
            if level < CustomNode.maxDepth {
                Section("子菜单（第 \(level + 1) 级）") {
                    CustomNodeListEditor(nodes: $node.children, level: level + 1)
                }
            }
        }
        .navigationTitle(node.name.isEmpty ? "菜单项" : node.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    CustomTemplateEditor(original: nil) { _ in }
}
