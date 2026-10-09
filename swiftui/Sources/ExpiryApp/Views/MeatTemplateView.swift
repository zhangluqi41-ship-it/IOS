//
//  MeatTemplateView.swift
//  肉类 —— 保存类型（冷藏 / 冷冻）+ 肉类 + 部位三级选择，两个日期按规则自动填。
//
//  ★ 结构对齐奶制品：上面选品类、中间填日期、下面填操作人。
//    区别只是多了一层「部位」，以及两个日期都按「保存类型」算偏移。
//
//  ★ 冷冻标签打印后，**再扫它的二维码就会进「解冻」流程**
//    （不是从模板入口进 —— 用户要求「不作为可选模板，只有扫描二维码才能出来」），
//    见 `MeatThawView`。
//

import SwiftUI

struct MeatTemplateView: View {
    @State private var storage: MeatStorage?
    @State private var animal: MeatAnimal?
    @State private var cut: String?
    @State private var maker = Prefs.lastMaker
    @State private var expireDate = Date()
    @State private var bestDate = Date()
    @State private var alertText = ""
    @State private var showAlert = false

    var body: some View {
        List {
            Section {
                Picker("保存类型", selection: $storage) {
                    // ★ 2026-10-09：去掉「请选择」占位项，理由同奶制品模板。
                    ForEach(MeatStorage.allCases) { s in
                        Text(s.label).tag(Optional(s))
                    }
                }
                .pickerStyle(.menu)

                Picker("肉类", selection: $animal) {
                    // ★ 同上：不塞占位项。
                    ForEach(MeatAnimal.allCases) { a in
                        Text(a.label).tag(Optional(a))
                    }
                }
                .pickerStyle(.menu)
                .disabled(storage == nil)

                Picker("部位", selection: $cut) {
                    // ★ 同上：不塞占位项。
                    ForEach(animal?.cuts ?? [], id: \.self) { c in
                        Text(c).tag(Optional(c))
                    }
                }
                .pickerStyle(.menu)
                .disabled(animal == nil)

                if let s = storage, animal != nil, cut != nil {
                    Button {
                        applyRule(s)
                    } label: {
                        HStack {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(Theme.brand)
                            Text("按推荐填日期")
                                .foregroundStyle(Theme.brand)
                            Spacer()
                            Text("保质期 \(s.offsetText) · 最佳 \(s.offsetText)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("品类")
            } footer: {
                if animal == nil {
                    Text("先选保存类型，再选肉类与部位。")
                } else if let s = storage, s.isFrozen {
                    Text("冷冻标签打印后，用「扫码」再扫一次这张标签，就会进入解冻流程。")
                } else if storage != nil {
                    Text("冷藏肉类不需要解冻，扫它不会再生成新标签。")
                }
            }

            Section {
                AutoCloseDatePicker(title: "原始保质期", date: $expireDate)
                QuickDateChips(selection: $expireDate)

                AutoCloseDatePicker(title: "最佳使用时间", date: $bestDate)
                QuickDateChips(selection: $bestDate)
            } header: {
                Text("日期")
            } footer: {
                Text("保存类型选好后会自动按规则填上，也可以手动改。")
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "person")
                        .foregroundStyle(Theme.brand)
                        .frame(width: 22)
                    TextField("输入操作人", text: $maker)
                        .onChange(of: maker) { _, value in
                            if value.count > LabelTemplate.maxNameLength {
                                maker = String(value.prefix(LabelTemplate.maxNameLength))
                            }
                        }
                }
            } footer: {
                Text("会记住上次填写的操作人")
            }
        }
        .navigationTitle("肉类")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissible()
        .modifier(LabelActions(build: buildDraft))
        .onChange(of: animal) { _, _ in
            // 换了肉类，原来的部位就不属于它了 —— 必须清掉，
            // 否则会印出「猪肉-鸡腿」这种不存在的组合。
            cut = nil
        }
        .onChange(of: storage) { _, value in
            guard let value, animal != nil, cut != nil else { return }
            applyRule(value)
        }
        .alert(alertText, isPresented: $showAlert) {
            Button("好", role: .cancel) {}
        }
    }

    /// 按保存类型把两个日期都填好（冷藏 +5 天 / 冷冻 +3 个月，两者相同）。
    private func applyRule(_ s: MeatStorage) {
        let (expire, best) = MeatRule.dates(storage: s, from: Date())
        expireDate = expire
        bestDate = best
    }

    private func buildDraft() -> LabelDraft? {
        guard let s = storage else {
            alertText = "请先选择保存类型（冷藏 / 冷冻）"
            showAlert = true
            return nil
        }
        guard let a = animal else {
            alertText = "请先选择肉类"
            showAlert = true
            return nil
        }
        guard let c = cut else {
            alertText = "请先选择部位"
            showAlert = true
            return nil
        }
        let makerValue = LabelTemplate.clamp(maker, LabelTemplate.maxNameLength)
        let makerFinal = makerValue.isEmpty ? "未署名" : makerValue
        Prefs.lastMaker = makerValue

        let now = Date()
        let data = LabelTemplate.buildMeat(animal: a, cut: c, storage: s, now: now,
                                           expireDate: expireDate, bestBefore: bestDate,
                                           maker: makerFinal)
        let record = LabelTemplate.makeRecord(kind: .meat, data: data, createdAt: now,
                                              expireAt: expireDate, bestBefore: bestDate,
                                              maker: makerFinal)
        return LabelDraft(data: data, record: record)
    }
}

#Preview {
    NavigationStack {
        MeatTemplateView()
    }
}
