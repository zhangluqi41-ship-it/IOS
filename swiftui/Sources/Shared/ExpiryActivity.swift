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

import ActivityKit
import AppIntents
import Foundation

// MARK: - 活动属性

struct ExpiryActivityAttributes: ActivityAttributes {

    /// 这条活动处于哪个阶段。
    ///
    /// ★ 只影响文案（「还有」/「已到时间」）。**功能行为不依赖它** ——
    ///   「稍后提醒」到底该不该重复提醒，是按钮被执行的那一刻在主 App 进程里
    ///   用 `Date() >= dueAt` 现判的（见 `ExpiryActivityBridge.snooze`）。
    ///   这样即使活动是很久以前挂上的、`phase` 已经过期，行为仍然正确。
    enum Phase: String, Codable, Hashable, Sendable {
        /// 尚未到期（含「提前 10 分钟」那段窗口）。
        case soon
        /// 已经到时间（或已过）。
        case due
    }

    struct ContentState: Codable, Hashable, Sendable {
        /// 倒计时区间的下界 —— 也就是活动启动那一刻。
        ///
        /// ★ 必须存下来：`Text(timerInterval:)` 要求一个 `ClosedRange<Date>`，
        ///   而它的下界只能在渲染时用一个固定值（不能是「此刻」，
        ///   否则每次重绘区间都在变）。
        var startedAt: Date
        /// 到期时刻（= 里程碑时间）。
        var dueAt: Date
        var phase: Phase
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
    static func snooze(recordID: String, dueAt: Date) {
        // 提前 10 分钟的那条：不做任何操作。
        guard Date() >= dueAt else { return }
        ExpiryStore.shared.startSnooze(byID: recordID, dueAt: dueAt)
    }

    #else

    static func markDone(recordID: String) {}
    static func snooze(recordID: String, dueAt: Date) {}

    #endif
}
