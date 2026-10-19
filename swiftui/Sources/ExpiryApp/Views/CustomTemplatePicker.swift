import SwiftUI

// MARK: - 自定义模板：逐级选择
//
// ★★★ 2026-10-19 新增（第 3 步）。
//
// 口径（已确认）：
//   · 每一级都可能设了「建议天数」，**选到哪级就用哪级的天数**；
//   · 叶子节点 → 点一下直接进打印页；
//   · 有子项的节点 → 进入下一页；如果它自己有天数，页面顶部会有
//     「用「猪肉」（3 天）」入口（用户可以选自己，也可以继续往下走）。

struct CustomTemplatePicker: View {
    let template: CustomTemplate

    var body: some View {
        CustomNodePages(nodes: template.nodes, path: [template.name])
            .navigationTitle(template.name)
    }
}

/// 一页菜单（递归：子项还是它自己）。
struct CustomNodePages: View {
    let nodes: [CustomNode]
    /// 从模板名开始、**到本页为止**的路径（不含本页要列出的项）。
    let path: [String]

    var body: some View {
        List {
            ForEach(nodes) { node in
                if node.children.isEmpty {
                    // 叶子：直接去打印
                    NavigationLink {
                        GenericTemplateView(presetTitle: joined(node),
                                            presetDays: node.days)
                    } label: {
                        row(node, suffix: node.days.map { "\($0) 天" })
                    }
                } else {
                    NavigationLink {
                        // ★ `AnyView` 打断递归（`CustomNodePages` ↔ `nodePage`，否则类型无限展开）。
                        AnyView(nodePage(node))
                    } label: {
                        row(node, suffix: node.days.map { "\($0) 天" })
                    }
                }
            }
        }
    }

    /// 有子项的节点：本页顶部给它自己一个「用这一项」入口，下面是子项。
    private func nodePage(_ node: CustomNode) -> some View {
        List {
            if let days = node.days {
                Section {
                    NavigationLink {
                        GenericTemplateView(presetTitle: joined(node), presetDays: days)
                    } label: {
                        Label("用「\(node.name)」（\(days) 天）", systemImage: "printer")
                    }
                }
            }
            Section("子项") {
                CustomNodePages(nodes: node.children, path: path + [node.name])
            }
        }
        .navigationTitle(node.name)
    }

    /// 完整标题：父路径 + 自己（用 `-` 连接）。
    private func joined(_ node: CustomNode) -> String {
        (path + [node.name]).joined(separator: "-")
    }

    private func row(_ node: CustomNode, suffix: String?) -> some View {
        HStack(spacing: 8) {
            Text(node.name)
            Spacer(minLength: 8)
            if let suffix {
                Text(suffix)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CustomTemplatePicker(template: CustomTemplate(
            name: "解冻",
            nodes: [
                CustomNode(name: "猪肉", days: 3, children: [
                    CustomNode(name: "梅花肉", days: 2),
                    CustomNode(name: "五花肉", days: 3),
                ]),
                CustomNode(name: "牛肉", days: 4),
            ]
        ))
    }
}
