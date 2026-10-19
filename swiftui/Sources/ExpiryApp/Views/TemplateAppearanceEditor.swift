import SwiftUI

// MARK: - 模板外观（图标 + 两个颜色）
//
// ★★★ 2026-10-19（用户）：「图标设置占用太大了，可以**单独开一个子菜单**来设置，
//   同时在设置颜色时**增加一个预览**」
//
//   ➜ 原来 40 个图标（5 排）+ 两组色板全塞在主页面，把"菜单"挤到很下面。
//   ➜ 现在收进这个子页面：**顶部实时预览** + 图标网格 + 两个色板。
//   ➜ 主页面只留一行入口（带小预览）。

struct TemplateAppearanceEditor: View {
    @Binding var icon: String
    @Binding var tintName: String
    @Binding var iconColorName: String
    /// 预览里显示的标题（模板名，可能是空的）。
    let previewTitle: String

    var body: some View {
        List {
            // ── 实时预览：就是磁贴上的那个圆角方块 ──
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(CustomTemplate.color(named: iconColorName))
                            .frame(width: 52, height: 52)
                            .background(
                                CustomTemplate.color(named: tintName),
                                in: RoundedRectangle(cornerRadius: 13)
                            )
                        Text(previewTitle.isEmpty ? "模板名称" : previewTitle)
                            .font(.headline)
                            .foregroundStyle(previewTitle.isEmpty ? .secondary : .primary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            // ── 图标 ──
            Section("图标") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                    ForEach(Self.iconChoices, id: \.self) { name in
                        Button {
                            icon = name
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 17))
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(icon == name
                                              ? Color.accentColor.opacity(0.22)
                                              : Color(uiColor: .tertiarySystemFill))
                                )
                                .foregroundStyle(icon == name ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("图标块背景色") {
                colorRow(selection: $tintName)
            }

            Section("图标颜色") {
                colorRow(selection: $iconColorName)
            }
        }
        .navigationTitle("图标与颜色")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 一排色点（选中的带描边 + 对勾）。
    @ViewBuilder
    private func colorRow(selection: Binding<String>) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
            ForEach(CustomTemplate.colorChoices, id: \.self) { name in
                Button {
                    selection.wrappedValue = name
                } label: {
                    Circle()
                        .fill(CustomTemplate.color(named: name))
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle().strokeBorder(
                                Color.primary.opacity(selection.wrappedValue == name ? 0.9 : 0.12),
                                lineWidth: selection.wrappedValue == name ? 2 : 1
                            )
                        }
                        .overlay {
                            if selection.wrappedValue == name {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(name == "white" || name == "yellow"
                                                     ? Color.black : Color.white)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    /// 40 个可选图标（5 行 × 8）。
    static let iconChoices = [
        "square.grid.2x2", "shippingbox", "drop", "leaf", "flame", "snowflake",
        "cup.and.saucer", "carrot", "fish", "birthday.cake", "fork.knife", "barcode",
        "thermometer", "clock", "tag", "bag", "cart", "archivebox", "tray", "cylinder",
        "cube", "square.stack", "mug", "wineglass", "basket", "heart", "star", "bolt",
        "sparkles", "square.grid.3x3", "circle.hexagongrid", "doc.text", "checklist",
        "bookmark", "flag", "paintpalette", "scissors", "wrench", "hammer", "takeoutbag.and.cup.and.straw",
    ]
}
