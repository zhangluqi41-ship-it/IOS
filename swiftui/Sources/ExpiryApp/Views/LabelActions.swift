//
//  LabelActions.swift
//  标签动作的公共装配 —— 五个模板页（通用 / 康普茶一发 / 康普茶二发 / 奶制品 / 肉类）
//  共用同一套「打印」动作与提示，避免五处复制。
//
//  ★ 为什么不用 `.toolbar(placement: .bottomBar)`：
//    试过了 —— 在 TabView 里的二级页上，bottom bar 会和底部的 Tab 栏抢位置，
//    结果按钮被 Tab 栏盖住、直接看不见（用户实测反馈）。
//    改成 `safeAreaInset(edge: .bottom)` 自绘一条操作条：
//    它加在「内容 + 底部安全区」之间，而 Tab 栏占的正是底部安全区，
//    所以这条 bar 会稳稳落在 Tab 栏**上方**，就是想要的二级 bar 效果。
//
//  ★ 2026-10-07：用户要求**取消「预览标签」功能**，二级条只留「打印」。
//    随之一起去掉的还有预览页上的「保存到手机」「分享」。
//    ★ 2026-10-10（第十四轮·全工程优化）：`PreviewView` / `PreviewPayload` /
//    `ShareSheet` 的源码已**删除**（确认零入口；如需恢复查 git 历史，
//    那里面记录的 PDFKit/ScrollView 缩放坑别再踩第二遍）。
//    `PDFRasterizer` **保留** —— 单测与 `QRCodeGenerator` 的 `GrayBuffer` 仍在用。
//
//  ★ 2026-10-09：键盘抬起时底部操作条收起，改为在键盘上方的第一方
//    accessory bar 里与「完成」并排 —— 详见 `LabelActions` 的文档注释。
//

import SwiftUI

// MARK: - 提示

struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

extension Optional where Wrapped == String {
    /// 打印回调带的失败原因：nil 或空串时回退到兜底文案。
    /// （避免每个调用点各写一遍 `message?.isEmpty == false ? message! : …`）
    func orFallback(_ fallback: String) -> String {
        if let self, !self.isEmpty { return self }
        return fallback
    }
}

// MARK: - 一张待输出的标签

/// 模板页把「标签数据 + 待入库记录」打包成 draft，
/// 打印从 draft 出发生成 PDF，保证内容与入库记录完全一致。
struct LabelDraft {
    let data: LabelData
    let record: LabelRecord

    var fileName: String {
        LabelTemplate.labelFileName(data.title, record.createdAt)
    }

    /// 生成 PDF（50×30mm 矢量，可直接送打印机）。
    func pdf() -> Data {
        LabelRenderer.renderPDF(data,
                                regular: FontProvider.regular(12),
                                bold: FontProvider.bold(12))
    }
}

// MARK: - 二级操作条

/// 二级操作条：只剩一个「打印」，固定落在 Tab 栏上方。
struct LabelActionBar: View {
    let isBusy: Bool
    let onPrint: () -> Void

    var body: some View {
        Button(action: onPrint) {
            HStack(spacing: 7) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Label("打印", systemImage: "printer.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 11)
        }
        .liquidGlassProminentButton()
        .tint(Theme.brand)
        .disabled(isBusy)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

// MARK: - 「操作人」输入行（五个模板页共用）

/// 「操作人」输入行：图标 + 限长 TextField。
/// 五个模板页（通用 / 康普茶一发 / 康普茶二发 / 奶制品 / 肉类）共用，
/// 别在各页里再手抄一遍 HStack。
///
/// ★★★ 2026-10-10（第十九轮）新增 `focused(_:)`：
///   为了让「收键盘」走**第一方 `@FocusState`**（`focused = nil`），
///   这个输入框必须把自己的 focus 绑定暴露出去。
///   用法：`MakerField(maker: $maker, focused: $focus)`
///   ⚠️ 加了它之后，`@FocusState.Binding` 的类型会传染 —— 见 `KeyboardFocus.swift`。
struct MakerField: View {
    @Binding var maker: String
    /// 页面级的焦点绑定。⚠️ **不要设默认值** —— 全页共用的焦点必须显式传进来，
    /// 否则会各自为政、收键盘只收得到其中一部分（第十九轮定的规矩）。
    var focused: FocusState<AnyHashable?>.Binding

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person")
                .foregroundStyle(Theme.brand)
                .frame(width: 22)
            TextField("输入操作人", text: $maker)
                .focused(focused, equals: AnyHashable("maker"))
                .onChange(of: maker) { _, value in
                    if value.count > LabelTemplate.maxNameLength {
                        maker = String(value.prefix(LabelTemplate.maxNameLength))
                    }
                }
        }
    }

    /// 打印前的「制作人」收尾：裁剪 → 记住这次填的 → 空则「未署名」。
    /// 返回值可直接写进标签与入库记录（五个模板页的 buildDraft 共用）。
    static func finalize(_ raw: String) -> String {
        let value = LabelTemplate.clamp(raw, LabelTemplate.maxNameLength)
        Prefs.lastMaker = value
        return value.isEmpty ? "未署名" : value
    }
}

// MARK: - 重新打印

/// 「效期管理」里对一条已有记录重新出标签。
///
/// 和模板页「打印」走的是**同一条入库路径**（`PrinterService.printLabel` 的
/// `record:` 参数），所以重打之后记录不会翻倍 ——
/// `LabelRecord.qrText` 与原来完全相同，`ExpiryStore.add` 会按它去重合并。
enum LabelReprint {

