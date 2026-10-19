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
    @State private var scannedTitle: String?
    @State private var scannedBestBefore: Date?
    /// ★ 2026-10-19（用户）：「增加**无原始保质期**选项，如果无，自动填写最佳保质期 2099.12.31」
    @State private var noExpiry = false
    @FocusState private var focus: AnyHashable?

    /// 从**扫码 Tab** 进来时带着原标签信息（二次制备）。
    /// - Parameters:
    ///   - presetSourceTitle: 原标签标题（扫到的）
    ///   - presetSourceBest: 原标签的最佳使用时间
    init(template: CustomTemplate,
         presetSourceTitle: String? = nil,
         presetSourceBest: Date? = nil) {
        self.template = template
        _scannedTitle = State(initialValue: presetSourceTitle)
        _scannedBestBefore = State(initialValue: presetSourceBest)
    }

    var body: some View {
        List {
            // ★★★ 2026-10-19（用户）：「这个功能不是这样的，他应该是**扫描已经打印出来的
            //   某个二维码**二次制备…… 这个扫描功能应该是在 **tabbar 的扫描里**完成后弹出来的，
            //   参考康普茶二发」+「在效期打印界面，如果不编辑或者删除模板，**他应该是被隐藏起来的**」
            //   ➜ 打印页这里**不再有任何"扫描原标签"入口**；二次制备改由扫码 Tab 触发。
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
                Toggle("无原始保质期", isOn: $noExpiry)

                LabelDatePicker(title: "原始保质期", date: $expireDate)
                    .disabled(noExpiry)
                if !noExpiry {
                    QuickDateChips(selection: $expireDate)
                }

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
        .onChange(of: noExpiry) { _, isOn in
            guard isOn else { return }
            // 无原始保质期 → 最佳使用时间固定填 2099/12/31（表示"无期限"）。
            var comps = DateComponents()
            comps.year = 2099
            comps.month = 12
            comps.day = 31
            comps.hour = 23
            comps.minute = 59
            if let far = AppCalendar.shared.date(from: comps) {
                withAnimation(.default) {
                    bestDate = far
                    expireDate = far
                }
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
    /// 原始保质期该用几天。
    private var appliedDays: Int? {
        // 懒人一键保质期 = 模板级统一的原始保质期。
        if let lazy = template.lazyDays { return lazy }
        let chain = chosenChain()
        guard !chain.isEmpty else { return nil }
        return chain.reversed().compactMap(\.days).first ?? template.defaultDays
    }

    /// 最佳使用时间该用几天。
    private var appliedBestDays: Int? {
        // 模板级「设建议天数」在这里当统一的**最佳**天数。
        if let uniform = template.defaultDays { return uniform }
        let chain = chosenChain()
        guard !chain.isEmpty else { return nil }
        return chain.reversed().compactMap(\.bestDays).first
            ?? chain.reversed().compactMap(\.days).first
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

    /// 标签标题的唯一来源。
    ///
    /// ★ 2026-10-19（用户）命名规则（合并后的唯一实现）：
    ///   · **没有菜单** → `模板名-手输物料名`（"冷冻-五花肉"）
    ///   · **有菜单** → 默认 `第一层-第二层…`（"猪肉-五花肉"）；
    ///     开了「命名带模板名称」→ `模板名-第一层-第二层…`（"冷冻-猪肉-五花肉"）
    private func makeTitle(chain: [CustomNode]) -> String {
        // ★★★ 2026-10-19（用户）：「还是增加名称自定义吧，**顺序啊、"‑"用哪些名称连接都可以自己来选择**」
        //   ➜ `titleParts` 非空时，严格按用户排的顺序取字段；
        //     为空则走旧的默认规则（兼容老模板）。
        if !template.titleParts.isEmpty {
            var values: [String] = []
            for part in template.titleParts {
                let value: String
                switch part {
                case .template:
                    value = template.name
                case .level1:
                    // ★★★ 2026-10-19（用户）：「**第一层有选项则第一层就是选项，
                    //   若无选项，那第一层就应该是打字输入的信息**」
                    //   ➜ 空菜单模板里「第一层」= 手输物料名（否则标题会空掉、标签没信息）。
                    if chain.count > 0 {
                        value = chain[0].name
                    } else {
                        value = materialName.trimmingCharacters(in: .whitespaces)
                    }
                case .level2:
                    value = chain.count > 1 ? chain[1].name : ""
                case .level3:
                    value = chain.count > 2 ? chain[2].name : ""
                case .manual:
                    value = materialName.trimmingCharacters(in: .whitespaces)
                case .source:
                    value = scannedTitle ?? ""
                }
                if !value.isEmpty { values.append(value) }
            }
            let result = values.joined(separator: template.titleSeparator)
            // ★ 兜底：规则里一个有效字段都没取到时，至少用手输名，别打出空标题。
            if result.isEmpty {
                return materialName.trimmingCharacters(in: .whitespaces)
            }
            return result
        }

        if template.nodes.isEmpty {
            let name = materialName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "" : "\(template.name)-\(name)"
        }
        guard !chain.isEmpty else { return "" }
        var parts = chain.map(\.name)
        if template.includeTemplateInTitle { parts.insert(template.name, at: 0) }
        return parts.joined(separator: "-")
    }

    /// 空菜单模板：标题 = 「模板名-物料名」，日期按模板级天数自动填。
    private func syncFromInput() {
        title = makeTitle(chain: [])
        let name = materialName.trimmingCharacters(in: .whitespaces)
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
        title = makeTitle(chain: chain)
        // 原始保质期
        if let days = appliedDays, days > 0 {
            expireDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        }
        // 最佳使用时间（没单独设就跟原始一致）
        if let best = appliedBestDays ?? appliedDays, best > 0 {
            bestDate = Calendar.current.date(byAdding: .day, value: best, to: Date()) ?? Date()
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
                                                      doneDays: template.defaultDays ?? 3,
                                                      sourceBestBefore: sourceBest,
                                                      maker: makerFinal)
        } else if template.usePrep {
            // 完成天数复用模板级「建议天数」（没设就按 3 天）。
            // 完成天数 = 原始保质期（懒人天数优先），不是最佳天数。
            data = LabelTemplate.buildCustomPrep(title: name, now: now,
                                                 doneDays: template.lazyDays ?? template.defaultDays ?? 3,
                                                 bestBefore: bestDate,
                                                 maker: makerFinal)
        } else {
            data = LabelTemplate.buildGeneric(title: name, now: now,
                                              expireDate: expireDate,
                                              bestBefore: bestDate,
                                              maker: makerFinal)
        }
        let record = LabelTemplate.makeRecord(kind: .generic, data: data, createdAt: now,
                                              expireAt: expireDate, bestBefore: min(bestDate, expireDate),
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
