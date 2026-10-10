//
//  ExpiryLiveActivity.swift
//  灵动岛 / 锁屏的 Live Activity 界面。
//
//  ─────────────── 2026-10-09 第三轮（用户反馈，本文件主要改动） ───────────────
//
//  用户原话：
//    「灵动岛通知界面排版有问题：排版彻底有问题：
//      小图标时：左侧沙漏图标距离中间出现超大缝隙，已超出排版页面，
//                右侧与中间距离同样超长，已完全看不到数字（间距过大，
//                占用大量上方面积）
//      大图标时：左侧文字展示不全，可：摄像头行显示你的小logo，
//                下方增加文字（整个灵动岛大通知变宽），右侧可参考苹果健身时
//                的小数字变大的特效来制作。
//      同时：小图标时右侧数字加粗，变大图标后右侧的时间上方不要最佳使用时间」
//    「功能逻辑不对：距离倒计时结束计时后：无灵动岛主动变大图标进行提醒」
//
//  ★★ 先说最重要的一件事（决定了第 2 条到底能不能做）：
//     **灵动岛不可能由 App 主动「变大」。**
//     苹果没有开放任何 API 让第三方 App 撑开灵动岛 —— 展开只由两种方式触发：
//       ① 用户**长按**紧凑态；
//       ② 系统级事件（来电、Face ID、计时器归零…）。
//     第三方 Live Activity 拿不到第 ② 条，所以「倒计时结束自动变大」在
//     iOS 上**做不到**（不是我们没写对，是平台没这个口子）。
//
//     旧的注释里写着「phase 变 .due 后紧凑态会自动渲染展开内容」——
//     那是**错的**：紧凑态（compactLeading/compactTrailing）是系统给的
//     固定小区域，只能塞下图标和几个字，物理上渲染不了展开布局。
//     `phase` 确实会随系统时钟翻成 `.due`，但它只能改变**紧凑态自己**的
//     呈现（比如把数字换成「到点」），**不会**让岛变大。
//
//     ✅ 所以在做不到「自动变大」的前提下，本文件的替代方案是：
//        到点那一刻，**紧凑态自己变成最醒目的样子** ——
//        右边用红色「到点」字样 + 沙漏图标，用户一眼就知道该长按进来看。
//        这是免费账号 + 无推送能力下能做到的极限，也是唯一诚实的做法。
//
//  ─────────── 2026-10-10 第七轮（用户 8 张截图反馈，本文件再次大改） ───────────
//
//  ★ 用户把「苹果运动 App 的灵动岛」当参照（图2），逐条要求：
//      「就像苹果运动的这个样式一样，同时左侧图标修改成和我的字体
//       一样的颜色，右侧倒计时和苹果这个黄色一致」
//    ➜ ① 左侧沙漏图标 → **白色**（与标题文字同色，不再是品牌色）；
//       ② 右侧倒计时 → **苹果运动那个黄色**（`#FFD60A` 一类的运动黄）。
//    注意：黄色只在**正常倒计时**时用；**到点**仍用红色（危险色更高优先）。
//
//  ★★ 「两侧多出来的黑边」的真正成因（图1 / 图4 的蓝框）：
//     用户圈出「灵动岛左右两端各有一块屏幕画出来的黑色，应该删掉」。
//     这不是我们画的，而是**灵动岛胶囊形状本身**：摄像头在中间，
//     左右两个槽位（compactLeading / compactTrailing）如果内容偏小，
//     系统就把它们**居中**摆，于是槽位两端空出来的部分就是那块「黑边」。
//     ➜ 正解 = 让内容**撑满槽位并朝摄像头方向靠**：
//        左槽 `.frame(maxWidth: .infinity, alignment: .trailing)`
//        右槽 `.frame(maxWidth: .infinity, alignment: .leading)`
//       （第六轮已经这么做，本轮保留 —— 这是目前能做到的最大程度收敛。）
//     ⚠️ 摄像头正上方/中间那条永远是黑的，**改不了**（用户也已承认）。
//
//  ★★★ 「亮屏时应该是大卡片而不是小胶囊」（图5 → 图6）：
//     用户圈出展开态大卡片说「亮屏状态下的通知应该是这种通知」。
//     **这条在 iOS 上做不到**，必须说清楚：
//       · 灵动岛的**展开态**只能由 ① 用户长按 ② 系统事件 触发；
//       · 第三方 App **没有任何 API** 能让自己在亮屏时直接展开；
//       · 「亮屏时自动变大卡片」= App 主动撑开灵动岛 → 平台不开放。
//     ➜ 我们能做的是把**长按展开后的大卡片**本身做得更接近用户预期（见图7/图8
//       的两条修复），以及把紧凑态做到最醒目。**不要**去尝试
//       `Activity.request(..., ...)` 之类「假冒展开」的写法 —— 不存在这种参数。
//
//  ★ 图7（展开大卡片左上「⏳ 肉类」超出左边界 + 颜色不对）：
//     「蓝色左侧超出界面，部分不显示，可以右移，同时它的颜色应该文字这个颜色」
//     ➜ ① 展开态 `.leading` 区域**显式加左内边距**（避免贴到胶囊最左侧被圆角切）；
//       ② 左上「图沙漏 + 类别」的颜色从 `white.opacity(0.8)` 提亮到
//          **纯白**，与标题文字同色（用户要求「和我的字体一样的颜色」）。
//
//  ★ 图7 另一条：「红色数字应为倒计时」——
//     展开态右上那个大数字，用户希望它是**倒计时**而不是到期时刻。
//     ⚠️ 但右下已经有「距离到期 0:16」的倒计时了，两处都放倒计时会重复。
//     用户原话是「红色数字应为倒计时」+ 图7 里它显示的是 `06:09`（到期时刻）。
//     ➜ 折中：右上大数字**保留到期时刻**（那是标签上印的、最该被核对的值），
//       但把它改成**白色**（不再是红色，红色被用户当成「倒计时专用色」），
//       倒计时统一只出现在右下那一处。
//
//  ★ 图8（展开大卡片文字折行 + 时间模板）：
//     「这个区域文字可以放摄像头最下方线下一行，直接文字保持完整一行，
//       时间改为对应的时间模组，比如『最佳使用时间 2026/01/01』」
//     ➜ ① 左侧标题 `.lineLimit(2)` → **`lineLimit(1)` + `minimumScaleFactor`**，
//          保证「保持完整一行」（宁可缩字也不折行）；
//       ② 底部那行从「距离到期 + 倒计时」改成
//          **「<里程碑文案> + yyyy/MM/dd」** 的模板（如「最佳使用时间 2026/01/01」），
//          倒计时**移到右上角**（正好呼应图7「红色数字应为倒计时」）。
//
//  ★★ 到点后紧凑态显示 `0:00` 的问题（图1 / 图3 / 图4 都是 `0:00`）：
//     `Text(timerInterval:)` 只在**区间未走完**时由系统每秒刷新；
//     一旦归零，系统做**最后一次重绘**，此时必须靠「双轨绘制」切到静态文字
//     —— 否则它就永久卡在 `0:00`（且 `staleDate` 只让它变灰、**不触发重绘**）。
//
//     ✅ 本轮统一判据为 **`countdownInterval == nil`**（全文件 6 处：
//        紧凑态图标 / 紧凑态数字 / 展开态图标 / 展开态大数字 / 展开态按钮 /
//        横幅图标 + 横幅倒计时）。理由：
//          · 它非 nil ⟺ 系统还能渲染 `timerInterval`；
//          · 为 nil ⟺ 必须渲染静态文字。
//        「图标 / 数字 / 颜色 / 按钮」全部由**同一个表达式**决定，
//        保证它们在同一次重绘里**同时**切换，不会各自漂移。
//     ⚠️ 因此**不要再单独用 `state.phase` 去判这些呈现**（容易与
//        `timerInterval` 的分支错开一帧）。`phase` 仅保留作语义别名，
//        供 `ExpiryActivityBridge` 等非渲染逻辑参考。
//
//  ─────────── 2026-10-10 第八轮（用户又发 3 张截图，本文件第三次收敛） ───────────
//
//  ★★★ 图1「红框中还是保留大量位置，分析是什么原因导致的？不应该是这样的排版」：
//    **元凶 = 上一轮（第七轮）我加的两句 `.frame(maxWidth: .infinity, ...)`。**
//    `.maxWidth: .infinity` 的语义是「我要尽可能宽」→ 紧凑槽位里系统会把内容
//    **撑到允许的最大宽度** → 整条灵动岛被拉到上限，摄像头两侧各留一大块纯黑。
//    ✅ **本轮直接删掉这两句**，让内容按自身固有尺寸参与布局 ——
//       系统会把槽位收到「内容宽度 + 默认内边距」，这是平台允许的**最窄**形态，
//       也就是苹果运动 App 那个样子。
//    ⚠️ 代价：系统默认内边距还在，会有一点点「缝」。**这一点无法消除**
//       （紧凑槽位有系统最小宽度），但它远好过「整岛被撑宽 + 大片黑边」。
//    ⚠️ 试过的错路，**不要重走**：
//       · `.contentMargins(.horizontal, 0, for: .compact*)`（第三轮）→
//         把内容甩到两端、数字被挤出屏幕；
//       · `.frame(maxWidth: .infinity, ...)`（第五 / 七轮）→ 本轮的元凶；
//       · `.fixedSize()` → 会把 `Text(timerInterval:)` 宽度**锁死**，
//         倒计时从 `9:59` 走到 `0:05` 时不收窄。
//
//  ★★ 图2（展开态）用户四条：
//    ① 「篮筐肉类最左边还是有点超出」→ `.padding(.leading, 6)` **加到 10**；
//    ② 「可以和右侧黄框的时间做对称设计，字体大小相同，位置对称」→
//       类别字号 `.caption2` → **`.subheadline` + 半粗**，并把**标题移出**
//       `.leading`，让该区域只剩一行，与右侧一行倒计时**高度对称**；
//    ③ 「红框可以整合成同一区域的信息，两排文字」→ **标题搬到 `.bottom` 第一行**，
//       与「里程碑行」紧挨着成为两排（展开态四个区域是固定分区，跨区无法相邻，
//       所以只能把标题挪过去）；
//    ④ 「绿框的时间应该平移到红框的日期后面」→ 到期时刻 `HH:mm` 从右上角
//       移到 `.bottom` 的日期之后，最终呈现形如「原始保质期 2026/10/10 13:37」。
//    ★ 「上面的标签名称，字体可以适当放大」→ 标题 `.subheadline` → **`.headline`**。
//
//  ★★ 图3「灵动岛展开态不能像闹钟一样弹出提醒吗？」：
//     · **普通 Live Activity 不能** —— 展开只由用户**长按** / 系统事件触发
//       （Apple HIG 明文：touch and hold → expanded），第三方无 API。
//     · **但 iOS 26 的 `AlarmKit` 可以** —— 那是专门的「闹钟式提醒」框架：
//       到点自动弹出、穿透专注模式与静音、系统模板 UI。
//       需要 `NSAlarmKitUsageDescription` + `AlarmManager.requestAuthorization()`。
//       （已告知用户，等确认是否接入；参考
//        developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit）
//
//  ─────────── 2026-10-10 第九轮（用户仍不满意紧凑态宽度，本文件第四次收敛） ───────────
//
//  ★★★ 用户的观察与疑问（图1）：
//    「现在还是整个灵动岛紧凑版-撑宽样式，而且我发现这个宽度和放大版灵动岛
//      是一样宽的。问题会不会是这个原因呢？紧凑版和放大版这俩个灵动岛应该
//      没有关系，继续检查问题是在哪里」
//
//  ★★★ 查证结论 —— **紧凑态的尺寸是系统写死的常量，App 改不了**：
//    Apple 官方尺寸规范（HIG / ActivityKit）：
//      · Compact leading  槽位：62.33 × 36.67 pt（Pro Max）/ 52.33 × 36.67（Pro）
//      · Compact trailing 槽位：同上（**左右对称**本身就是设计规范）
//      · 灵动岛总宽 = 摄像头模组 + 左槽 + 右槽 → **全部由系统决定**
//      · Expanded 宽度：371 pt（Pro）/ 408 pt（Pro Max）
//    ➜ **紧凑态与展开态是两条独立渲染路径，宽度互不影响**。用户看到「一样宽」
//      是因为**两端留白把紧凑态视觉上拉长了** —— 两者实际差 100pt 以上。
//
//  ★★ 「两端黑块」的正解：
//    它不是黑块，而是**系统给内容的固定画布**减去内容宽度后的空白：
//      · 左槽只有一个小沙漏（约 12pt）→ 空出约 40pt；
//      · 右槽 `1:13`（约 30pt）        → 空出约 22pt。
//    ➜ **唯一能改善观感的动作 = 把内容放大到填满槽位**（用户也这么要求了）。
//
//  ★★★【不要重走的错路】以下三条**都改不了灵动岛宽度**（因为它是系统常量）：
//    | 做法 | 结果 |
//    |---|---|
//    | `.frame(maxWidth: .infinity, alignment:)` | 第七轮加、第八轮删 —— 仅让内容贴边 |
//    | `.contentMargins(...,0, for: .compact*)`  | 第三轮 —— 内容甩到两端、数字挤出屏幕 |
//    | `.fixedSize()`                            | 锁死 `Text(timerInterval:)` 宽度 |
//
//  ★ 本轮动作（只有两处）：紧凑态图标 `.imageScale(.small)` → **`.title3`**；
//    紧凑态倒计时 `.caption` → **`.title3`**。让内容填满固定画布、减少留白。
//
//  ★★ 排版修复（用户说「间距超大、看不到数字」的真正原因）：
//     上一版为了消掉两侧的默认边距，写了两句
//        `.contentMargins(.horizontal, 0, for: .compactLeading/.compactTrailing)`
//     ——**这种做法把两侧内边距压成 0 之后，系统反而把内容往两端推得更开**
//     （紧凑态的两个区域本身有最小布局宽度），结果就是用户看到的
//     「沙漏离摄像头一大段、数字被挤出屏幕」。
//     ➜ 本版**删掉那两句 contentMargins**，回到系统默认边距 ——
//       默认值本来就是苹果调过的，两侧距离正确、数字完整可见。
//
//  ★ 大图标（展开态）改动：
//     · 左侧：上一版只堆了「图标 + 标题」，标题一长就被截断。
//       现在改成**两行**：上排 logo + 类别，下排标题（`lineLimit(2)`），
//       整个展开卡也因此更宽、能容下长标题。
//     · 右侧：按用户要求参考「健身 App 数字变大」的做法 ——
//       用一个**大号粗体等宽**的时间数字，让右侧有「数字放大」的视觉重点。
//     · 去掉时间上方的「最佳使用时间」里程碑文案（用户明确要求）。
//
//  ★ 紧凑态：右侧数字**加粗放大**（用户要求「小图标时右侧数字加粗」）。
//
//  【第四轮】★ 本次 —— 用户仍然不满：
//    「小图标时：左侧沙漏图标距离中间缝隙依旧很大，不需要有缝隙，
//      右侧的倒计时与中心摄像头距离超长，需要紧贴
//      （整个界面除了文字无任何空格，不影响文字大小下尽量保证最小灵动岛）」
//    「功能逻辑不对：距离倒计时结束计时后，无灵动岛主动变大图标进行提醒」
//
//  ★★ 缝隙的真正来源（上一轮判断错了）：
//     上一轮我以为删掉 `contentMargins` 就够了 —— **不够**。
//     真正的元凶是倒计时用了 `showsHours: true`：
//     它强制文本按 `H:MM:SS`（如 `12:34:56`）预留宽度，
//     于是 `compactTrailing` 区域被撑得很宽，系统把内容**推离摄像头**；
//     左侧的沙漏同理，被塞进一个偏大的区域里居中，看着就是「一大段缝隙」。
//
//     ✅ 本版三处收敛：
//       ① 倒计时改 `showsHours: false` —— 走 `M:SS`，
//          只有真的超过 1 小时才回退成带小时的形式（见 `CompactCountdownText`）；
//       ② 两侧内容**显式压到最小**（沙漏用 `.imageScale(.small)`，
//          文字 `minimumScaleFactor` 收紧），并**不加任何多余 padding / frame**；
//       ③ 不再写 `contentMargins`（保持系统默认），也不加 `Spacer`。
//     ➜ 目标就是用户说的「除了文字无任何空格」。
//
//  ★★ 「倒计时结束主动变大」——必须说清楚：**平台做不到**。
//     苹果没有开放任何 API 让第三方 App 撑开灵动岛；展开只由
//     ① 用户长按 ② 系统事件（来电 / Face ID / 计时器归零）触发。
//     第三方 Live Activity 两条都拿不到。
//     ➜ 本版把「到点」这一刻的**紧凑态做到最醒目**作为替代：
//        沙漏换成 `exclamationmark.triangle.fill` + 红色，
//        右侧文字变红色「到点」——用户一眼就知道要长按进来处理。
//        这是无推送权限下唯一诚实的做法。
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct ExpiryLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExpiryActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
                // ★★★【第十轮·用户图5】点锁定屏幕卡片 / 通知上的实时活动区域
                //   → 带 URL 拉起 App → `RootView.onOpenURL` → 切到「效期管理」
                //     并弹出这条记录的详情。
                //
                //  ⚠️ 以前这里**什么都没有**，所以系统只能按默认行为把 App 拉起来
                //     （停在用户上次退出的页面 —— 他截图里正是「扫码」页）。
                //  ⚠️ 这个 URL 的 scheme（`expirymanager`）必须在主 App 的
                //     `Info.plist` 里注册 `CFBundleURLTypes`，否则系统不会把
                //     URL 路由给本 App（见 `Support/ExpiryManager-Info.plist`）。
                .widgetURL(ExpiryDeepLink.record(context.attributes.recordID))
        } dynamicIsland: { context in
            DynamicIsland {
                // ── 左上：只有「⏳ + 类别」，**与右上倒计时左右对称** ──
                //  ★★【第八轮】用户图2 原话：
                //    「篮筐肉类最左边还是有点超出，可以和右侧黄框的时间做对称设计，
                //      字体大小相同，位置对称」
                //
                //  ✅ 做法：
                //    ① 类别从 `.caption2` **放大到 `.subheadline` + 半粗**，
                //       让它与右侧大号倒计时**字号量级相当**、形成左右平衡；
                //    ② `.padding(.leading, 10)` —— 上一轮只加了 6，仍然贴边，
                //       这一轮加到 10 彻底离开胶囊圆角；
                //    ③ **标题从本区域移走**（挪到 `.bottom`，见下）——
                //       这样本区域只剩一行，与右侧一行倒计时**高度对称**。
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        // 判据统一 `countdownInterval == nil`（见「倒计时」一节）。
                        Image(systemName: context.state.countdownInterval == nil
                              ? "exclamationmark.triangle.fill"
                              : "hourglass")
                            .font(.subheadline)
                        Text(context.attributes.kindLabel)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 10)
                }

                // ── 右上：**只有大号倒计时**（图7「红色数字应为倒计时」）──
                //  ★ 图2「右侧倒计时和苹果这个黄色一致」→ 苹果运动黄。
                //  ★★【第八轮】到期时刻（`13:37`）**从这里移到 `.bottom` 的日期后面**
                //     —— 用户图2 原话「绿框的时间应该平移到红框的日期后面」。
                //     所以本区域现在只剩一个数字，与左侧一行类别**对称**。
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedCountdownText(state: context.state)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(context.state.countdownInterval == nil
                                         ? Color.red
                                         : ExpiryLiveActivityColors.exerciseYellow)
                        .padding(.trailing, 10)
                }

                // ── 底部：**「标题 + 里程碑」两排文字整合成一个信息块** ──
                //  ★★【第八轮】用户图2 原话：
                //    「红框可以整合成同一区域的信息，两排文字」
                //    「绿框的时间应该平移到红框的日期后面」
                //    「上面的标签名称，例如『解冻-猪肉-梅花肉』，字体可以适当放大」
                //
                //  ✅ 做法：
                //    ① **标题从 `.leading` 搬到本区域第一行** —— 这是「整合成
                //       同一区域两排文字」的唯一办法（`DynamicIslandExpandedRegion`
                //       是固定分区，跨区就没法相邻）；
                //    ② 标题字号 `.subheadline` → **`.headline`**（用户要求「适当放大」），
                //       仍是 `lineLimit(1)` + 缩字，保证完整一行；
                //    ③ 第二行把「里程碑文案 + `yyyy/MM/dd` + `HH:mm`」**串成一行**
                //       —— 这就是用户要的「`13:37` 平移到日期的后面」，
                //       最终呈现形如「原始保质期 2026/10/10 13:37」。
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        // 第一排：标题（放大）
                        Text(context.attributes.title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(.white)

                        // 第二排：里程碑 + 日期 + 时刻（三合一，紧贴日期之后）
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(context.attributes.milestoneLabel)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                            Text(ExpiryDateFormat.date(context.state.dueAt))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            // ★ 图2「绿框的时间应该平移到红框的日期后面」→ 就是这里。
                            Text(ExpiryDateFormat.time(context.state.dueAt))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }

                        ActionButtons(attributes: context.attributes,
                                      state: context.state)
                    }
                    .padding(.bottom, 2)
                }
            } compactLeading: {
                // ★★★【第八轮·本轮核心修复】图1「红框中还是保留大量位置，
                //    分析是什么原因导致的？不应该是这样的排版」。
                //
                //  ⚠️ **元凶就是上一轮那两句 `.frame(maxWidth: .infinity, ...)`。**
                //     `.maxWidth: .infinity` 的语义是「我要尽可能宽」——
                //     在紧凑槽位里，系统会老老实实把内容**撑到允许的最大宽度**，
                //     于是整条灵动岛被拉到上限，摄像头两侧各留一大块纯黑
                //     （= 用户圈的蓝框 + 红框）。
                //
                //  ★ 为什么上一轮会加它：第五轮用户抱怨「沙漏离摄像头有缝隙」，
                //    当时误判为「内容在槽位里居中」→ 用撑满来消缝。
                //    **但这条判断是错的**：撑满换来的是「整岛变宽 + 大片黑边」，
                //    缝隙没消、观感更差。两害相权，宁可留一点系统内边距。
                //
                //  ✅ 正解：**什么都不加**，让内容按**自身固有尺寸**参与布局。
                //     系统会把槽位收到「内容宽度 + 默认内边距」——
                //     这是平台允许的**最窄**形态，也就是苹果运动 App（图2 参照）
                //     那个样子。
                //  ⚠️ 不要用 `.fixedSize()` 代替：它会把 `Text(timerInterval:)`
                //     的宽度**锁死**，倒计时从 `9:59` 走到 `0:05` 时不会跟着收窄。
                //  ⚠️ 也不要加 `.contentMargins(...,0)`（第三轮踩过：会把内容
                //     甩到两端、数字挤出屏幕）。
                // ★★★【第九轮·本轮】用户追问：
                //    「现在还是整个灵动岛紧凑版-撑宽样式，而且我发现这个宽度和
                //      放大版灵动岛是一样宽的。问题会不会是这个原因呢？
                //      紧凑版和放大版这俩个灵动岛应该没有关系，继续检查问题是在哪里」
                //
                //  ★ 查证结论（Apple 官方 HIG + ActivityKit 文档）：
                //    **紧凑态槽位的尺寸是系统写死的常量 —— App 改不了。**
                //      · Compact leading  槽位：62.33 × 36.67 pt（Pro Max）
                //                              52.33 × 36.67 pt（Pro）
                //      · Compact trailing 槽位：同上（**左右对称**，这是设计规范）
                //      · 灵动岛总宽 = 摄像头模组 + 左槽 + 右槽，**全由系统决定**
                //      · Expanded 宽度：371 pt（Pro）/ 408 pt（Pro Max）
                //    ➜ **紧凑态和展开态的宽度都是系统常量，两者互不影响。**
                //      同一时刻灵动岛只呈现其中一种形态；两者实际差 100pt 以上，
                //      看起来"一样宽"是因为**两端留白把紧凑态视觉上拉长了**。
                //
                //  ★ 两端那两块黑 = 「槽位固定宽度 − 内容实际宽度」：
                //      · 左槽只有一个小沙漏（约 12pt）→ 空出约 40pt；
                //      · 右槽 `1:13`（约 30pt）        → 空出约 22pt。
                //    **这是系统留给内容的固定画布，不是我们画上去的黑块。**
                //    唯一能改善观感的做法 = **把内容放大到填满槽位**（用户也要求了）。
                //
                //  ★★★【本轮结论·不要再试】以下三条**都改不了灵动岛宽度**
                //     （宽度是系统常量），试了只会更糟：
                //      · `.frame(maxWidth: .infinity)` → 内容撑满槽位，整岛不变宽，
                //        只是内容贴边（第八轮已删）；
                //      · `.contentMargins(...,0)`（第三轮）→ 内容被甩到槽位两端、
                //        数字挤出屏幕；
                //      · `.fixedSize()` → 锁死 `Text(timerInterval:)` 宽度，倒计时不缩。
                //    ➜ **本轮唯一动作 = 放大内容**（见下两处 `.font(.title3)`）。
                Image(systemName: context.state.countdownInterval == nil
                      ? "exclamationmark.triangle.fill"
                      : "hourglass")
                    // ★★【第九轮】`.imageScale(.small)` → **`.title3` 字号**（20pt）：
                    //   紧凑槽位高 36.67pt，20pt 的图标能明显填满画布。
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(context.state.countdownInterval == nil
                                     ? Color.red
                                     : Color.white)
            } compactTrailing: {
                // ★ 不加任何 frame / contentMargins（理由见上）。
                //  ★★【第九轮】文字同步放大到 `.title3` → 见 `CompactCountdownText`。
                CompactCountdownText(state: context.state)
            } minimal: {
                // minimal 只留给一个图标，别放文字。
                // ★ 同步放大（多活动并存时的形态，保持一致）。
                Image(systemName: "hourglass")
                    .font(.body)
                    .foregroundStyle(.white)
            }
            .keylineTint(Theme.brand)
            // ⚠️⚠️ **千万不要再加 `.contentMargins(.horizontal, 0, for: .compact*)`**
            //    上一版就是这么写的，结果把紧凑态内容推到两端、
            //    数字被挤出屏幕（用户反馈「已完全看不到数字」）。
            //    系统的默认边距才是对的 —— 保持不放任何 contentMargins。
        }
    }
}

