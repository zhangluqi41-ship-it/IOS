//
//  MeatTemplateView.swift
//  肉类 —— 保存类型（冷藏 / 冷冻）+ 肉类 + 部位三级选择，两个日期按规则自动填。
//
//  ★ 结构对齐奶制品：上面选品类、中间填日期、下面填操作人。
//    区别只是多了一层「部位」，以及两个日期都按「保存类型」算偏移。
//
//  ★★ 2026-10-10（第十轮）用户图6 修复：
//    「选择完肉类后部位信息全不见了」——
//    根因是「部位」Picker 没有 `nil` 占位项，`cut == nil` 时渲染成空白。
//    现在改成「换肉类 → 自动选中该肉类第一个部位」（见 `onChange(of: animal)`）。
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
                LabelDatePicker(title: "原始保质期", date: $expireDate)
                QuickDateChips(selection: $expireDate)

                LabelDatePicker(title: "最佳使用时间", date: $bestDate)
                QuickDateChips(selection: $bestDate)
            } header: {
                Text("日期")
            } footer: {
                Text("保存类型选好后会自动按规则填上，也可以手动改。")
            }

            Section {
                MakerField(maker: $maker)
            } footer: {
                Text("会记住上次填写的操作人")
            }
        }
        .navigationTitle("肉类")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissible()
        .modifier(LabelActions(build: buildDraft))
        // ★★★【第十轮·用户图6 修复】「选择完肉类后部位信息全不见了」
        //
        //  原写法是 `cut = nil`（理由是「换了肉类，旧部位就不属于它了」），
        //  这个理由本身没错，但它撞上了一个 SwiftUI 的渲染陷阱：
        //
        //    「部位」Picker 里**没有 tag 为 `nil` 的选项**
        //    （2026-10-09 按用户要求删掉了「请选择」占位项），
        //    所以当 `selection == nil` 时，Picker **找不到任何匹配项**，
        //    右侧的值区就渲染成**一片空白** —— 用户看到的就是「部位信息全不见了」。
        //
        //  ➜ 正解：换肉类时**自动选中该肉类的第一个部位**，而不是清成 nil。
        //    · 永远不会出现空白；
        //    · `buildDraft()` 的 `guard let c = cut` 立刻可通过；
        //    · 「按推荐填日期」按钮的显示条件（`cut != nil`）也立刻满足。
        //  ⚠️ 不要改回 `cut = nil`，也不要给 Picker 加回「请选择」占位项
        //     （那是用户明确要求删掉的）。
        .onChange(of: animal) { _, value in
            guard let value else {
                // 肉类被清空（理论上不会发生）→ 部位一并清空。
                cut = nil
                return
            }
            cut = value.cuts.first
            if let s = storage { applyRule(s) }
        }
        .onChange(of: storage) { _, value in
            guard let value, cut != nil else { return }
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
        let makerFinal = MakerField.finalize(maker)

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
