//
//  MeatThawView.swift
//  肉类 · 解冻 —— 扫「冷冻」标签的二维码后进入，直接生成一张解冻标签。
//
//  ★ 用户要求（清单「一、模板二级菜单」第 4 条）：
//      「解冻后的菜单中开封时间改成解冻时间，时间为扫码时的时间，
//        原始保质期保持原保不变，最佳使用时间改为当前时间 + 3 天」
//
//  ★ 这个页面**只有扫码能进来**：它没有模板卡片、也不在 `TemplateRoute` 里 ——
//    用户明确要求「不作为可选模板，只有扫描二维码才能出来」。
//
//  ★ 原始保质期那一行**照搬二维码原文**（`meat.expireRaw`），
//    不是拿 Date 重新格式化 —— 否则会按「是否 ≤7 天」把时刻改写成 23:59
//    或写回当前时刻，那就不是「保持不变」了。
//

import SwiftUI

struct MeatThawView: View {
    let meat: MeatLabelInfo

    @State private var maker = Prefs.lastMaker
    @State private var flash: String?

    private var now: Date { Date() }
    private var thawBest: Date { MeatRule.thawedBest(from: now) }

    var body: some View {
        List {
            Section {
                LabeledContent("品名", value: meat.baseName)
                LabeledContent("保存类型", value: meat.storage.label)
                LabeledContent("原始保质期", value: meat.expireRaw)
                LabeledContent("原最佳使用时间", value: LabelTemplate.fmtDateTime(meat.bestBefore))
            } header: {
                Text("扫到的冷冻标签")
            } footer: {
                Text("冷冻标签扫一次即进入解冻流程，这一页不会出现在模板菜单里。")
            }

            Section {
                LabeledContent("解冻时间", value: LabelTemplate.fmtDateTime(now))
                LabeledContent("原始保质期", value: meat.expireRaw)
                LabeledContent("最佳使用时间", value: LabelTemplate.fmtDateTime(thawBest))
            } header: {
                Text("解冻后要打印的内容")
            } footer: {
                Text("解冻时间 = 扫码这一刻；原始保质期保持不变；"
                     + "最佳使用时间 = 现在 + \(MeatRule.thawedBestDays) 天。")
            }

            Section {
                MakerField(maker: $maker)
            } footer: {
                Text("会记住上次填写的操作人")
            }

            Section {
                Label("解冻标签的标题为「\(MeatRule.thawPrefix)-\(meat.baseName)」",
                      systemImage: "tag")
                Label("再扫这张解冻标签不会再触发解冻", systemImage: "checkmark.seal")
            } header: {
                Text("说明")
            }
        }
        .navigationTitle("肉类 · 解冻")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissible()
        .modifier(LabelActions(build: buildDraft))
    }

    private func buildDraft() -> LabelDraft? {
        let makerFinal = MakerField.finalize(maker)

        let stamp = Date()
        let best = MeatRule.thawedBest(from: stamp)
        let data = LabelTemplate.buildMeatThaw(baseName: meat.baseName,
                                               now: stamp,
                                               expireRaw: meat.expireRaw,
                                               maker: makerFinal)
        let record = LabelTemplate.makeRecord(kind: .meat, data: data, createdAt: stamp,
                                              expireAt: meat.expireAt, bestBefore: best,
                                              maker: makerFinal)
        return LabelDraft(data: data, record: record)
    }
}

#Preview {
    NavigationStack {
        MeatThawView(meat: MeatLabelInfo(
            baseName: "牛肉-眼肉",
            title: "冷冻-牛肉-眼肉",
            storage: .frozen,
            alreadyThawed: false,
            expireAt: Date(),
            bestBefore: Date(),
            expireRaw: "2027/01/09 23:59"
        ))
    }
}
