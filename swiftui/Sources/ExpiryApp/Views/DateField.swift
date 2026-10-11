//
//  DateField.swift
//  模板页统一的日期输入控件。
//
//  ───────────── 十四轮演变的最终结论（v1.1.10 · 路线 B 定案） ─────────────
//
//  ★★★ 2026-10-11（第二十七轮）—— 用户复验 v1.1.10：
//
//      「现在日历点击完日期确实收回了，但是**选择年月的滚轮后也收回了**
//        （不应该收回，只有选择完日期后收回）」
//
//  ✔ 界面畸形已修好（浮层是正常的宽方块日历了）。
//  ✘ **收起判据错了**：滚年月也被误判成"选完日期"。
//
//  ★★★ 真根因（我上一版的注释写错了）：
//      上一版判据 = 「规范化后的『天』变了就收」，注释里我还写着
//      "左右翻月 / 滚年份 → `selection` 不参与 → 不受影响"。
//      **这句是错的**：`.graphical` 日历点顶部标题弹出的**年月滚轮**，
//      滚动时会**立即把新值写进 `selection`**（年月变、日尽量保持），
//      于是 `onChange` 触发 → 浮层被误关。
//
//  ★ 正确判据 = **区分「点网格里的某一天」和「用滚轮换月/换年」**：
//      · 点网格里的一天    → 年月**不变**，只换「日」→ 收起 ✔
//      · 滚轮换月 / 换年   → 年月**变了**          → 不收 ✔
//      · 点相邻月的灰字日期 → 年月变（系统还会翻月）→ 不收（用户还在导航，合理）
//      · 点中的是当前这天  → 值不变，`onChange` 根本不触发 → 不收
//    ➜ 判据落在：**「年月没变、只是换了某一天」才算"选完日期"。**
//      实现抽成纯函数 `LabelTemplate.shouldCollapseAfterDateChange(from:to:)`（可单测）。
//
//  ⚠️ 墓碑追加：**「值变了就收」**（滚轮会被误触发，第 26 轮）；
//     **用防抖计时器去"猜"用户滚完了没**（判据本身就该是确定的）。
//
//  ★★★ 2026-10-11（第二十六轮）—— 用户复验 v1.1.9：
//
//      「功能测试完全没问题，但是界面又畸形了」（附真机截图）
//
//  ✔ **功能对了**：点日期行能弹、选完能带动画收起、日期文字是系统色。
//  ✘ **界面畸形**：浮层变成一条 ~120pt 的**竖向细条**，箭头指着行的中段；
//    里面的 `.graphical` 日历被**横向压扁 + 裁切**（只看得见「14 / 21 / 28」一列），
//    整块浮层压在下面的快捷档位 chip 上 —— 完全没法用。
//
//  ★★★ 真根因（**不是锚点问题，是弹层内容没给宽度**）：
//
//    **iPhone 上 `.presentationCompactAdaptation(.popover)` 不会"按内容撑开"弹层。**
//    它会按锚点算出一个很窄的宽度，然后让 `.graphical` 日历**硬塞进去被压扁**。
//    `.graphical` 的固有宽度（~320pt）在普通布局里会自动生效（它自带
//    intrinsic size），但在 popover 里**不参与 sizing**，必须我们显式指定。
//
//    ➜ 社区通行且实测有效的写法 = 给日历一个 **`.frame(width: 320)`**。
//      这是"给系统一个尺寸建议"的正规用法，不是自造控件。
//
//  ★ 本版同时修掉锚点：`.popover` 挂在**满宽的 `HStack` 容器**上
//    （而不是 `Button` 自身）—— 两者叠加，浮层才既宽、又对准整行居中。
//
//  ★★ 教训（第三次同型）：**"我加了 `.frame(maxWidth:.infinity)`" ≠ "锚点变宽了"**。
//     凡"锚点类 / 尺寸类"的修饰符（`.popover` / `.sheet` / `.frame(width:)`），
//     都要独立确认**它到底作用在哪个视图、哪个阶段**。
//     ➜ 与第 23/24 轮（`.focused` 挂错对象、`.background` 挂错层）**完全同型**。
//     又一次证明：**"我加了这段代码" ≠ "这段代码在起作用"**。
//
//  ★★★ 2026-10-11（第二十五轮）—— 用户拍板走「路线 B」：
//
//      「直接上 b，但是你要自己检查全部代码，不要出现问题」
//
//  背景：v1.1.7 我押注「`@FocusState` + `.focused` 让它自己收」，**赌输了**。
//        v1.1.8 交付键盘修复后，用户开始处理日历，我逐行读代码找出了真根因：
//
//      ★★★ **`DatePicker` 根本不参与 SwiftUI 的焦点系统。**
//          苹果官方文档对 `.focused(_:)` 的定义是「视图**去争抢焦点**时更新绑定」
//          （"When focus moves to the view, the binding sets the bound value to `true`"）。
//          文本输入控件（`TextField` / `TextEditor` / `SecureField`）会去争抢焦点，
//          所以它们才有效；**`DatePicker` 不是输入控件**，永远不会争抢焦点
//          → `isFocused` **永远是 `false`**
//          → `if isFocused { isFocused = false }` **永远不执行**
//          → 「选完自动收」的代码从写下的那一刻起就是一行死代码。
//          ➜ 这正是「我加了这段代码 ≠ 这段代码在起作用」的又一例证（第 23/24 轮同病）。
//
//  ───────────────────────── 为什么最终选路线 B ─────────────────────────
//
//  用户的硬要求有两条：**「最高的苹果流畅度」** + **「全部用第一方工具」**。
//  而「日期选完自动收」这个需求，在原生 `.compact` 上**根本无法实现**：
//
//    · `.compact` 弹出的是 UIKit **私有**面板
//      （`_UIDatePickerIOSCompactViewController`），苹果**从未公开**关闭它的 API。
//      业界权威答案原话："I see no documented way of doing this right now."
//    · 苹果 HIG 是**有意**设计成「点外面确认」的：
//      "people can make multiple edits to dates and times before tapping outside
//       the view to confirm their choices."
//      ➜ 也就是说，「选完自动收」在 `.compact` 上是**逆着系统设计**走，只能靠歪招
//        （历史第 2/6/9/11 轮 = `.id()` 重建控件 → 无动画 + 样式退化，用户三次报障）。
//
//  ➜ 于是唯一诚实的做法 = **换一套公开的、可控的第一方 API**：
//
//      ★★★ 定案 = `.popover` + `DatePicker(.graphical)`（路线 B）
//
//        ① `.popover` 是**公开的第一方弹层**，`isPresented` 由我们掌握
//           → 选完直接 `showing = false` → 走的是**系统自己的 popover 转场动画**。
//           我们没有"中途插一脚"，而是**从源头就按系统的模型来**（这正是流畅度的来源）。
//        ② `.graphical` 是**公开的日历样式**，不依赖任何私有实现 →
//           不存在"重建后样式退化"。
//        ③ 主行 = 普通 `Button`，与 `List` 滚动、与收键盘 overlay 都**不冲突**。
//        ④ 日期文字用**系统语义色**（`.primary`），不碰 `Theme.brand`
//           —— 用户明确说过"日期文字是系统黑/白，不是蓝色"。
//
//  ─────────────── ⚠️ 第 11 轮（v1.1.5）用同一套 API 为什么失败 ───────────────
//
//  上一版是这么写的（`git show 6bfc114` 可查）：
//
//      .popover(isPresented: $showing, arrowEdge: .bottom) { ... }
//
//  **三个具体的错**，本版逐条修掉：
//
//    ① `arrowEdge: .bottom` 把浮层**推向屏幕上方**。
//       苹果文档：`arrowEdge` = "The edge of the attachmentAnchor that defines the
//       location of the popover's arrow." —— 箭头在浮层的**下边**，
//       意味着浮层要放在锚点**上方**。而这两行日期都排在屏幕**上半部**，
//       上方空间不够 → 系统只好硬塞 → 看起来"飘到导航栏"。
//       ➜ **本版完全不给 `arrowEdge`**，让系统按可用空间自己挑最优方向（这才是原生行为）。
//
//    ② 锚点太小、太靠内。`List` 行里那个 `Button` 的实际布局框只有文字那么高（~20pt），
//       浮层要以这么窄的一条为基准算位置。
//       ➜ 本版给主行**明确的满宽 + 标准行高**（`.frame(maxWidth: .infinity, minHeight: 24)`
//         + `.contentShape(Rectangle())`），锚点是一个稳定、方正的区域。
//
//    ③ 日期文字用了 `Theme.brand`（蓝）→ 用户报"颜色不对"。
//       ➜ 本版用 `.primary`（系统标签色，深色模式下自动变白）。
//
//  ───────────────────────────── 墓碑（一个都别再写回来） ─────────────────────────────
//
//   ① `.id(...)` 换值重建控件 —— 无动画 + 销毁浮层 + 样式退化（第 2/6/9/11 轮）；
//   ② `Menu { DatePicker }` —— Menu 只装命令，日历根本不渲染（第 7 轮）；
//   ③ 防抖计时器（`Task.sleep`）—— 自造冷却窗口（第 10/11 轮）；
//   ④ **`@FocusState` + `.focused` 收 `DatePicker` 的浮层** —— 死代码，
//      `DatePicker` 不参与焦点系统（第 23 轮，本版刚刚证伪）；
//   ⑤ `.compact` + 私有面板 —— 关不掉，只能靠歪招（第 8/9 轮）；
//   ⑥ `arrowEdge: .bottom` 硬编码 —— 会把浮层推向错误方向（第 11 轮）；
//   ⑦ 日期文字用 `Theme.brand` —— 用户要的是系统黑/白（第 11/22 轮）；
//   ⑧ `.background(手势层)` —— 被不透明的 `List` 遮住，收不到触摸（第 23 轮）。
//
//  ★★★ ⑨ **popover 内容不给宽度** —— iPhone 上 `.presentationCompactAdaptation(.popover)`
//        不会按内容撑开，会把 `.graphical` 日历**压扁成竖条**（第 26 轮用户实机截图）。
//        **永远记得给弹层内容一个 `.frame(width: 320)`。**
//  ★★★ ⑩ **把 `.popover` 挂在 `List` 行的"子控件"上** —— 锚点会是那个子控件的小框，
//        而不是整行；要挂在**撑满整行宽度的容器**上（第 11 / 26 轮）。
//  ★★★ ⑪ **「值变了就收」当收起判据** —— `.graphical` 的年月滚轮也会写 `selection`，
//        会把"正在浏览月份"误判成"选完日期"（第 27 轮）。
//        要按 **「年月是否变」** 区分：年月不变=点了网格某天（收）；年月变=滚轮导航（不收）。
//
//  ★ 一句话：**「关不掉某个系统弹层」的困境，正解是换一个公开、可控的第一方 API，
//    而不是用重建控件的歪招。**
//  ★ 另一句：**popover 是"两件事"——锚点是谁 + 内容多大。两个都要显式管。**
//  ★ 第三句：**收起判据要落在"用户做了什么操作"，而不是"某个值变没变"。**
//