    /// 重打。连接状态由调用方先行判断并给出提示。
    static func print(_ record: LabelRecord,
                      completion: ((Bool, String?) -> Void)? = nil) {
        let printer = PrinterService.shared
        guard printer.isConnected else {
            completion?(false, "请先连接打印机")
            return
        }

        let data = LabelTemplate.rebuild(from: record)
        let pdf = LabelRenderer.renderPDF(data,
                                          regular: FontProvider.regular(12),
                                          bold: FontProvider.bold(12))

        // ★ 传一份 `printedAt = nil` 的副本：打印成功回调里会把它写成「这次」的时间，
        //   否则 `printedAt ?? Date()` 会保留旧值，详情页的「打印时间」永远不变。
        var fresh = record
        fresh.printedAt = nil

        printer.printLabel(pdf: pdf,
                           fileName: LabelTemplate.labelFileName(record.title, record.createdAt),
                           copies: Prefs.printCopies,
                           density: Prefs.printDensity,
                           paperType: Prefs.paperType,
                           record: fresh,
                           completion: completion)
    }

    /// 重打 + 把结果直接翻成提示（连接检查也在里面）。
    /// 两个入口（效期管理列表行 / 详情页）共用；
    /// 成功时的正文由调用方给（两处文案**刻意不同**，别合并）。
    static func printNoticing(_ record: LabelRecord,
                              successBody: String,
                              setNotice: @escaping (Notice?) -> Void) {
        guard PrinterService.shared.isConnected else {
            setNotice(Notice(title: "还没有连接打印机",
                             body: "请到「打印机」标签页连接硕方 T50 Pro，再回来重打。"))
            return
        }
        Self.print(record) { ok, message in
            if ok {
                setNotice(Notice(title: "已发送到打印机", body: successBody))
            } else {
                setNotice(Notice(title: "打印失败",
                                 body: message.orFallback("请检查打印机状态后重试。")))
            }
        }
    }
}

// MARK: - 动作修饰器

/// 给模板页挂上：底部二级操作条 + 键盘上方的「完成」+ 提示弹窗。
///
/// - Parameter build: 由各页自己实现——校验通过返回 `LabelDraft`，
///   校验不过时页面内部弹自己的提示并返回 `nil`。
///
/// ★★ 2026-10-09 改动（用户反馈「输入文字时，完成和打印两个按钮重叠」）：
///   原来底部那条「打印」操作条会跟着键盘一起抬到键盘正上方，
///   而键盘自己的 accessory bar（「完成」）也在键盘正上方 ——
///   两条 bar 贴在一起、又都是半透明材质，看起来就是「叠在一起」。
///
/// ★★★ 2026-10-10（第十八轮）**再修一次，这次是彻底删掉重复入口** ——
///   上一轮的方案（键盘抬起时把「打印」搬到 accessory bar，与「完成」并排）
///   在**列表自身的滚动区域**上又出了新问题，用户截图圈出两个红框按钮：
///     「点击输入框后『打印』框消失，变成这两个红框内的按钮（完成 / 打印），
///       删除这两个红框按钮，保留底部那个『打印』，
///       并且该按钮保持当前逻辑、键盘出现后自然跟随键盘上移。」
///
///   为什么它会「浮在内容上」：`safeAreaInset(edge: .bottom)` 的 inset 条
///   会跟着键盘抬起来，而列表**已经有了键盘 inset**，两者叠加 →
///   这条 bar 被顶到列表内容之上、半透明材质把「最佳使用时间」那行盖住
///   （截图里"最佳使用时间"被压掉一半就是这个）。
///
///   ➜ 正解：**删掉 accessory bar 里的「打印」**，同时**保留底部操作条**
///     （不再 `if !keyboard.isVisible` 收起）。
///     · 键盘收起时：底部「打印」照旧；
///     · 键盘抬起时：**还是同一个**底部「打印」—— 它自己就跟着键盘上移，
///       没有第二个按钮出现，就不存在重叠/盖内容；
///     · 键盘上只留系统自带的「完成」（用户明确要保留它，用来收键盘）。
///
///   ⚠️ 千万不要把「打印」再挂回 `ToolbarItemGroup(placement: .keyboard)` ——
///      那正是本轮删掉的东西。
///
/// ★★★ 2026-10-10（第十九轮）**「完成」也删掉了** —— 用户：
///   「『完成』按钮也不需要，因为逻辑上是**点击或滑动屏幕任意位置，流畅收起键盘**」。
///   确实不需要：滑动收键盘已由第一方 `.scrollDismissesKeyboard` 负责、
///   点空白由我们那个只观察不拦截的手势负责，两者都走 **`@FocusState`**
///   （`FocusCoordinator`）→ 键盘是**动画**收起的，不再需要这个快捷键。
///
///   ➜ 于是**整条 keyboard accessory bar 被彻底移除** —— 这顺带解决了
///     第十八轮那个疑难：以前 accessory bar 上挂过「打印」，
///     会让 `.scrollDismissesKeyboard` 失效（第十七轮的观察）；
///     现在 bar 没了，`ToolbarItemGroup(placement: .keyboard)` 不再出现，
///     那条干扰也一并消失。
///
///   ⚠️ 以后**不要再往这里加 `ToolbarItemGroup(placement: .keyboard)`** ——
///      键盘上方应该只有系统键盘自己。
struct LabelActions: ViewModifier {
    let build: () -> LabelDraft?

