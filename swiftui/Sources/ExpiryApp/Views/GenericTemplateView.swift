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
///   四个 chip 在 iPhone 最窄机型上仍能一行放下（约 296pt < 343pt 可用宽度），
///   所以不做横向滚动，保持一眼看全。
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
struct QuickDateChips: View {
    @Binding var selection: Date

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.label) { p in
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
