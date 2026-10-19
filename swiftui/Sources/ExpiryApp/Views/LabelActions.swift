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

// MARK: - 菜单式选择行（整行可点）

/// 菜单式选择行：右侧显示当前值与上下箭头，**行右半区都是点击热区**。
///
/// ★★★ 2026-10-13（用户第一次反馈）：「要点击（红框内的）小箭头才能拉出菜单，
///   影响使用体验」—— 根因是原生 `Picker(.menu)` 在 `List` 里只有尾部
///   一小块区域响应点击。改用 `Menu` + `.contentShape(Rectangle())` 扩大热区
///   （用户原话：「点击**右边这附近**都可以拉出」）。
///
/// ★★★ 2026-10-13（用户第二次反馈）：「点击后文字都消失了……字体这个位置
///   要**锁定**，不参与点击弹出菜单和动画」——
///   根因：文字 / 当前值放在 `Menu` 的 **label** 里时，iOS 在菜单弹出的
///   「morph 动画」中会把 label 整块吃掉（snapshot 成锚点色块），
///   行内文字随之消失。
///   ➜ 修法 = **内容与热区分家**：
///     · `Menu` 的 label 只放一块**透明热区**（`Color.clear`）——
///       系统动画想怎么 morph 这块透明色块都行，**看不见就伤不到**；
///     · 文字 / 当前值 / 箭头放在 `Menu` **外部**（`ZStack` 的静态层），
///       并 `allowsHitTesting(false)`（不挡点击）—— 系统的菜单动画
///       **碰不到它们** → 位置永久锁定、永不消失。
///   ⚠️ 别把内容挪回 label 里 —— 那正是被否掉的样子。
///   ⚠️ 静态层里**必须**有 `allowsHitTesting(false)`，否则那层会把
///      所有点击吃掉，菜单反而拉不出来。
///
/// ★★★ 2026-10-13（用户第三次反馈）：「他弹出的时候能不能**从最右侧弹出**，
///   而不是中心点弹出呢？」——
///   系统的菜单弹出位置由 label 的 frame 决定（菜单会居中于锚点矩形）：
///     · 上一版 label = **整行** → 菜单从整行中心展开，把行首的
///       「奶制品类型」等标签文字盖住（用户截图圈出的问题）；
///     · ✅ 现在把热区收成**贴右的固定宽度** → 锚点靠右 → 菜单从右侧展开，
///       行首文字不再被盖，观感也与系统「点值区域弹菜单」的习惯一致。
///   ⚠️ `hotZoneWidth` 是权衡值：太宽 → 菜单又跑回中间；太窄 → 可点区域变小。
///      **别改回 `.frame(maxWidth: .infinity)`**（= 锚点全行 = 菜单居中）。
struct MenuPickerRow<Value: Hashable>: View {
    let title: String
    let options: [Value]
    let optionLabel: (Value) -> String
    @Binding var selection: Value?

    /// 外层 `.disabled(...)` 的状态 —— 自绘内容要照着系统样式给出「禁用变灰」。
    @Environment(\.isEnabled) private var isEnabled

    /// 透明热区的宽度（贴右）。取 160pt：iPhone 上行内容宽约 320pt，
    /// 它覆盖「值 + 箭头」及周遭的右半区，菜单左缘也刚好落在标签文字右侧。
    /// ⚠️ 泛型类型里**不能写 `static let`**（stored property 不被支持，
    ///   CI 报过：`static stored properties not supported in generic types`）
    ///   —— 必须写成计算属性。
    private static var hotZoneWidth: CGFloat { 160 }

