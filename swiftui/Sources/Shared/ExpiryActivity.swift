//
//  ExpiryActivity.swift
//  灵动岛（Live Activity）的**共享**定义 —— 同一个文件同时编进
//    · 主 App 目标（`ExpiryManager`，带 `EXPIRY_APP` 宏）
//    · Widget 扩展（`ExpiryWidget`，带 `EXPIRY_WIDGET` 宏）
//
//  ★ 为什么要共享：`ActivityAttributes` 是「宿主 App 起活动、扩展渲染 UI」
//    两边都要认识的一对类型；`Button(intent:)` 里的 Intent 类型也必须两边都编，
//    否则扩展编译不过（`AppIntent` 是编译期解析的）。
//
//  ★★ 为什么带 `EXPIRY_APP` 宏：`LiveActivityIntent` 里的 `perform()` 会由
//    **主 App 进程**执行（不是扩展进程），所以「真实现」必须调主 App 的
//    `ExpiryStore`；而 `ExpiryStore` 并不在扩展目标里。用编译条件把真实现 /
//    空实现分开，就能让同一个文件在两个目标里都编译通过，
//    同时保证运行期真正干活的是主 App 那份。
//
//  ★ 为什么不用 App Group 传数据：
//    这里没有任何「扩展要读 App 数据」的需求 —— 扩展渲染用的全部内容都由
//    `ContentState` 带过去；按钮回写走 `LiveActivityIntent`（主 App 进程）。
//    不用 App Group 就少一个临场创建的 `4U3G6835M9.xxx`，也就少一份
//    「装出两个 App」的风险。
//
//  ★★ 平台硬限制（决定了下面 `ExpiryActivityManager` 的策略）：
//    Live Activity **只能由处于前台的 App 调 `Activity.request()` 启动**；
//    本地通知 / 后台唤醒都拉不起它（iOS 17.2 起后台只能靠服务端 APNs
//    push-to-start，免费开发者账号没有推送能力）。
//    所以只能「用户最后一次打开 App 时，把 8 小时内会到期的那个里程碑先挂上去」。
//
//  ★★ 但这只限制「起点」，不限制「之后」：
//    活动一旦起来了，它的**倒计时**是系统自己算的 —— `Text(timerInterval:)`
//    每秒刷新，不需要 App 在后台做任何事。
//
//  ⚠️⚠️ 2026-10-10（第十轮）重要更正：**不要**指望「`Date()` 越过 `dueAt` 时
//    系统会自动把紧凑态翻成『到点』」—— 实测不可靠（用户图1：归零后长期卡
//    `0:00`）。原因是 `Text(timerInterval:)` 只在区间未走完时刷新，
//    而「翻分支」需要一次**状态更新**，纯本地活动在 App 不在前台时又做不到。
//    ➜ 正解是**再预定一条由系统托管的「到点警报」活动**
//      （`Activity.request(..., alertConfiguration:, start: dueAt)`），
//      见 `ExpiryActivityManager.scheduleAlert`。它带的就是
//      `countdownInterval == nil` 的状态，所以一出现就渲染成「到点 + 两个按钮」。
//
//  ★ 「稍后提醒」的 5 分钟循环：
//    活动起来之后也没法从后台重置倒计时 → 用一条 `repeats: true` 的本地通知
//    每 5 分钟敲一次（见 `ExpiryStore.startSnooze`）；App 一回到前台，
//    `ExpiryActivityManager.sync` 会检测到「已经到点但还没处理」，
//    把倒计时区间重置成 `[now, now+5min]`，灵动岛上就又是满格的 5 分钟。
//

import ActivityKit
import AppIntents
import Foundation

// MARK: - 活动属性

struct ExpiryActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable, Sendable {
        /// 倒计时区间的下界 —— 也就是活动启动那一刻。
        ///
        /// ★ 必须存下来：`Text(timerInterval:)` 要求一个 `ClosedRange<Date>`，
        ///   而它的下界只能在渲染时用一个固定值（不能是「此刻」，
        ///   否则每次重绘区间都在变）。
        var startedAt: Date
        /// 到期时刻（= 里程碑时间）。
        var dueAt: Date

        // MARK: 派生属性

