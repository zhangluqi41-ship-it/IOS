//
//  GenericTemplateView.swift
//  通用效期 —— 标题手填 + 两个日期（统一「日期」组）+ 快捷档位。
//
//  输出动作（打印）由 `LabelActions` 修饰器统一挂底部工具栏，
//  这里只负责「校验 + 装配 draft」。
//

import SwiftUI

struct GenericTemplateView: View {
    @State private var title = ""
    @State private var maker = Prefs.lastMaker
    @State private var expireDate = Date()
    @State private var bestDate = Date()
    @State private var showTitleAlert = false
    /// ★ 第一方焦点：收键盘（点空白 / 滚动）都改走 `focused = nil`，
    ///   这样键盘才会播系统动画而不是瞬间消失。
    @FocusState private var focus: AnyHashable?

    var body: some View {
        List {
            Section {
                field(icon: "tag", placeholder: "输入物料名称", text: $title,
                      limit: LabelTemplate.maxTitleLength)
                    .focused($focus, equals: AnyHashable("title"))
                MakerField(maker: $maker, focused: $focus)
            } footer: {
                Text("会记住上次填写的操作人")
            }

            Section {
                LabelDatePicker(title: "原始保质期", date: $expireDate)
                QuickDateChips(selection: $expireDate)

                LabelDatePicker(title: "最佳使用时间", date: $bestDate)
                QuickDateChips(selection: $bestDate)
            } header: {
                Text("日期")
            }
        }
        .navigationTitle("通用效期")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissible(focus: $focus)
        .modifier(LabelActions(build: buildDraft))
        .alert("请先填写物料名称", isPresented: $showTitleAlert) {
            Button("好", role: .cancel) {}
        }
    }

    private func field(icon: String, placeholder: String,
                       text: Binding<String>, limit: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.brand)
                .frame(width: 22)
            TextField(placeholder, text: text)
                .onChange(of: text.wrappedValue) { _, value in
                    if value.count > limit { text.wrappedValue = String(value.prefix(limit)) }
                }
        }
    }
    private func buildDraft() -> LabelDraft? {
        let name = LabelTemplate.clamp(title)
        guard !name.isEmpty else {
            showTitleAlert = true
            return nil
        }
        let makerFinal = MakerField.finalize(maker)

        let now = Date()
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

/// 快捷档位：+3 天 / +7 天 / +15 天 / +1 个月。
///
/// ★ 2026-10-09 用户要求增加「+3 天」—— 奶制品最推荐档就是 +3 天，
///   通用模板里也常要填「开封后 3 天用完」，手点日历太慢。
///
/// ★★★ 2026-10-10（第十八轮）用户反馈 ——
///   「选高亮 +15 天后日期自动变成 +15 天，但**手动改完日期（明显不是 +15 天）后，
///     +15 天依然高亮**」。
///
///   根因：高亮原来存在一个**自己的** `@State selectedLabel` 里 ——
///   「点 chip」会写它，「点日历改日期」却**没人去清它**，
///   于是日期早已不是 +15 天了，高亮还赖在 +15 天上。
///
///   ➜ 正解：**高亮不再是状态，而是从真实日期现算出来的**（单一数据源）。
///     某个档位的日期 == 当前选中日期 → 它才高亮；否则一律不高亮。
///     · 点 chip → 日期变了 → 现算即命中 → 立刻高亮（与原来一样快）；
///     · 点日历改成别的日子 → 日期变了 → 现算不命中 → **高亮自动消失**（本轮修的）；
///     · 改成正好等于某个档位 → 那个档位自动亮（顺手白赚的一致性）。
///
///   ⚠️ 不要再引入 `@State` 去记「选中的是哪个档」——
///      那等于把高亮和真相日期的绑定**又**拆开一次（本轮踩的就是这个坑）。
///
/// ★★★ 2026-10-10（第二十一轮）改走**第一方 `Button` 样式**：
///   之前手写 `Capsule()` 背景 + 手调 padding（典型的"安卓味自绘"），
///   现在用系统自带的 **`.buttonStyle(.bordered)` / `.borderedProminent`**
///   —— 圆角、材质、按压反馈、深色模式、无障碍全部由系统给，
///   不用我们自己猜数值，也是用户要的「最高苹果流畅度」。
struct QuickDateChips: View {
    @Binding var selection: Date

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.label) { p in
                // ★★★ 2026-10-11（第二十三轮）**颜色回归原版**。
                //
                //   用户报：「颜色不对，改成原来的颜色」（附了改前/改后两张对比图）。
                //   图片对比结论：
                //     · 原版（用户要的）= **深灰胶囊 `Color(.tertiarySystemFill)`
                //       + `.primary` 文字**（深色模式下就是白字），选中 = 蓝底白字；
                //     · 我改坏的（v1.1.5）= `.buttonStyle(.borderedProminent)`
                //       → 系统把 `Theme.brand` 同时当**底色**和**文字色**，
                //         变成「实心蓝 + 蓝字」，四个 chip 还全一个色、看不出选没选。
                //
                //   ➜ 正解 = 回到 **v1.1.3 那套写法**（`git show 53c1d64` 可查）。
                //     它本来就是第一方语义色：`.tertiarySystemFill` 是系统动态灰、
                //     `.primary` 是系统语义标签色 —— 跟深/浅模式、液态玻璃都自动协调，
                //     比 `.bordered` 系列在 `List` 行里更贴合、也更贴近用户认可的观感。
                //
                //   ⚠️ 别再改回 `.buttonStyle(.bordered / .borderedProminent)` ——
                //      `.tint()` 会同时给底和字上色，出不来"灰底黑字"的静默态。
                //   ⚠️ 高亮判定仍然必须**按天现算**（见 `isSelected`），不许存状态。
                let isOn = isSelected(p.date)
                Button {
                    selection = p.date
                } label: {
                    Text(p.label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            isOn ? Theme.brand : Color(.tertiarySystemFill),
                            in: Capsule()
                        )
                        .foregroundStyle(isOn ? .white : .primary)
                        // ★ 撑满胶囊矩形，保证整块都能点（胶囊内边距也算命中区）。
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }

    /// ★ 高亮 = **现算**，不存状态。
    ///
    /// ⚠️ 比较必须**按天**做（两边都压到 0 点）—— `Date` 带时分秒，
    ///    直接用 `==` 几乎永远不成立（这也是「高亮跟不住日期」的隐患来源）。
    private func isSelected(_ preset: Date) -> Bool {
        let cal = AppCalendar.shared
        return cal.isDate(cal.startOfDay(for: selection),
                          inSameDayAs: cal.startOfDay(for: preset))
    }

    private struct Preset {
        let label: String
        let date: Date
    }

    private var presets: [Preset] {
        let cal = AppCalendar.shared
        let today = cal.startOfDay(for: Date())
        func add(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: today) ?? today }
        func addMonth(_ m: Int) -> Date { cal.date(byAdding: .month, value: m, to: today) ?? today }
        return [
            Preset(label: "+3 天", date: add(3)),
            Preset(label: "+7 天", date: add(7)),
            Preset(label: "+15 天", date: add(15)),
            Preset(label: "+1 个月", date: addMonth(1)),
        ]
    }
}

#Preview {
    NavigationStack {
        GenericTemplateView()
    }
}
