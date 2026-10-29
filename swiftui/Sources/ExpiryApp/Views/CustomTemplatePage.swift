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
    /// ★ 2026-10-20（用户）：「开启扫码功能的模板**不应该有原始保质期，应该是承接扫到的码的原始信息**」
    ///   → 二次制备时原始保质期从原标签带过来，不让改。
    @State private var scannedExpire: Date?
    /// 原始二维码（"原材料已用完"要按它去找记录）。
    @State private var scannedSourceQR: String?
    /// ★ 2026-10-21（用户）：「还要确认**原材料是否用完**」
    @State private var markSourceUsed = false
    @FocusState private var focus: AnyHashable?

    /// 从**扫码 Tab** 进来时带着原标签信息（二次制备）。
    /// - Parameters:
    ///   - presetSourceTitle: 原标签标题（扫到的）
    ///   - presetSourceBest: 原标签的最佳使用时间
    init(template: CustomTemplate,
         presetSourceTitle: String? = nil,
         presetSourceBest: Date? = nil,
         presetSourceExpire: Date? = nil,
         presetSourceQR: String? = nil) {
        self.template = template
        _scannedTitle = State(initialValue: presetSourceTitle)
        _scannedBestBefore = State(initialValue: presetSourceBest)
        _scannedExpire = State(initialValue: presetSourceExpire)
        _scannedSourceQR = State(initialValue: presetSourceQR)
        _expireDate = State(initialValue: presetSourceExpire ?? Date())
    }

    var body: some View {
        List {
            // ★★★ 2026-10-19（用户）：「这个功能不是这样的，他应该是**扫描已经打印出来的
            //   某个二维码**二次制备…… 这个扫描功能应该是在 **tabbar 的扫描里**完成后弹出来的，
            //   参考康普茶二发」+「在效期打印界面，如果不编辑或者删除模板，**他应该是被隐藏起来的**」
            //   ➜ 打印页这里**不再有任何"扫描原标签"入口**；二次制备改由扫码 Tab 触发。
            if template.nodes.isEmpty && template.needsManualName {
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
            } else if !isSecondaryFlow {
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
                if let days = appliedBestDays {
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

            // ★★★ 2026-10-21（用户）：「还要确认**原材料是否用完**，不能完全套用新建模板，
            //   扫二维码模板就应该是这样」→ 顶部一块"原材料已用完" + 扫到的标签信息。
            if isSecondaryFlow {
                Section {
                    Toggle("原材料已用完", isOn: $markSourceUsed)
                } footer: {
                    if let source = scannedTitle {
                        Text("开启并打印后，会把效期管理里「\(source)」这条记录标记为已用完；关闭则不动它。")
                    }
                }

                Section {
                    if let source = scannedTitle {
                        LabeledContent("品名", value: source)
                    }
                    if let sourceExpire = scannedExpire {
                        LabeledContent("原始保质期", value: Self.dateText(sourceExpire))
                    }
                    if let sourceBest = scannedBestBefore {
                        LabeledContent("原最佳使用时间", value: Self.dateText(sourceBest))
                    }
                } header: {
                    Text("扫到的标签")
                } footer: {
                    Text("扫到后即进入续做流程，菜单里不会再出现这一项。")
                }
            }

            Section {
                // ★★★ 2026-10-22（用户）：「**开启制备功能但是没有完成时间，却有原始保质期**。
                //   系统存的也有问题，逻辑都是乱的」——
                //   制备模式的第一栏本来就该是**完成时间**（现在 + 制备天数），
                //   不是"原始保质期"。而且它由模板天数算出，不该让用户改。
                if template.usePrep {
                    LabelDatePicker(title: "完成时间", date: .constant(completionDate))
                        .disabled(true)
                } else {
                    // 二次制备 / 无保质期：原始保质期不允许改。
                    LabelDatePicker(title: "原始保质期", date: $expireDate)
                        .disabled(usesSourceExpire || isNoExpiry)
                    if !usesSourceExpire && !isNoExpiry {
                        QuickDateChips(selection: $expireDate)
                    }
                }

                // ★ 无保质期时，最佳使用时间也固定为 2099/12/31（不可改）。
                LabelDatePicker(title: "最佳使用时间", date: $bestDate)
                    .disabled(isNoExpiry)
                if !isNoExpiry {
                    QuickDateChips(selection: $bestDate)
                }

                if template.usePrep {
                    Text("完成时间 = 现在 + \(DurationFormat.short(days: template.prepDays))（制备天数）；"
                         + "最佳使用时间按「最佳天数」自动填写，可手动改。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if usesSourceExpire {
                    Text("二次制备：原始保质期承接原标签，不可修改。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let days = appliedBestDays {
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
        .modifier(LabelActions(build: buildDraft, onConfirmed: {
            // ★ 打印成功后才标记（失败不动记录）。
            guard markSourceUsed, let qr = scannedSourceQR,
                  let record = ExpiryStore.shared.records.first(where: { $0.qrText == qr })
            else { return }
            ExpiryStore.shared.markUsed(record)
        }))
        .onChange(of: selections) { _, _ in syncFromSelection() }
        .onAppear {
            // ★ 二次制备进来时 `title` 还是初始空串（没有选择动作，不会触发 onChange）→
            //   这里主动算一次，否则点打印会弹"请先输入物料名称"。
            if title.isEmpty {
                title = makeTitle(chain: chosenChain())
            }
            // ★★★ 2026-10-22（用户）：「新解冻制备功能开启，**最佳使用时间应该是 +3 天，
            //   这里只 +1 天**」——
            //   真因：`bestDate` 的初始值是 `Date()`（此刻），而 `syncFromSelection`
            //   只在 `onChange(of: selections)` 触发；二次制备从扫码直接进来、**没有选择动作**
            //   → `bestDate` 一直停在"此刻"，等于 +0 天。
            //   ➜ 进页面时按「最佳天数」补算一次（制备天数只用于「完成时间」）。
            // ★★★ 2026-10-22（用户）：「这里我选择了**无保质期**，那它保质期**应该是 2099年12月31日**」
            //   之前 `resolvedExpireDate` 只在点「按推荐填日期」时才调用，
            //   直接进页面（没点按钮）两个日期都停在"此刻" → 显示成今天。
            //   ➜ 进页面就按模板配置补算：无保质期 → 两个日期都置为 2099/12/31。
            if isNoExpiry {
                let far = Self.farFutureDate
                if bestDate <= Date().addingTimeInterval(60) { bestDate = far }
                expireDate = far
            } else if template.useSecondary, template.defaultDays == nil,
                      let sourceBest = scannedBestBefore,
                      bestDate <= Date().addingTimeInterval(60) {
                // 二次制备且模板**没设最佳天数** → 承接原标签。
                bestDate = sourceBest
                expireDate = resolvedExpireDate(fallback: sourceBest)
            } else if let days = appliedBestDays, days > 0,
                      bestDate <= Date().addingTimeInterval(60) {
                let due = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? bestDate
                bestDate = due
                expireDate = resolvedExpireDate(fallback: due)
            } else if bestDate <= Date().addingTimeInterval(60) {
                // 什么都不设（既不设最佳、也无原始保质期）→ 原始保质期跟着最佳走。
                expireDate = resolvedExpireDate(fallback: bestDate)
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
    /// ★★★ 2026-10-20（用户）：「设为**只有一个设最佳天数**……修改后台数据库逻辑」
    ///   ➜ 只有一个天数：模板级「设最佳使用时间」优先，否则按菜单层级继承。
    ///   ➜ 原始保质期不再单独设：无保质期 → 2099/12/31；否则与最佳一致。
    private var appliedBestDays: Int? {
        if let uniform = template.defaultDays { return uniform }
        let chain = chosenChain()
        guard !chain.isEmpty else { return nil }
        return chain.reversed().compactMap(\.days).first
    }

    /// 点「按推荐填日期」：把两个日期重置成「今天 + 推荐天数」。
    private func applyRecommendedDates() {
        guard let days = appliedBestDays, days > 0 else { return }
        let due = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        withAnimation(.default) {
            bestDate = due
            expireDate = resolvedExpireDate(fallback: due)
        }
    }

    /// 标签标题的唯一来源。
    ///
    /// ★ 2026-10-19（用户）命名规则（合并后的唯一实现）：
    ///   · **没有菜单** → `模板名-手输物料名`（"冷冻-五花肉"）
    ///   · **有菜单** → 默认 `第一层-第二层…`（"猪肉-五花肉"）；
    ///     开了「命名带模板名称」→ `模板名-第一层-第二层…`（"冷冻-猪肉-五花肉"）
    private func makeTitle(chain: [CustomNode]) -> String {
        let computed = computeTitle(chain: chain)
        // ★★★ 2026-10-21（用户报：「我选择了不需要修改名称，它就是直接用模板名的，
        //   但是扫描完之后又要我强制输入名称」）——
        //   真因：模板**有菜单但没选**时 `computeTitle` 返回空串，`buildDraft` 就弹
        //   "请先输入物料名称"。二次制备的标题本来就该来自原标签。
        //   ➜ 统一兜底：算不出就用 `scannedTitle`。
        if computed.isEmpty, let source = scannedTitle, !source.isEmpty {
            return source
        }
        return computed
    }

    /// 各分支的标题计算（不负责兜底）。
    private func computeTitle(chain: [CustomNode]) -> String {
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
                    //   ★ 2026-10-20：模板设了「不需要输入模板名」时，第一层不再取手输名。
                    if chain.count > 0 {
                        value = chain[0].name
                    } else if template.needsManualName {
                        value = materialName.trimmingCharacters(in: .whitespaces)
                    } else {
                        value = ""
                    }
                case .level2:
                    value = chain.count > 1 ? chain[1].name : ""
                case .level3:
                    value = chain.count > 2 ? chain[2].name : ""
                case .manual:
                    value = template.needsManualName
                        ? materialName.trimmingCharacters(in: .whitespaces) : ""
                case .sourceLevel1, .sourceLevel2, .sourceLevel3:
                    // ★ 2026-10-20（用户提问引出的 bug）：原标签是**原模板**用它的连接符拼的，
                    //   拿当前模板的 `titleSeparator` 去拆会拆不开（一个用"·"一个用"-"）。
                    //   ➜ 优先用「绑定的源模板」自己的连接符。
                    let pieces = (scannedTitle ?? "")
                        .components(separatedBy: sourceSeparator)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let index: Int = (part == .sourceLevel1 ? 0
                                      : (part == .sourceLevel2 ? 1 : 2))
                    value = index < pieces.count ? pieces[index] : ""
                }
                if !value.isEmpty { values.append(value) }
            }
            let result = values.joined(separator: template.titleSeparator)
            // ★★★ 2026-10-21（用户报："我开启了不需要输入模板名，打印还是弹**请先输入物料名称**"）
            //   ➜ 关掉手输后，标题要**兜底用扫到的原标签标题**，否则 name 为空 → 被 buildDraft 拦住。
            if result.isEmpty {
                if let source = scannedTitle, !source.isEmpty { return source }
                if template.needsManualName {
                    return materialName.trimmingCharacters(in: .whitespaces)
                }
            }
            return result
        }

        if template.nodes.isEmpty {
            // 不需要手输 → 直接用原标签标题。
            if !template.needsManualName, let source = scannedTitle, !source.isEmpty {
                return source
            }
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
            // ★★★ 2026-10-21（用户报：「我选择了不需要编辑名称，**但还是需要**」）——
            //   真因：这里原来是 `title = ""` 直接清空，**绕过了 makeTitle 的兜底**
            //   （二次制备本该用原标签标题）。改成走同一条计算链。
            title = makeTitle(chain: [])
            return
        }
        title = makeTitle(chain: chain)
        if let best = appliedBestDays, best > 0 {
            let due = Calendar.current.date(byAdding: .day, value: best, to: Date()) ?? Date()
            bestDate = due
            expireDate = resolvedExpireDate(fallback: due)
        }
    }

    /// 原标签标题用的连接符（取**源模板**的设置，拆层才不会错）。
    private var sourceSeparator: String {
        guard let id = template.sourceTemplateID,
              let source = CustomTemplateStore.template(id: id) else {
            return template.titleSeparator
        }
        return source.titleSeparator
    }

    /// 完成时间 = 现在 + 制备天数（制备模式专用）。
    private var completionDate: Date {
        // ⚠️ `byAdding: .day` 只吃 Int；制备天数允许小数 → 用秒加（最小 1 分钟）。
        Date().addingTimeInterval(max(60, template.prepDays * 86_400))
    }

    /// `yyyy/MM/dd HH:mm`，给"扫到的标签"那三行用。
    static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = AppCalendar.shared
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f.string(from: date)
    }

    /// 原始保质期的最终取值：无保质期 → 2099；设了原始天数 → 今天+N；都没设 → 跟最佳一致。
    /// 是不是"扫码续做"流程（用户：「扫二维码模板就应该是这样」）。
    private var isSecondaryFlow: Bool {
        template.useSecondary && scannedTitle != nil
    }

    /// 二次制备时原始保质期固定承接原标签（扫到的码里有就用它）。
    private var usesSourceExpire: Bool {
        template.useSecondary && scannedExpire != nil
    }

    private func resolvedExpireDate(fallback: Date) -> Date {
        if let sourceExpire = scannedExpire, template.useSecondary { return sourceExpire }
        // ★★★ 2026-10-20（用户）：「这个界面**不应该有"无原始保质期"选项**，删除这个功能，
        //   因为他是在**创建模板时设定的**」→ 只看模板/节点配置，页面不再有临时开关。
        if isNoExpiry { return Self.farFutureDate }
        if let orig = appliedOriginalDays, orig > 0 {
            return Calendar.current.date(byAdding: .day, value: orig, to: Date()) ?? fallback
        }
        return fallback
    }

    /// 原始保质期该用几天（模板级优先，其次按层级继承）。
    private var appliedOriginalDays: Int? {
        if let t = template.originalDays { return t }
        let chain = chosenChain()
        return chain.reversed().compactMap(\.originalDays).first
    }

    /// 当前选择链路上有没有任何一项开了「无保质期」。
    private var isNoExpiry: Bool {
        if template.noExpiry { return true }
        return chosenChain().contains { $0.noExpiry }
    }

    /// 「无保质期」时使用的日期：2099/12/31 23:59。
    static var farFutureDate: Date {
        var comps = DateComponents()
        comps.year = 2099; comps.month = 12; comps.day = 31
        comps.hour = 23; comps.minute = 59
        return AppCalendar.shared.date(from: comps) ?? Date()
    }

    // MARK: 打印

    private func buildDraft() -> LabelDraft? {
        let name = LabelTemplate.clamp(title)
        // ★ 2026-10-20：模板设了「不需要输入模板名」时，标题完全由命名规则决定，
        //   不再要求手输（这时 name 为空说明命名规则没配好，仍然拦一下）。
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
                                                      doneDays: template.usePrep ? template.prepDays
                                                                                 : (template.defaultDays ?? 3),
                                                      sourceBestBefore: sourceBest,
                                                      bestDays: template.defaultDays ?? 0,
                                                      maker: makerFinal)
        } else if template.usePrep {
            // 完成天数复用模板级「建议天数」（没设就按 3 天）。
            // 完成天数 = 原始保质期（懒人天数优先），不是最佳天数。
            data = LabelTemplate.buildCustomPrep(title: name, now: now,
                                                 doneDays: template.prepDays,
                                                 bestBefore: bestDate,
                                                 maker: makerFinal)
        } else {
            data = LabelTemplate.buildGeneric(title: name, now: now,
                                              expireDate: expireDate,
                                              bestBefore: bestDate,
                                              maker: makerFinal)
        }
        // ★★★ 2026-10-21（用户）：「打开制备功能后，效期管理里面就应该是**"完成时间"**，
        //   同时显示在**"正在制作中"**里。这个制备现在打印标签没问题，但是**数据后台存的不对**」
        //   真因：不管哪种模式，record 的 `bestBefore` 都取 `min(bestDate, expireDate)` ——
        //   而「制备」的"到期"是**完成时间**（现在 + 制备天数），不是页面上那个"最佳使用时间"。
        // ★★★ 2026-10-21（用户）：「**"完成时间"也算到期了，他不按到期算，"最佳使用时间"才算到期，
        //   "完成时间"只是完成制备**」
        //   ➜ 两个字段分工不同，**不要合在一起**：
        //     · `expireAt`  ← 制备型 = **完成时间**（决定"制作中 / 已完成制作"）
        //     · `bestBefore`← 始终是**最佳使用时间**（= 到期基准 / 倒计时 / 通知）
        let isPrep = template.usePrep || (template.useSecondary && scannedTitle != nil)
        // ⚠️ 同上：小数天 → 秒加。
        let prepDaysValue = template.usePrep
            ? template.prepDays
            : (template.defaultDays ?? 3)
        let completion = now.addingTimeInterval(max(60, prepDaysValue * 86_400))
        let recordExpire = isPrep ? completion : expireDate
        // ★★★ 2026-10-22（用户截图：康普茶二发记录显示「今天到期」）——
        //   制备型的「最佳使用时间」**可以晚于完成时间**（完成 +3 天、最佳 +31 天），
        //   这里再套 `min` 会把它压回完成时间 → 记录被判成"今天到期"。
        //   ➜ 制备型直接用 `bestDate` 本身；非制备型才取 min。
        let recordBest = isPrep ? bestDate : min(bestDate, expireDate)
        // 把来源模板的外观写进记录，列表才能画出这个模板自己的图标与文案，
        // 而不是一律回退到 `.generic`。
        let record = LabelTemplate.makeRecord(kind: .generic, data: data, createdAt: now,
                                              expireAt: recordExpire, bestBefore: recordBest,
                                              maker: makerFinal, isPrepared: isPrep,
                                              templateName: template.name,
                                              iconName: template.icon,
                                              tintName: template.tintName,
                                              iconColorName: template.iconColorName)
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