    @ObservedObject private var printer = PrinterService.shared

    @AppStorage("printCopies") private var copies: Int = 1
    @AppStorage("printDensity") private var density: Int = 0
    @AppStorage("paperType") private var paperType: Int = 1

    @State private var notice: Notice?

    func body(content: Content) -> some View {
        content
            // ★★★ 第十八轮：**不再随键盘收起**。
            //   它自己是 `safeAreaInset`，键盘弹起时会被系统连同安全区
            //   一起顶到键盘上方 —— 也就是用户要的「自然跟随键盘上移」，
            //   同时全页只剩这一个「打印」，不会再和 accessory bar 打架。
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LabelActionBar(isBusy: printer.isPrinting, onPrint: printNow)
            }
            // ★★★ 第十九轮：**没有任何 `ToolbarItemGroup(placement: .keyboard)`**。
            //   模拟器实测（历史轮次）只挂一个 accessory bar 时
            //   `.scrollDismissesKeyboard` 依然生效 —— 但那时 bar 上只有「完成」。
            //   既然「完成」也被用户点名删掉，索性整条 bar 拿掉，
            //   键盘上方只剩系统键盘自己，干扰最小。
            .alert(notice?.title ?? "",
                   isPresented: Binding(get: { notice != nil },
                                        set: { if !$0 { notice = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(notice?.body ?? "")
            }
    }

    // MARK: 动作

    private func printNow() {
        guard printer.isConnected else {
            notice = Notice(title: "还没有连接打印机",
                            body: "请到「打印机」标签页扫描并连接硕方 T50 Pro，再回来打印。")
            return
        }
        guard let draft = build() else { return }

        printer.printLabel(pdf: draft.pdf(),
                           fileName: draft.fileName,
                           copies: copies,
                           density: density,
                           paperType: paperType,
                           record: draft.record) { ok, message in
            if ok {
                notice = Notice(title: "已发送到打印机",
                                body: "\(draft.data.title)\n份数 \(copies) · 浓度 \(density == 0 ? "自动" : "\(density)")")
            } else {
                notice = Notice(title: "打印失败",
                                body: message.orFallback("请检查打印机状态后重试。"))
            }
        }
    }
}