import SwiftUI

/// 模板页统一的日期选择器。
///
/// **交互**：点整行 → 弹出系统日历浮层（`.graphical`）→ 点中某一天 → **带动画自动收起**。
/// **实现**：全程只用第一方公开 API —— `Button` + `.popover` + `DatePicker(.graphical)`
///          + `Text(_:format:)`。零自造控件、零重建、零定时器。
struct LabelDatePicker: View {
    let title: String
    @Binding var date: Date

    /// 日历浮层是否展开。
    ///
    /// ★ 这正是"能自动收起"的全部秘密：`popover` 的开关**归我们管**
    ///   （对比 `.compact` 的私有面板 —— 那个苹果不给 API）。
    @State private var showing = false

    /// ★ 把外部绑定的值**规范化到当天 0 点**再喂给 `DatePicker`。
    ///
    /// 为什么必须做：`Date` 是带时分秒的绝对时刻，两个「同一天」的 Date 并不相等；
    /// 业务上也**只关心日期**（`kDotsPerMM`、+N 天规则都按天算）。
    /// 统一压到 0 点后：比较稳定、写入语义干净、`onChange` 的「值变了」判据才准确。
    private var day: Binding<Date> {
        Binding(
            get: { AppCalendar.shared.startOfDay(for: date) },
            set: { date = $0 }
        )
    }

