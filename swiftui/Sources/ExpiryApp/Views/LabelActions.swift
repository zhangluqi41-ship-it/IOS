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
struct MakerField: View {
    @Binding var maker: String

    var body: some View {
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

/// 给模板页挂上：底部二级操作条 + 键盘上方的「完成 / 打印」+ 提示弹窗。
///
/// - Parameter build: 由各页自己实现——校验通过返回 `LabelDraft`，
///   校验不过时页面内部弹自己的提示并返回 `nil`。
///
/// ★★ 2026-10-09 改动（用户反馈「输入文字时，完成和打印两个按钮重叠」）：
///   原来底部那条「打印」操作条会跟着键盘一起抬到键盘正上方，
///   而键盘自己的 accessory bar（「完成」）也在键盘正上方 ——
///   两条 bar 贴在一起、又都是半透明材质，看起来就是「叠在一起」。
///
///   现在的做法：**同一时刻只存在一条 bar**
///     · 键盘收起 → 底部操作条显示「打印」
///     · 键盘抬起 → 底部操作条当场收起；「打印」搬到键盘上方的
///       第一方 accessory bar，与「完成」并排（`ToolbarItemGroup(placement: .keyboard)`）
///   两边都是系统第一方控件，位置由系统安排，结构上不可能重叠。
///   收起/展开的动画时长取自键盘通知，和键盘同一条时间线。
struct LabelActions: ViewModifier {
    let build: () -> LabelDraft?

    @ObservedObject private var printer = PrinterService.shared
    @ObservedObject private var keyboard = KeyboardWatcher.shared

    @AppStorage("printCopies") private var copies: Int = 1
    @AppStorage("printDensity") private var density: Int = 0
    @AppStorage("paperType") private var paperType: Int = 1

    @State private var notice: Notice?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // 键盘抬起时就地收起，把位置让给键盘自己的 accessory bar。
                if !keyboard.isVisible {
                    LabelActionBar(isBusy: printer.isPrinting, onPrint: printNow)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("完成") { SoftKeyboard.hide() }
                    Spacer()
                    keyboardPrintButton
                }
            }
            .alert(notice?.title ?? "",
                   isPresented: Binding(get: { notice != nil },
                                        set: { if !$0 { notice = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(notice?.body ?? "")
            }
    }

    /// 键盘上方那个「打印」——和「完成」同一条 accessory bar，永远不会重叠。
    @ViewBuilder
    private var keyboardPrintButton: some View {
        Button {
            printNow()
        } label: {
            if printer.isPrinting {
                ProgressView().controlSize(.small)
            } else {
                Text("打印").fontWeight(.semibold)
            }
        }
        .disabled(printer.isPrinting)
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
