import SwiftUI

// MARK: - 自定义模板：打印页
//
// ★★★ 2026-10-19（用户）：
//   「不需要这么多层的选项，应该点开后**就是**『肉类』那种类型的页面，
//    然后菜单应该是**三层树形结构**；
//    我刚新建的模板『星巴克果汁』应该在这个红框（导航标题）里，而不是在名称里」
//
// 所以这块**不用逐级导航**（原来的 CustomTemplatePicker 已废弃）：
//   · 导航标题 = **模板名**（"星巴克果汁"）；
//   · 页面里一个 **`Menu` 下拉**，把整棵树展平、用缩进表示层级（和「肉类」的品类菜单同款）；
//   · 选到某一项 → 自动填标题（"星巴克果汁-桃浓缩汁"）和日期（今天 + 该级天数）；
//   · 下面是日期 / 制作人 / 打印，与通用页完全一致。

struct CustomTemplatePage: View {
    let template: CustomTemplate

    @State private var picked: NodeItem?
    @State private var title = ""
    @State private var expireDate = Date()
    @State private var bestDate = Date()
    @State private var maker = Prefs.lastMaker
    @State private var showPickerAlert = false
    @FocusState private var focus: AnyHashable?

    var body: some View {
        List {
            Section {
                Menu {
                    ForEach(flattened) { item in
                        Button(item.display) { pick(item) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: template.icon)
                            .foregroundStyle(Theme.brand)
                            .frame(width: 22)
                        Text(picked?.path.joined(separator: "-") ?? "选择品类")
                            .foregroundStyle(picked == nil ? Color.secondary : Color.primary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("品类")
            }

            Section {
                LabelDatePicker(title: "原始保质期", date: $expireDate)
                QuickDateChips(selection: $expireDate)

                LabelDatePicker(title: "最佳使用时间", date: $bestDate)
                QuickDateChips(selection: $bestDate)
            } header: {
                Text("日期")
            } footer: {
                if let item = picked, let days = days(for: item) {
                    Text("已按「\(item.node.name)」的建议 \(days) 天自动填写，可手动改。")
                }
            }

            Section {
                MakerField(maker: $maker, focused: $focus)
            } footer: {
                Text("会记住上次填写的操作人")
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissible(focus: $focus)
        .modifier(LabelActions(build: buildDraft))
        .alert("请先选择品类", isPresented: $showPickerAlert) {
            Button("好", role: .cancel) {}
        }
    }

    // MARK: 菜单项

    /// 展平后的菜单项（缩进用全角空格，`Menu` 里没有真正的层级视觉）。
    private var flattened: [NodeItem] { flatten(template.nodes) }

    private func flatten(_ nodes: [CustomNode], path: [String] = [],
                         ancestors: [CustomNode] = [], level: Int = 0) -> [NodeItem] {
        nodes.flatMap { node -> [NodeItem] in
            let p = path + [node.name]
            let selfItem = NodeItem(node: node, path: p, ancestors: ancestors, level: level)
            return [selfItem] + flatten(node.children, path: p,
                                        ancestors: ancestors + [node],
                                        level: level + 1)
        }
    }

    /// 该用几天：**自己的天数优先，没有就向上找最近祖先**。
    ///
    /// ★ 用户规则：一个模板里天数只出现在某一层（如"冷冻"），
    ///   往下任何部位都继承它；所以选到"五花"时拿到的是"冷冻"的天数。
    private func days(for item: NodeItem) -> Int? {
        if let own = item.node.days { return own }
        return item.ancestors.reversed().compactMap(\.days).first
    }

    private func pick(_ item: NodeItem) {
        picked = item
        title = item.path.joined(separator: "-")
        if let days = days(for: item), days > 0 {
            let due = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
            expireDate = due
            bestDate = due
        }
    }

    // MARK: 打印

    private func buildDraft() -> LabelDraft? {
        let name = LabelTemplate.clamp(title)
        guard !name.isEmpty else {
            showPickerAlert = true
            return nil
        }
        let makerFinal = MakerField.finalize(maker)
        let now = Date()
        // ★ 版式复用「通用效期」（开封时间 / 原始保质期 / 最佳使用时间）——
        //   用户要的就是"和肉类那种页面一样"，只是标题来自自定义模板的路径。
        let data = LabelTemplate.buildGeneric(title: name, now: now,
                                              expireDate: expireDate,
                                              bestBefore: bestDate,
                                              maker: makerFinal)
        let record = LabelTemplate.makeRecord(kind: .generic, data: data, createdAt: now,
                                              expireAt: expireDate, bestBefore: bestDate,
                                              maker: makerFinal)
        return LabelDraft(data: data, record: record)
    }
}

/// 展平后的一个菜单项。
struct NodeItem: Identifiable {
    let node: CustomNode
    let path: [String]
    /// 从根到**父级**的链（用于天数继承：自己的没有就往上找）。
    let ancestors: [CustomNode]
    let level: Int

    var id: UUID { node.id }

    /// 菜单里显示的文字：缩进 + 名字 +（天数）。
    var display: String {
        var text = String(repeating: "　", count: level) + node.name
        if let days = node.days { text += "（\(days) 天）" }
        return text
    }
}

#Preview {
    NavigationStack {
        CustomTemplatePage(template: CustomTemplate(
            name: "星巴克果汁",
            icon: "cup.and.saucer",
            nodes: [
                CustomNode(name: "桃浓缩汁", days: 5),
                CustomNode(name: "果汁杯", days: 1, children: [
                    CustomNode(name: "冷萃", days: 2),
                ]),
            ]
        ))
    }
}