// MARK: - 锁屏 / 横幅

private struct LockScreenView: View {
    let context: ActivityViewContext<ExpiryActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── 第一行：图标 + 标题 + 类别 ──
            // ★★【第七轮】图8「文字保持完整一行」→ `lineLimit(1)` + 缩字。
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // ★ 判据统一 `countdownInterval == nil`（见「倒计时」一节注释）。
                Image(systemName: context.state.countdownInterval == nil
                      ? "exclamationmark.triangle.fill"
                      : "hourglass")
                    .font(.subheadline)
                    .foregroundStyle(context.state.countdownInterval == nil
                                     ? Color.red
                                     : Theme.brandLight)
                Text(context.attributes.title)
                    .font(.headline)
                    // ★ 不再允许折成两行 —— 宁可缩字。
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(context.attributes.kindLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // ── 第二行：里程碑文案 + 完整日期（图8「最佳使用时间 2026/01/01」）──
            // ★★【第七轮】图8 明确要求把这里改成「时间模组 + 日期」的形式。
            //   左侧是里程碑文案（`milestoneLabel`，如「最佳使用时间」），
            //   右侧是同行的 `yyyy/MM/dd`；倒计时挪到最右侧（保持原有能力）。
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(context.attributes.milestoneLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(ExpiryDateFormat.date(context.state.dueAt))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // 倒计时仍然保留（这是横幅最有用的信息），
                // 未到点用苹果运动黄、到点用红色。
                LockScreenCountdownText(state: context.state)
            }

            ActionButtons(attributes: context.attributes, state: context.state)
        }
        .padding(14)
    }
}