    var body: some View {
        ZStack(alignment: .trailing) {
            // ① 静态展示层（占满整行；不参与命中测试、不参与菜单动画）——
            //    系统的菜单 morph 动画只作用于 ② 的透明热区，碰不到这一层。
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let selection {
                    Text(optionLabel(selection))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .opacity(isEnabled ? 1 : 0.35)
            // ⚠️ 放行命中测试 —— 让点击穿到下面的透明热区上。
            .allowsHitTesting(false)

            // ② 透明热区（贴右、固定宽）—— 只负责接收点击 / 承载系统菜单动画。
            //    它是 `Menu` 的 label，frame 决定菜单弹出的水平位置（见文件头注释）。
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(optionLabel(option)).tag(Optional(option))
                    }
                }
            } label: {
                Color.clear
                    .frame(width: Self.hotZoneWidth, height: 28)
                    .contentShape(Rectangle())
            }
        }
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
///   确实不需要：两条路都在 `KeyboardDismiss.swift` 的第一方实现里 ——
///   滑动走系统 `.scrollDismissesKeyboard`、点空白走容器上的 `onTapGesture`，
///   都**直接写页面 `@FocusState`** → 键盘是**动画**收起的，不再需要这个快捷键。
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
    /// ★★★ 2026-10-17 新增（用户功能 2）：**确认打印并发送成功后**回调。
    ///
    ///   加工页（解冻 / 二发）用它把「原材料」记录标为已用完 ——
    ///   用户要求「确认打印前增加『原材料是否用完』选项，已用完就在效期管理里选择已用完」。
    ///   ⚠️ 只在**打印成功**后调用（失败不消耗原材料）。
    var onConfirmed: (() -> Void)? = nil

    @ObservedObject private var printer = PrinterService.shared

    @AppStorage("printCopies") private var copies: Int = 1
    @AppStorage("printDensity") private var density: Int = 0
    @AppStorage("paperType") private var paperType: Int = 1

    /// ★★★ 2026-10-18（用户第 4 条）：**统一提示状态机**。
    ///   为什么不继续用 `notice: Notice?` + 再加一个 `.alert`：
    ///   **同一个视图上挂两个 `.alert` 会互相覆盖**（只有最后一个生效），
    ///   所以把「普通提示」和「同名未过期确认」合并到同一个 alert 槽里。
    @State private var prompt: Prompt?
    /// ★★★ 2026-10-17（用户功能 1）：待确认的打印草稿。
    ///   非 nil → 弹「确认打印」窗（文字预览 + 份数）；确认后才真正发送。

    /// 统一提示（一个 alert 槽同时承载「普通提示」和「同名物料确认」）。
    private enum Prompt {
        case notice(title: String, message: String)
        /// ★ 2026-10-18（用户第 4 条）：首项 = 待打印草稿，次项 = 同名未过期记录。
        case duplicate(LabelDraft, [LabelRecord])


        var title: String {
            switch self {
            case .notice(let t, _): return t
            case .duplicate: return "存在未过期物料"
            }
        }

        var message: String {
            switch self {
            case .notice(_, let m): return m
            case .duplicate(_, let list):
                let names = Set(list.map(\.title)).joined(separator: "、")
                return "「\(names)」还有 \(list.count) 条未过期。要把这批标记为已用完吗？"
            }
        }
    }

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
            .alert(prompt?.title ?? "",
                   isPresented: Binding(get: { prompt != nil },
                                        set: { if !$0 { prompt = nil } })) {
                if case .duplicate = prompt {
                    Button("标记已用完") { finishDuplicate(useUp: true) }
                    Button("不用", role: .cancel) { finishDuplicate(useUp: false) }
                } else {
                    Button("好", role: .cancel) {}
                }
            } message: {
                Text(prompt?.message ?? "")
            }
            // ★★★ 2026-10-17（用户功能 1）：点「打印」先弹确认窗（预览 + 份数），
            //   不再直接发送到打印机。
            // ★★★ 2026-10-18（用户第 5 条 + 再订正）：
            //   · 「不要从下往上，做成**悬浮窗口**（第一方工具哈！）」→ 先试了 `.popover`；
            //   · 再订正：「**不是从制作人这里弹出来，而是独立的窗口**，类似 SideStore 那个
            //     Install App 弹窗」→ `.popover` 会带一个指向锚点的箭头，不行。
            //   ➜ 现在用 **`.overlay` + 全屏遮罩 + 居中卡片**：
            //     iOS 公开 API 里"居中弹窗"只有 `.alert`（放不下预览和份数 Stepper），
            //     所以用**系统材质（`.thinMaterial`）+ 系统按钮**复现系统 alert 的观感 ——
            //     材质、圆角、按钮全部来自第一方，没有自绘色块。
            // 打印确认已改成**系统 alert**（见上面 `prompt` 的 `.confirmPrint` 分支）。
    }

    // MARK: 动作

    private func printNow() {
        guard printer.isConnected else {
            prompt = .notice(title: "还没有连接打印机",
                            message: "请到「打印机」标签页扫描并连接硕方 T50 Pro，再回来打印。")
            return
        }
        // 校验（必填项）仍在这一步 —— 校验不过时页面自己会弹提示。
        guard let draft = build() else { return }

        // ★★★ 2026-10-18（用户第 4 条）：
        //   「打印**标题完全相同**的标签时，提示上一批物料是否已用完，
        //     『存在未过期物料，是否已用完？』，**点击完后再弹打印的弹窗**」
        //   ➜ 只查**同标题 + 未用完 + 未过期**的记录（已用完/已过期的不啰嗦）；
        //     有 → 先弹 alert 问「要不要标记已用完」，答完再弹打印确认窗。
        let sameTitle = ExpiryStore.shared.records.filter {
            $0.title == draft.data.title
                && $0.usedAt == nil
                && $0.dueDate > Date()
                && $0.id != draft.record.id
        }
        if sameTitle.isEmpty {
            presentPrintConfirm(draft)
        } else {
            prompt = .duplicate(draft, sameTitle)
        }
    }

    /// 同名未过期物料的确认结果 → **答完再弹打印确认窗**（用户要求）。
    private func finishDuplicate(useUp: Bool) {
        guard case let .duplicate(draft, list) = prompt else { return }
        if useUp {
            list.forEach { ExpiryStore.shared.markUsed($0) }
        }
        prompt = nil
        // ★ 上一个 alert 还在关闭动画里，**立刻**再 present 会被系统吞掉。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            presentPrintConfirm(draft)
        }
    }

    /// 弹**系统 alert**（`UIAlertController`）做打印确认。
    ///
    /// ★★★ 2026-10-19（用户）：「就是要这个样式完全没错，**但是不能输入打印份数了吗？**」
    ///   ➜ SwiftUI 的 `.alert` 放不了输入框，但 **UIKit 的 `UIAlertController` 可以**
    ///     （`addTextField`）—— 同样是系统 alert、同样的外观，只是多了一行**系统输入框**。
    ///   ➜ 数字键盘、默认填上次的份数、1~20 之间钳制。
    private func presentPrintConfirm(_ draft: LabelDraft) {
        // ★ 2026-10-19（用户）：「它左边或者上面可以加个**输入打印份数的提示**吗？」
        //   ➜ alert 的输入框左边塞不进东西（系统布局），但可以在 `message` 末尾加一行，
        //     它正好显示在输入框**正上方**。
        //   ⚠️ 输入框本身的**高度/宽度改不了** —— `UIAlertController` 的 textField
        //     尺寸由系统决定（改 frame 会被忽略），只能改字号/对齐/键盘类型。
        let message = Self.confirmMessage(for: draft) + "\n\n打印份数（1~20）"
        let alert = UIAlertController(title: "确认打印",
                                      message: message,
                                      preferredStyle: .alert)

        alert.addTextField { field in
            field.text = "\(self.copies)"
            field.textAlignment = .center
            field.placeholder = "打印份数"
            // 输入框高度是系统的（改不了），只能把字号调小一点，视觉上轻一些。
            field.font = .systemFont(ofSize: 15, weight: .regular)

            // ★★★ 2026-10-19（用户）：「这个界面有别的办法了没，**我不想要键盘**」
            //   ➜ 给输入框挂一个**空的 `inputView`**：点它时弹出来的不是系统键盘，而是这个空视图。
            //     `inputAccessoryView`（下面的步进器）仍然会跟着显示 ——
            //     所以效果是「点一下 → 只出现 −/＋ 步进器，不弹数字键盘」。
            //   ➜ 光标也一并隐藏（`tintColor = .clear`），因为它已经不能直接打字了。
            field.inputView = UIView()
            field.tintColor = .clear

            // ★★★ 2026-10-19（用户）：「这个输入框左右能增加『增加、减少』按钮吗？」
            //   ➜ `UIAlertController` 的输入框**只能独占一行**（左右是系统留白，塞不进按钮）。
            //   ➜ 第一方的替代做法：给它挂 **`inputAccessoryView`**（键盘正上方那条），
            //     里面放 **`UIStepper`** —— 系统步进器本身就是「− / +」，
            //     点它 → 数字直接回填到输入框。
            let stepper = UIStepper()
            stepper.minimumValue = 1
            stepper.maximumValue = 20
            stepper.stepValue = 1
            stepper.value = Double(max(1, min(20, self.copies)))
            stepper.addAction(UIAction { [weak field] action in
                guard let field,
                      let sender = action.sender as? UIStepper else { return }
                field.text = "\(Int(sender.value))"
            }, for: .valueChanged)

            // 包一层容器让步进器居中（accessoryView 默认会被拉满整行）。
            let holder = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 52))
            holder.autoresizingMask = .flexibleWidth
            stepper.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(stepper)
            NSLayoutConstraint.activate([
                stepper.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
                stepper.centerYAnchor.constraint(equalTo: holder.centerYAnchor)
            ])
            field.inputAccessoryView = holder
        }

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "打印", style: .default) { [weak alert] _ in
            let typed = alert?.textFields?.first?.text ?? ""
            let count = max(1, min(20, Int(typed) ?? self.copies))
            self.confirmPrint(draft, copies: count)
        })

        Self.topViewController()?.present(alert, animated: true)
    }

    /// 确认窗的正文（与标签同源：标题 / 各行 / 制作人）。
    /// ⚠️ `LabelRow.label` 自带全角冒号，别再补。
    private static func confirmMessage(for draft: LabelDraft) -> String {
        var lines = [draft.data.title, ""]
        for row in draft.data.rows {
            lines.append("\(row.label)\(row.value)")
        }
        if !draft.data.maker.isEmpty {
            lines.append("")
            lines.append(draft.data.maker)
        }
        return lines.joined(separator: "\n")
    }

    /// 当前最顶层的控制器（用来 present UIKit alert）。
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }

    /// 用户在确认窗里点了「打印 N 份」。
    private func confirmPrint(_ draft: LabelDraft, copies chosen: Int) {
        let count = max(1, chosen)
        // ★ 记住这次选的份数（下次弹窗默认用它）。
        copies = count

        printer.printLabel(pdf: draft.pdf(),
                           fileName: draft.fileName,
                           copies: count,
                           density: density,
                           paperType: paperType,
                           record: draft.record) { ok, message in
            if ok {
                // ★ 功能 2：打印成功后才消耗「原材料」。
                onConfirmed?()
                prompt = .notice(title: "已发送到打印机",
                                message: "\(draft.data.title)\n份数 \(count) · 浓度 \(density == 0 ? "自动" : "\(density)")")
            } else {
                prompt = .notice(title: "打印失败",
                                message: message.orFallback("请检查打印机状态后重试。"))
            }
        }
    }
}

// MARK: - 打印确认
//
// ★★★ 2026-10-19：确认窗已改成**系统 alert**（用户选 A：100% 原生）。
//   原来的 `PrintConfirmSheet`（自绘卡片 + Stepper）整段删除 —— 系统 alert 放不下
//   预览表格和份数选择，所以：预览放进 `alert` 的 message（多行文本），
//   份数改用「打印机」页里的设置（`@AppStorage("printCopies")`）。