    /// 日期文字的展示格式：`2026/10/30`。
    ///
    /// ★ 用**第一方 `FormatStyle`**，而不是自己拼字符串 —— 补零 / locale / 公历
    ///   它自带，并且天然与系统语言环境一致（用户从第二轮起就要求统一斜杠格式）。
    /// ⚠️ 别用 `Text(date, format: .dateTime…)` 的"年月日"写法 —— 中文环境下
    ///   会输出「2026年10月30日」，不是用户要的斜杠形式。
    private static let slashy = Date.FormatStyle(date: .numeric, time: .omitted)
        .year().month().day()

    var body: some View {
        // ★★★ 关键结构：**外层是满宽容器，`.popover` 挂在容器上**（不挂在 `Button` 上）。
        //
        //   ⚠️ 为什么不能直接把 `.popover` 挂在 `Button` 上 ——
        //      `.popover` 的锚点 = **它附着视图的 layout frame**。
        //      第 11 / 25 两轮我都是挂在 `Button`（或它的行内小控件）上，
        //      即便外面套了 `.frame(maxWidth:.infinity)`，系统取到的仍是
        //      **按钮自身那个又窄又高的矩形** → 箭头只指着行的中段。
        //   ➜ 必须让 `.popover` 附在一个**真正撑满整行宽度**的容器上。
        HStack(spacing: 0) {
            Button {
                showing = true
            } label: {
                HStack {
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    // ★ 日期文字 = **系统标签色**（浅色下黑、深色下白），不是品牌蓝。
                    Text(day.wrappedValue, format: Self.slashy)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                // ★ 撑满矩形，保证整行都能点中。
                .contentShape(Rectangle())
            }
            // ★ `.plain`：不要给文字染上系统强调色（那会变成"蓝字白底按钮"，
            //   和用户要的"系统黑/白"冲突）。
            .buttonStyle(.plain)
        }
        // ★★ 锚点本体：**满宽 + 明确行高** —— 这才是给 `.popover` 用的矩形。
        .frame(maxWidth: .infinity, minHeight: 24)
        // ★★★ 第一方弹层。`isPresented` 归我们掌控 → 能主动、带动画地收起。
        //
        //   ⚠️ **不传 `arrowEdge`** —— 默认 `nil` 即"系统自选最优方向"（苹果文档原文
        //      "the system allowing any arrow edge"）。硬编码 `.bottom` 会强制把浮层
        //      放到锚点**上方**，屏幕上半部的行就没地方放 → "飘到导航栏"（第 11 轮）。
        //
        //   ⚠️ **不改 `attachmentAnchor`**，保持默认 `.rect(.bounds)` ——
        //      锚点 = 上面那个满宽容器的 bounds。
        .popover(isPresented: $showing) {
            DatePicker(title, selection: day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                // ★★★ 第二十六轮的**真凶**：popover 内容必须**显式给宽度**！
                //
                //   实测现象（用户截图）：浮层变成一条 ~120pt 的**竖向细条**，
                //   里面的 `.graphical` 日历被**横向压扁 + 裁切**（只能看见
                //   「14 / 21 / 28」一列），完全没法用。
                //
                //   根因：**iPhone 上 `.presentationCompactAdaptation(.popover)` 不会
                //   让弹层"按内容撑开"** —— 它会按锚点算一个很窄的宽度，
                //   然后把 `.graphical` 日历**硬塞进去压扁**。
                //   `.graphical` 的固有宽度（~320pt）在普通布局里会自动生效，
                //   但在 popover 里**不参与 sizing**，必须我们显式指定。
                //
                //   ➜ 社区通行且实测有效的写法：给日历一个 `.frame(width: 320)`。
                //     （这是"给系统一个尺寸建议"的正规用法，不是自造控件。）
                .frame(width: 320)
                .padding()
                .presentationCompactAdaptation(.popover)
                .onChange(of: day.wrappedValue) { oldValue, newValue in
                    // ★★★ 收起判据（第二十七轮修正）：
                    //   **只有「点网格里的某一天」才收起；用滚轮换月/换年不收起。**
                    //
                    //   ⚠️ 上一版判据是「规范化后的『天』变了就收」，**是错的**：
                    //      `.graphical` 日历点顶部标题弹出的**年月滚轮**，
                    //      滚动时会**立即把新值写进 `selection`**（年月变、日尽量保持）
                    //      → `onChange` 触发 → 浮层被误关。用户报的正是这个。
                    //
                    //   ➜ 正解 = 用年月是否改变来区分两种操作（见 `shouldCollapseAfterDateChange`）：
                    //      · 点网格里的某天 → 年月不变、只换天  → 收起 ✔
                    //      · 滚轮换月 / 换年 → 年月变了          → 不收 ✔
                    //      · 点相邻月的灰字  → 年月变（系统会翻月）→ 不收（用户还在导航）
                    //      · 点中的是当前这天 → 值不变，`onChange` 根本不触发 → 不收
                    //
                    //   ⚠️ 不写 `Task.sleep` / 防抖：判据是确定的，不需要冷却窗口。
                    //   ⚠️ 绝不重建控件、绝不 `.id()`。
                    if LabelTemplate.shouldCollapseAfterDateChange(from: oldValue, to: newValue) {
                        showing = false
                    }
                }
        }
    }
}

/// 日期单位图例：英文缩写 `Y / M / D`。
///
/// ⚠️ **从未接入任何真实页面**（只在 `#Preview` 里出现过）。保留原因：
///   当初想解决「滚轮单位是中文」，但系统 DatePicker 的面板无法稳定外挂图例。
///   **别当死代码删** —— 这是有意留的备选。
struct UnitLegend: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(["Y", "M", "D"], id: \.self) { unit in
                Text(unit)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .allowsHitTesting(false)
    }
}

#Preview {
    NavigationStack {
        Form {
            Section("日期") {
                LabelDatePicker(title: "原始保质期", date: .constant(Date()))
                LabelDatePicker(title: "最佳使用时间", date: .constant(Date()))
                UnitLegend()
            }
        }
    }
}
