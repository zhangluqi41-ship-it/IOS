//
//  MeatThawView.swift
//  肉类 · 解冻 —— 扫「冷冻」标签的二维码后进入，直接生成一张解冻标签。
//
//  ★ 用户要求（清单「一、模板二级菜单」第 4 条；2026-10-10 第十五轮更新）：
//      「解冻后的菜单中开封时间改成解冻时间，时间为扫码时的时间，
//        原始保质期改成完成时间（解冻时间 + 1 天），
//        最佳使用时间改为当前时间 + 3 天」
//    最初版本是「原始保质期保持原保不变」，本轮改成「完成时间 = 解冻时间 + 1 天」。
//
//  ★ 这个页面**只有扫码能进来**：它没有模板卡片、也不在 `TemplateRoute` 里 ——
//    用户明确要求「不作为可选模板，只有扫描二维码才能出来」。
//
//  ★ 顶部「扫到的冷冻标签」区块显示的是**原冷冻标签**上的信息
//    （`meat.expireRaw` = 那张标签印的原始保质期），
//    与「解冻后要打印的内容」是两回事 —— 别把它也一起改了。
//

import SwiftUI

struct MeatThawView: View {
    let meat: MeatLabelInfo

    @State private var maker = Prefs.lastMaker
    @State private var flash: String?
    /// ★ 第一方焦点（第十九轮）：收键盘走 `focused = nil`，键盘才有系统动画。
    @FocusState private var focus: AnyHashable?

    private var now: Date { Date() }
    /// 完成时间 = 解冻时间 + 1 天。
    private var thawComplete: Date { MeatRule.thawedComplete(from: now) }
    /// 最佳使用时间 = 解冻时间 + 3 天。
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
                LabeledContent("完成时间", value: LabelTemplate.fmtDateByThreshold(now, thawComplete))
                LabeledContent("最佳使用时间", value: LabelTemplate.fmtDateByThreshold(now, thawBest))
            } header: {
                Text("解冻后要打印的内容")
            } footer: {
                Text("解冻时间 = 扫码这一刻；完成时间 = 解冻时间 + \(MeatRule.thawCompleteDays) 天；"
                     + "最佳使用时间 = 解冻时间 + \(MeatRule.thawedBestDays) 天。")
            }

            Section {
                MakerField(maker: $maker, focused: $focus)
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
        .keyboardDismissible(focus: $focus)
        .modifier(LabelActions(build: buildDraft))
    }

    private func buildDraft() -> LabelDraft? {
        let makerFinal = MakerField.finalize(maker)

        let stamp = Date()
        let best = MeatRule.thawedBest(from: stamp)
        let data = LabelTemplate.buildMeatThaw(baseName: meat.baseName,
                                               now: stamp,
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