        /// 倒计时的渲染区间；`nil` 表示已经到时间（别再画负数倒计时）。
        ///
        /// ★ `Text(timerInterval:)` 要求「下界 < 上界」，否则会崩。
        ///   到点之后返回 `nil`，由视图显示「已到时间 / 到点」。
        ///
        /// ★★ 2026-10-10（第七轮）—— 这是修「到点后灵动岛卡在 `0:00`」的关键。
        ///
        ///    现象（用户图1/图3/图4）：倒计时明明归零了，紧凑态却一直显示
        ///    `0:00`，图标也还是白沙漏，**不翻成红色的「到点」**。
        ///
        ///    根因 + 正解（社区验证过的「双轨绘制」模式）：
        ///      `Text(timerInterval:)` 由系统托管，**只在区间未走完时**刷新。
        ///      正确写法是**在视图 body 里做一次三元分支**：
        ///        · 还没到点 → `Text(timerInterval:)`（系统实时倒计时）
        ///        · 已经到点 → `Text("到点")`（**静态文本**）
        ///      系统在归零那一刻会做**最后一次重绘**，这次重绘里
        ///      `Date() < dueAt` 已不成立 → 落到静态分支 → 显示「到点」。
        ///      ⚠️ 所以**判断必须写进 body**，不能只在「有没有区间」上做文章。
        ///      （参考：Blake Crosley《Live Activities 是状态机，不是徽章》
        ///        给出的 `if endTime > Date() { timerInterval } else { 静态 }`）
        ///
        ///    ⚠️ **不要给上界加任何「魔法偏移」**（比如 `dueAt + 1s`）：
        ///       会与 `phase` 的严格判定（`Date() >= dueAt`）错位，
        ///       在归零附近产生「到点 / 0:00」来回闪。上界就用 `dueAt`。
        ///    ⚠️ **千万不要用 `Date.distantFuture` / `.infinity` 当上界**：
        ///       Apple 论坛已确认（iOS 17/18 的 chronod bug）会让整条
        ///       Live Activity **完全不显示**。必须给**有限的具体时刻**。
        var countdownInterval: ClosedRange<Date>? {
            guard dueAt > startedAt, Date() < dueAt else { return nil }
            return startedAt...dueAt
        }
    }

    /// 记录的 `id.uuidString` —— 按钮回写时用来定位这条记录。
    var recordID: String
    /// 标签主标题，如「冷冻-牛肉-眼肉」。
    var title: String
    /// 模板类别文案，如「肉类」。
    var kindLabel: String
    /// 里程碑文案，如「原始保质期」/「最佳使用时间」/「完成时间」。
    var milestoneLabel: String
}

// MARK: - 灵动岛上的两个按钮

/// 「已完成使用」 —— 对应「效期管理」里的「已用完」。
struct ExpiryMarkDoneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "已完成使用"
    static var isDiscoverable: Bool = false

    @Parameter(title: "记录")
    var recordID: String

    init() {}

    init(recordID: String) {
        self.recordID = recordID
    }

    func perform() async throws -> some IntentResult {
        #if EXPIRY_APP
        ExpiryActivityBridge.markDone(recordID: recordID)
        #endif
        return .result()
    }
}

/// 「稍后提醒」。
///
/// ★ 用户规则（清单「三、效期管理」第 2 条）：
///     · 「提前 10 分钟」那条点稍后提醒 → **不做任何操作**
///     · 「到时间」那条点稍后提醒 → **每 5 分钟提醒一次**
///   判据是「点下去的这一刻有没有到时间」，所以这里把 `dueAt` 一并带过去，
///   由主 App 现判。
struct ExpirySnoozeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "稍后提醒"
    static var isDiscoverable: Bool = false

    @Parameter(title: "记录")
    var recordID: String
    @Parameter(title: "到期时刻")
    var dueAt: Date

    init() {}

    init(recordID: String, dueAt: Date) {
        self.recordID = recordID
        self.dueAt = dueAt
    }

    func perform() async throws -> some IntentResult {
        #if EXPIRY_APP
        ExpiryActivityBridge.snooze(recordID: recordID, dueAt: dueAt)
        #endif
        return .result()
    }
}

// MARK: - 点击跳转（deep link）

