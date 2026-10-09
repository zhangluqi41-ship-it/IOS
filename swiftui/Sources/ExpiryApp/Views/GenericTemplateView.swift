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

    var body: some View {
        List {
            Section {
                field(icon: "tag", placeholder: "输入物料名称", text: $title,
                      limit: LabelTemplate.maxTitleLength)
                field(icon: "person", placeholder: "输入操作人", text: $maker,
                      limit: LabelTemplate.maxNameLength)
            } footer: {
                Text("会记住上次填写的操作人")
            }

            Section {
                AutoCloseDatePicker(title: "原始保质期", date: $expireDate)
                QuickDateChips(selection: $expireDate)

                AutoCloseDatePicker(title: "最佳使用时间", date: $bestDate)
                QuickDateChips(selection: $bestDate)
            } header: {
                Text("日期")
            }
        }
        .navigationTitle("通用效期")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissible()
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
        let makerValue = LabelTemplate.clamp(maker, LabelTemplate.maxNameLength)
        let makerFinal = makerValue.isEmpty ? "未署名" : makerValue
        Prefs.lastMaker = makerValue

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
struct QuickDateChips: View {
    @Binding var selection: Date

    @State private var selectedLabel = ""

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.label) { p in
                Button {
                    selection = p.date
                    selectedLabel = p.label
                } label: {
                    Text(p.label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            selectedLabel == p.label ? Theme.brand : Color(.tertiarySystemFill),
                            in: Capsule()
                        )
                        .foregroundStyle(selectedLabel == p.label ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
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