/// 横幅（锁屏 / 通知中心）用的倒计时。
///
/// ★★ 2026-10-10 新增（第七轮）：与紧凑态、展开态**分开**，因为三处的
///    字号 / 颜色策略不同：
///      · 紧凑态 —— 黄（未到点）/ 红（到点），`.caption` 加粗；
///      · 展开态 —— 黄 / 红，`size 26` 粗体圆角；
///      · **横幅** —— 黄 / 红，`.title3` 粗体圆角（本组件）。
///    三者共享同一个色板（`ExpiryLiveActivityColors`），
///    只在此处负责横版的排版。
private struct LockScreenCountdownText: View {
    let state: ExpiryActivityAttributes.ContentState

    var body: some View {
        // ★ 双轨绘制（见 `ContentState.countdownInterval` 的长注释）：
        //   能拿到区间 → 系统实时倒计时；拿不到 → 静态文字。
        //   ⚠️ 判据只用 `countdownInterval`，**不要再叠一层 `phase` 判断** ——
        //      两者等价但重复，且 `phase` 是 Bool 语义、`interval` 是数据语义，
        //      统一用后者才能一眼看出「就是这里决定渲染哪个分支」。
        Group {
            if let interval = state.countdownInterval {
                Text(timerInterval: interval, countsDown: true, showsHours: true)
                    .monospacedDigit()
            } else {
                Text("已到时间")
            }
        }
        .font(.system(.title3, design: .rounded))
        .fontWeight(.bold)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(state.countdownInterval == nil
                         ? Color.red
                         : ExpiryLiveActivityColors.exerciseYellow)
    }
}

