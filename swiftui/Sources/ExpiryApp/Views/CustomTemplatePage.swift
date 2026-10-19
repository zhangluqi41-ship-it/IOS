import SwiftUI

// MARK: - 自定义模板：打印页
//
// ★★★ 2026-10-19（用户，第三次纠正）：
//   「(整棵树塞一个菜单) 不应该这样显示，他应该是（肉类页）**这样的菜单选项**存在」
//
// 肉类页的品类是**每一层一个独立的菜单行**：
//     保存类型        冷冻 ⌄
//     肉类            鸡肉 ⌄
//     部位            猪肉 ⌄
//
// 所以这里也改成**逐层 Picker**：选完上一层，下一层才出现；
// 每层标题 = 上一层的名字（第一层叫「品类」）。
// 选到某一层 → 标题 = 模板名 + 路径，日期 = 今天 + 该层（或最近祖先）的天数。

struct CustomTemplatePage: View {
    let template: CustomTemplate

    /// 每一层选中的节点 id（nil = 未选）。层级上限见 `CustomNode.maxDepth`。
    @State private var selections: [UUID?] = Array(repeating: nil, count: CustomNode.maxDepth)
    @State private var title = ""
    /// 空菜单模板时，用户直接输入的物料名称。
    @State private var materialName = ""
    @State private var expireDate = Date()
    @State private var bestDate = Date()
    @State private var maker = Prefs.lastMaker
    @State private var showPickerAlert = false
    /// ★ 二次制备：扫到的原标签信息 + sheet 开关。
    @State private var showSecondaryScan = false
    @State private var scannedTitle: String?
    @State private var scannedBestBefore: Date?
    @FocusState private var focus: AnyHashable?

