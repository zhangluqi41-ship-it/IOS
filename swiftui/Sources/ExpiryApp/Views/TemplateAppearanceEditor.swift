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
        // ★★★ 2026-10-19（用户）：「这个（预览）可以**锁定在这里，不跟下面的滚动一起动**」
        //   ➜ 预览从 `List` 里拿出来，做成导航栏下方的固定块；下面的图标/色板独立滚动。
        VStack(spacing: 0) {
            previewCard
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Color(.systemGroupedBackground))

            // ★★★ 2026-10-19（用户）：「这个界面的**滚动很不流畅**」
            //   ➜ 根因不是"没用官方工具"（List / LazyVGrid / Section 全是系统的），
            //     而是 **`List` 里嵌 `LazyVGrid`（40 个 Button）** 这个错误组合：
            //     List 的行高必须在布局阶段一次性算出来 → 40 个图标全部**同时创建**，
            //     而且 List 的行有额外的 cell 包装与阴影，滚动时每帧都要重新测量。
            //   ➜ 换成 **`ScrollView` + `LazyVStack`**：只有滚到眼前的那一块才构建，
            //     并且没有 List 的 cell 开销。
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    // ── 图标 ──
                    group(title: "图标") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8),
                                  spacing: 12) {
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
                    }

                    group(title: "图标块背景色") {
                        colorRow(selection: $tintName)
                    }

                    group(title: "图标颜色") {
                        colorRow(selection: $iconColorName)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("图标与颜色")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    /// 一组内容（标题 + 圆角卡片）。自己画卡片，不用 List 的 Section。
    @ViewBuilder
    private func group<Content: View>(title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14))
        }
    }

    /// 固定在顶部的预览卡片（就是磁贴上的那个方块）。
    private var previewCard: some View {
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
        .padding(.vertical, 22)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    /// 一排色点（选中的带描边 + 对勾）+ **系统调色盘**。
    @ViewBuilder
    private func colorRow(selection: Binding<String>) -> some View {
        VStack(spacing: 12) {
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

            // ★★★ 2026-10-22（用户）：「再加一个**调色盘功能**」——
            //   系统 `ColorPicker` 选任意颜色，存成 `#RRGGBB`（`CustomTemplate.color(named:)` 已支持解析）。
            ColorPicker("自定义颜色",
                        selection: Binding(
                            get: { CustomTemplate.color(named: selection.wrappedValue) },
                            set: { newValue in
                                if let hex = Self.hexString(from: newValue) {
                                    selection.wrappedValue = hex
                                }
                            }
                        ),
                        supportsOpacity: false)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    /// `Color` → `#RRGGBB`（用 UIColor 取分量，避免依赖平台差异）。
    static func hexString(from color: Color) -> String? {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }

    /// ★★★ 2026-10-22（用户）：「**图标能否增加全一些**」→ 40 → **88 个**（11 行 × 8）。
    static let iconChoices = [
        // 原有 40
        "square.grid.2x2", "shippingbox", "drop", "leaf", "flame", "snowflake",
        "cup.and.saucer", "carrot", "fish", "birthday.cake", "fork.knife", "barcode",
        "thermometer", "clock", "tag", "bag", "cart", "archivebox", "tray", "cylinder",
        "cube", "square.stack", "mug", "wineglass", "basket", "heart", "star", "bolt",
        "sparkles", "square.grid.3x3", "circle.hexagongrid", "doc.text", "checklist",
        "bookmark", "flag", "paintpalette", "scissors", "wrench", "hammer", "takeoutbag.and.cup.and.straw",
        // 食物 / 饮品（.fill 变体）
        "cup.and.saucer.fill", "wineglass.fill", "mug.fill", "carrot.fill",
        "leaf.fill", "fish.fill", "birthday.cake.fill", "takeoutbag.and.cup.and.straw.fill",
        // 食材 / 农业
        "tree", "camera.macro", "tortoise", "bird", "lizard",
        // 时间 / 计量
        "timer", "hourglass", "calendar", "alarm", "stopwatch",
        "gauge", "ruler", "scalemass", "chart.bar", "chart.pie",
        // 包装 / 工具
        "box.truck", "shippingbox.fill", "cart.fill", "basket.fill",
        "printer", "qrcode", "barcode.viewfinder", "doc.viewfinder", "folder",
        // 标记 / 其他
        "pin", "mappin", "location", "house", "building.2",
        "wrench.and.screwdriver", "paintbrush", "highlighter", "pencil", "square.and.pencil",
    ]
}