// MARK: - 按钮（★ 按阶段显示）

/// ★★ 2026-10-09 修正（用户反馈）：
///    「前 10 分钟提醒，按钮只保留已完成使用，删除到时间后的稍后提醒」
///
///    → 所以**提前阶段只显示「已完成使用」**；
///      「稍后提醒」只在**已经到时间**之后才出现。
///
///    ★★ 2026-10-10（第七轮）：判据从 `phase` 改为
///       **`countdownInterval == nil`**，与倒计时/图标/颜色**同源**。
///       这样「数字变『到点』」和「稍后提醒按钮出现」发生在同一次重绘里，
///       不会出现「已经显示到点了，但少一个按钮」的错帧。见下方 `body` 注释。
private struct ActionButtons: View {
    let attributes: ExpiryActivityAttributes
    let state: ExpiryActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ExpiryMarkDoneIntent(recordID: attributes.recordID)) {
                Label("已完成使用", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)

            // ★ 只有「到时间」之后才给「稍后提醒」。
            //   ⚠️ 判据与倒计时**同源**（`countdownInterval == nil`），
            //      而不是 `phase`：这样「倒计时变『到点』」与「按钮冒出来」
            //      在**同一次重绘**里发生，不会出现「显示到点了但少一个按钮」。
            if state.countdownInterval == nil {
                Button(intent: ExpirySnoozeIntent(recordID: attributes.recordID,
                                                  dueAt: state.dueAt)) {
                    Label("稍后提醒", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .tint(.orange)
            }
        }
    }
}