    var body: some View {
        List {
            // ★ 2026-10-19（用户）：「扫描二维码二次制备」——开启后这里可以扫原标签。
            if template.useSecondary {
                Section {
                    Button {
                        showSecondaryScan = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundStyle(Theme.brand)
                                .frame(width: 22)
                            if let scannedTitle {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("已扫描：\(scannedTitle)")
                                        .foregroundStyle(.primary)
                                    if let date = scannedBestBefore {
                                        Text("最佳使用时间 \(date.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                Text("扫描原标签")
                                    .foregroundStyle(Theme.brand)
                            }
                            Spacer(minLength: 8)
                            if scannedTitle != nil {
                                Image(systemName: "arrow.clockwise")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("扫到后：完成时间 = 扫描时刻 + \(template.secondaryDays) 天，最佳使用时间沿用原标签。")
                }
            }

            if template.nodes.isEmpty {
                // ★★★ 2026-10-19（用户）：「不添加菜单，就设置成**通用效期那种直接输入物料名称**的模板，
                //   命名规则为『定义的模板名称』-『直接输入的物料名称』」
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: template.icon)
                            .foregroundStyle(Theme.brand)
                            .frame(width: 22)
                        TextField("点击输入物料名称", text: $materialName)
                            .onChange(of: materialName) { _, _ in syncFromInput() }
                    }
                } header: {
                    Text("物料名称")
                }
            } else {
            Section {
                // ★ 逐层菜单：和「肉类」的「保存类型 / 肉类 / 部位」同一个样子。
                ForEach(visibleLevels, id: \.self) { level in
                    Picker(levelTitle(level), selection: binding(for: level)) {
                        Text("未选择").tag(UUID?.none)
                        ForEach(options(at: level)) { node in
                            // ★ 2026-10-19（用户）：「**不要在这里显示天数**」——
                            //   和「肉类」页一样，菜单里只放名字（天数在下面的按钮里体现）。
                            Text(node.name.isEmpty ? "未命名" : node.name)
                                .tag(Optional(node.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                // ★ 和「肉类」页同款：一行蓝色「按推荐填日期」，
                //   右侧灰字显示推荐的天数；手动改过日期后可点它恢复。
                if let days = appliedDays {
                    Button {
                        applyRecommendedDates()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wand.and.stars")
                            Text("按推荐填日期")
                            Spacer(minLength: 8)
                            Text("保质期 +\(days) 天 · 最佳 +\(days) 天")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("品类")
            }
            }

            Section {
                LabelDatePicker(title: "原始保质期", date: $expireDate)
                QuickDateChips(selection: $expireDate)

                LabelDatePicker(title: "最佳使用时间", date: $bestDate)
                QuickDateChips(selection: $bestDate)

                // 只有真的算出天数才显示这一行（没选品类时完全不占位）。
                if let days = appliedDays {
                    Text("已按「\(chosenChain().last?.name ?? "")」的建议 \(days) 天自动填写，可手动改。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("日期")
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
        .onChange(of: selections) { _, _ in syncFromSelection() }
        .sheet(isPresented: $showSecondaryScan) {
            SecondaryScanView { title, best in
                scannedTitle = title
                scannedBestBefore = best
            }
        }
        .alert(template.nodes.isEmpty ? "请先输入物料名称" : "请先选择品类",
               isPresented: $showPickerAlert) {
            Button("好", role: .cancel) {}
        }
    }

    // MARK: 层级

    /// 第 `level` 层的候选项。
    private func options(at level: Int) -> [CustomNode] {
        if level == 0 { return template.nodes }
        guard let parent = pickedNode(at: level - 1) else { return [] }
        return parent.children
    }

    /// 第 `level` 层已选的节点。
    private func pickedNode(at level: Int) -> CustomNode? {
        guard level >= 0, level < selections.count, let id = selections[level] else { return nil }
        return options(at: level).first { $0.id == id }
    }

    /// 从第 0 层到**最深已选**的节点链。
    private func chosenChain() -> [CustomNode] {
        var result: [CustomNode] = []
        for level in 0..<selections.count {
            guard let node = pickedNode(at: level) else { break }
            result.append(node)
        }
        return result
    }

    /// 当前应该显示几层：
    /// 第 0 层永远显示；第 N 层在「第 N-1 层已选 **且它还有子项**」时才出现。
    private var visibleLevels: [Int] {
        var result: [Int] = [0]
        for level in 1..<CustomNode.maxDepth {
            guard let parent = pickedNode(at: level - 1), !parent.children.isEmpty else { break }
            result.append(level)
        }
        return result
    }

    /// 每层菜单左边的标题：第 0 层「品类」，之后用上一层的名字（和肉类页同理）。
    private func levelTitle(_ level: Int) -> String {
        if level == 0 { return "品类" }
        return pickedNode(at: level - 1)?.name ?? "第 \(level + 1) 层"
    }

    private func binding(for level: Int) -> Binding<UUID?> {
        Binding(
            get: { level < selections.count ? selections[level] : nil },
            set: { newValue in
                guard level < selections.count else { return }
                selections[level] = newValue
                // 换了这一层，下面各层全部清空（避免残留不匹配的子项）。
                for deeper in (level + 1)..<selections.count { selections[deeper] = nil }
            }
        )
    }

    /// 选中的天数：**自己的优先，没有就往上找最近祖先**，最后兜底模板默认天数。
    private var appliedDays: Int? {
        let chain = chosenChain()
        guard !chain.isEmpty else { return nil }
        return chain.reversed().compactMap(\.days).first ?? template.defaultDays
    }

    /// 点「按推荐填日期」：把两个日期重置成「今天 + 推荐天数」。
    private func applyRecommendedDates() {
        guard let days = appliedDays, days > 0 else { return }
        let due = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        withAnimation(.default) {
            expireDate = due
            bestDate = due
        }
    }

    /// 空菜单模板：标题 = 「模板名-物料名」，日期按模板级天数自动填。
    private func syncFromInput() {
        let name = materialName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            title = ""
        } else {
            title = "\(template.name)-\(name)"
        }
        if let days = template.defaultDays, days > 0, !name.isEmpty {
            let due = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
            expireDate = due
            bestDate = due
        }
    }

    /// 选择变化后：刷新标题 + 日期。
    private func syncFromSelection() {
        let chain = chosenChain()
        guard !chain.isEmpty else {
            title = ""
            return
        }
        // ★★★ 2026-10-19（用户）：「**建了菜单后不需要模板名**」
        //   ➜ 有菜单时标题 = 纯菜单路径（"猪肉-五花肉"），模板名只作为**页面标题**显示。
        //   ➜ 只有空菜单时才用「模板名-手输名」。
        title = chain.map(\.name).joined(separator: "-")
        if let days = appliedDays, days > 0 {
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
        // ★ 2026-10-19（用户）：「使用制备功能」→ 三行改成 制备/完成/最佳。
        let data: LabelData
        if template.useSecondary, let sourceTitle = scannedTitle, let sourceBest = scannedBestBefore {
            // ★ 二次制备：标题 = 原标签标题-当前选择的名称；完成 = 现在 + N 天；最佳沿用原标签。
            data = LabelTemplate.buildCustomSecondary(sourceTitle: sourceTitle,
                                                      suffix: title,
                                                      now: now,
                                                      doneDays: template.secondaryDays,
                                                      sourceBestBefore: sourceBest,
                                                      maker: makerFinal)
        } else if template.usePrep {
            // 完成天数复用模板级「建议天数」（没设就按 3 天）。
            data = LabelTemplate.buildCustomPrep(title: name, now: now,
                                                 doneDays: template.defaultDays ?? 3,
                                                 bestBefore: bestDate,
                                                 maker: makerFinal)
        } else {
            data = LabelTemplate.buildGeneric(title: name, now: now,
                                              expireDate: expireDate,
                                              bestBefore: bestDate,
                                              maker: makerFinal)
        }
        let record = LabelTemplate.makeRecord(kind: .generic, data: data, createdAt: now,
                                              expireAt: expireDate, bestBefore: bestDate,
                                              maker: makerFinal)
        return LabelDraft(data: data, record: record)
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