/// 灵动岛 / 锁定屏幕卡片 / 通知 被点击后跳进 App 的地址。
///
/// ★★★【第十轮·用户图5 修复】
///   用户原话：「点击灵动岛的消息后会自动跳到 app 中，但是打开的画面是
///   上次退出时的画面。逻辑应该改为：点击灵动岛 -> 进入 APP 的效期管理界面」
///
///   查证结论：整个工程里**原本一个 `widgetURL` / `onOpenURL` 都没有** ——
///   也就是说「点了之后去哪」这件事**从来就没有实现过**，系统只能按默认行为
///   把 App 拉起来（= 停在用户上次退出的那个页面，所以是「扫码」页）。
///
///   修法：这里给出 URL 约定（**放 Shared**，因为 App 与 Widget 扩展都要用），
///   由
///     · Widget 侧 `.widgetURL(...)` 挂到卡片上；
///     · App 侧 `RootView.onOpenURL` 接住并切到「效期管理」Tab；
///     · `Info.plist` 的 `CFBundleURLTypes` 注册 `expirymanager://` 这个 scheme。
///   ⚠️ 三者缺一不可 —— 少了 scheme 注册，系统不会把 URL 路由给本 App。
enum ExpiryDeepLink {

    /// URL scheme（必须与 `Support/ExpiryManager-Info.plist` 里的 `CFBundleURLSchemes` 一致）。
    static let scheme = "expirymanager"

    /// 打开「效期管理」一级页。
    static let expiry = URL(string: "expirymanager://expiry")!

    /// 打开「效期管理」并弹出某条记录的详情。
    static func record(_ id: String) -> URL {
        URL(string: "expirymanager://record/\(id)")!
    }

    /// 解析一条 deep link；返回 `nil` 表示不是我们认识的地址。
    ///
    /// - Returns: `(要不要去效期管理, 要高亮的记录 id)`
    static func parse(_ url: URL) -> (expiry: Bool, recordID: String?)? {
        guard url.scheme == scheme else { return nil }
        switch url.host {
        case "expiry":
            return (true, nil)
        case "record":
            let id = url.pathComponents.count > 1 ? url.pathComponents[1] : nil
            return (true, id)
        default:
            return (true, nil)
        }
    }
}

// MARK: - 桥

/// Intent → 主 App 真实数据的桥。
///
/// ★ 两个目标看到的实现不同（见文件头）：
///     · 主 App：真干活（改 `ExpiryStore`、收掉灵动岛）
///     · 扩展  ：空实现 —— 扩展进程**永远不会**执行 `LiveActivityIntent`
///                （系统把它放到主 App 进程跑），这里只是为了让扩展编译过。
enum ExpiryActivityBridge {
    #if EXPIRY_APP

    /// 「已完成使用」：把记录标记为已用完，并收掉灵动岛。
    static func markDone(recordID: String) {
        ExpiryStore.shared.markUsed(byID: recordID)
        Task { await ExpiryActivityManager.shared.end(recordID: recordID) }
    }

    /// 「稍后提醒」：只有**已经到时间**的那条才需要重复提醒。
    ///
    /// ★★ 2026-10-09 修正（用户反馈「点击完无重新倒计时 5 分钟功能」）：
    ///    以前只排了一条 `repeats: true` 的 5 分钟通知，**灵动岛上的倒计时
    ///    一动不动**（因为它还是指向原来那个已经走完的 `dueAt`）。
    ///    现在多一步：把灵动岛重起一遍，倒计时区间重置成 `[now, now+5min]`，
    ///    用户点完就能看到岛上重新跳 5 分钟。
    ///
    ///    ⚠️ 重起活动代替「更新活动」，是因为 `Activity.update` 只让内容秒变，
    ///       而这里要的是**倒计时区间换新的**；重起最直接、也顺带清了 staleDate。
    static func snooze(recordID: String, dueAt: Date) {
        // 提前 10 分钟的那条：不做任何操作。
        guard Date() >= dueAt else { return }
        ExpiryStore.shared.startSnooze(byID: recordID, dueAt: dueAt)
        let fresh = Date().addingTimeInterval(ExpiryStore.snoozeInterval)
        Task { await ExpiryActivityManager.shared.restart(recordID: recordID, dueAt: fresh) }
    }

    #else

    static func markDone(recordID: String) {}
    static func snooze(recordID: String, dueAt: Date) {}

    #endif
}