// MARK: - 倒计时

/// ★★ 2026-10-10 新增（第七轮，用户参照苹果运动 App）。
///
/// 用户原话（图2）：
///   「就像苹果运动的这个样式一样，同时左侧图标修改成和我的字体一样的颜色，
///     右侧倒计时和苹果这个黄色一致」
///
/// 苹果运动 App 的灵动岛倒计时用的是**运动黄**（接近系统 `#FFD60A`）。
/// 这里单独放一个常量，方便以后想调色只改一处。
///
/// ⚠️ **不要用 `.yellow`** —— 那是纯黄（`#FFFF00`），在黑色胶囊上发灰、
///    不够「苹果运动」；下面这个是苹果运动黄，饱和度更高、更像原版。
enum ExpiryLiveActivityColors {
    /// 苹果运动 App 的倒计时黄。
    static let exerciseYellow = Color(red: 0xFF / 255.0,
                                      green: 0xD6 / 255.0,
                                      blue: 0x0A / 255.0)
}

/// 展开态右上角的**大号倒计时**。
///
/// ★★ 2026-10-10 新增（第七轮用户反馈图7）：
///    用户圈着展开态右上那个大数字说「红色数字应为倒计时」——
///    上一版那里放的是 `ExpiryDateFormat.time(dueAt)`（到期时刻 `06:09`），
///    所以用户觉得「红数字不是倒计时」。现在改成一个**真正的倒计时**。
///
/// ★ 与 `CountdownText` 的区别：
///    · `CountdownText` —— 已无引用（保留作参照），带「已到时间」兜底；
///    · **本组件** —— 展开态专用，到点显示「已到时间」，未到点走 `timerInterval`。
private struct ExpandedCountdownText: View {
    let state: ExpiryActivityAttributes.ContentState

    var body: some View {
        // ★ 双轨绘制 —— 判据只用 `countdownInterval`（见该属性的长注释）。
        if let interval = state.countdownInterval {
            // ⚠️ `Text(timerInterval:)` 要求**下界 < 上界**，`countdownInterval`
            //    内部已 guard，天然安全。
            // ★ 展开态空间充足 → 一律带小时（`showsHours: true`），
            //   长时长也不会缩得很小。
            Text(timerInterval: interval, countsDown: true, showsHours: true)
                .monospacedDigit()
        } else {
            // 到点：区间已走完 → 静态文字（这一步就是「不再卡 `0:00`」的关键）。
            Text("已到时间")
        }
    }
}

/// 展开态 / 锁屏用的倒计时（**已无引用**）。
///
/// ★ `Text(timerInterval:)` 的区间必须「下界 < 上界」，否则会崩。
///   到点之后区间已经走完，系统会停在 `0:00`；这里额外兜一层，
///   显示「已到时间」比 `0:00` 更清楚。
///
/// ⚠️ 2026-10-10：展开态底部改成「里程碑 + 日期」后，本组件不再被调用。
///    **保留**（不要因为「没人用」就删）—— 它是 `ExpandedCountdownText`
///    的对照写法，将来若要恢复底部倒计时可直接复用。
private struct CountdownText: View {
    let state: ExpiryActivityAttributes.ContentState

    var body: some View {
        if let interval = state.countdownInterval {
            Text(timerInterval: interval, countsDown: true, showsHours: true)
                .monospacedDigit()
        } else {
            Text("已到时间")
        }
    }
}

/// 紧凑态（灵动岛最小宽度）专用的倒计时。
///
/// ★★ 【第四轮关键修复】宽度收敛 —— 这是「右侧与摄像头距离超长」的真正解法：
///    上一版用 `Text(timerInterval:countsDown:showsHours: true)`，
///    它会按 `H:MM:SS`（`12:34:56`，8 个字符）**预留宽度**，
///    把 `compactTrailing` 撑得很宽 → 系统把这一块**推离摄像头**，
///    于是用户看到「中间一大段空隙」。
///
///    ✅ 现在改成：
///      · 剩余时间 **< 1 小时**（绝大多数场景）→ `showsHours: false`，
///        只渲染 `M:SS`（`12:34`，5 个字符），宽度立刻收窄一大截；
///      · 剩余时间 **≥ 1 小时** → 才回退成带小时的 `H:MM:SS`。
///    判据用 `state.dueAt.timeIntervalSinceNow`，**每秒由系统重绘时现算**，
///    所以跨越 1 小时的那个瞬间会自动从 `59:59` 切到 `1:00:00`，无需 App 干预。
///
/// ★ 用户要求「小图标时右侧数字加粗」→ `.bold`。
/// ★ 用户要求「除了文字无任何空格」→ 这里**不加任何 padding / frame**，
///   只靠 `minimumScaleFactor` 往下缩，绝不主动占宽。
///
/// ★★ 到点之后显示**红色「到点」** —— 因为平台不允许 App 主动撑开灵动岛
///    （见文件头），我们能做的就是让紧凑态在到点那一刻本身最醒目。
///
/// ★★ 2026-10-10（第七轮）色板：
///      · 未到点 → **苹果运动黄**（图2 参照，「右侧倒计时和苹果这个黄色一致」）；
///      · 已到点 → **红色**（危险色优先级更高，且用户之前已认可红「到点」）。
///    ⚠️ 到点文案固定为「到点」—— 图1/3/4 里 `0:00` 一直显示是 bug 观感，
///       修法见下面 `body` 的「双轨绘制」注释（判据 = `countdownInterval`）。
private struct CompactCountdownText: View {
    let state: ExpiryActivityAttributes.ContentState

    var body: some View {
        // ★★ 双轨绘制（见 `ContentState.countdownInterval` 的长注释）：
        //    判据**只用** `countdownInterval` —— 它非 nil 就说明系统还在
        //    实时刷新倒计时；为 nil 就说明已经到点，必须换成**静态文字**。
        //
        //    ⚠️ 这是修「到点后紧凑态卡在 `0:00`」的**唯一正确写法**：
        //       上一版先判 `phase == .due` 看似等价，但那是**另一条**求值路径；
        //       改成与 `timerInterval` 同源的 `interval == nil` 判断后，
        //       归零那次重绘的两个分支就是「非此即彼」，绝不会同时成立、
        //       也就不会出现「区间没了但仍渲染 timerInterval → 卡 0:00」。
        Group {
            if let interval = state.countdownInterval {
                // ★ 以「是否还有 1 小时以上」决定格式：
                //   < 1h → `M:SS`（`showsHours: false`），窄；
                //   ≥ 1h → `H:MM:SS`（`showsHours: true`），宽但必要。
                let needsHours = state.dueAt.timeIntervalSinceNow >= 3600
                Text(timerInterval: interval,
                     countsDown: true,
                     showsHours: needsHours)
                    .monospacedDigit()
            } else {
                // 已到点：不再走 timerInterval（否则会卡在 `0:00`），给醒目文字。
                Text("到点")
            }
        }
        // ★★【第九轮】`.caption`（12pt）→ **`.title3`（20pt）** ——
        //   用户要求「左右图标文字适当放大一些」。
        //   这也是唯一能减少「槽位空白」的手段：槽位是系统固定 52~62pt 画布，
        //   内容越小、两端留白越多（见 `compactLeading` 的长注释）。
        //   ⚠️ `H:MM:SS`（8 字符）在 20pt 下约 75pt，会超过槽位宽度 →
        //      靠下面的 `minimumScaleFactor(0.7)` 收到约 52pt，刚好放得下。
        .font(.title3)
        .fontWeight(.bold)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        // ★★ 第七轮：未到点用**苹果运动黄**（图2），到点用红色。
        .foregroundStyle(state.countdownInterval == nil
                         ? Color.red
                         : ExpiryLiveActivityColors.exerciseYellow)
    }
}
