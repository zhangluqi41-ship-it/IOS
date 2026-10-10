//
//  ExpiryActivityManager.swift
//  灵动岛（Live Activity）的起 / 更 / 收 —— **只属于主 App 目标**。
//
//  ★★ 为什么逻辑长这样（平台硬限制 + 第十轮的关键更正，别试图「优化」）：
//
//    【旧结论（第九轮之前）】Live Activity 只能由处在**前台**的 App 调
//      `Activity.request()` 启动 → 所以只能「用户最后一次打开 App 时，
//      把最近的、8 小时内会到期的那个里程碑先挂到岛上」。
//      ➜ 这套做法的死穴：App 不在前台时**没有任何办法更新活动**，
//        于是「到点自动弹出展开态」**物理上做不到**，
//        用户看到的永远是「卡在 0:00 的紧凑态 + 一条普通通知横幅」。
//
//    【第十轮更正】iOS 26 的 `Activity.request` 多了一个重载：
//        request(attributes:content:pushType:style:alertConfiguration:start:)
//      Apple 原文：「The system starts the Live Activity at the specified date,
//      **even if the app is in the background**.」
//      ➜ 于是本项目现在跑**两条活动**：
//        · **A = 倒计时**（现在的老路子，`pushType: nil`，最多 8 小时）
//          —— 负责「还有多久」的实时倒计时；
//        · **B = 到点警报**（`start: dueAt` + `alertConfiguration`）
//          —— 由**系统托管**，到点那一刻自动拉起并弹出展开态，
//             App 完全不需要在运行。见 `scheduleAlert` 的详细注释。
//      ⚠️ A 和 B 是**两条独立活动**，所以清理时必须区分：
//        · `endCountdownOnly()` —— 换目标时只清 A；
//        · `endAll()`           —— 彻底不要灵动岛时才连 B 一起清。
//        用错会把刚弹出的到点警报一起收掉。
//
//    【第十三轮更正·用户「两个灵动岛同时存在 / 关掉横幅才切换」】
//      用户原话：
//        · 「到时间后，我将横幅通知关闭后才会变成展开态灵动岛，
//           否则将一直保持 0:00 那个形态」
//        · 「锁屏界面能同时看到两个灵动岛，逻辑应该是下方代替上方，
//           是同一个模块的不同形态」
//        · 「灵动岛和横幅通知应该是并行进程，但显然现在是线性进程」
//
//      ⚠️ 根因不是排版，是**两条活动的优先级没设**。Apple 文档
//        (`Displaying live data with Live Activities`) 原文：
//          「If you don't provide a relevance score or if Live Activities have
//            the same relevance score, the system shows **the first Live
//            Activity you started** in the Dynamic Island.」
//          「If you use different relevance scores, the system shows the Live
//            Activity with **the highest relevance score** in the Dynamic Island.」
//        A 先启动、B 后启动、两者 `relevanceScore` 都是默认 0
//        ➜ 灵动岛永远只显示 A，B 排在后面 —— 用户必须人为打断才轮到 B。
//
//      ✅ 本轮两条修正：
//        ① **分级**：A = `countdownRelevance`(50)、B = `alertRelevance`(100)。
//           到点那一刻 B 一出现，因为它分最高，灵动岛**立刻**换成它
//           —— 这就是用户要的「并行」而非「线性」。
//        ② **到点后 A 退场**：`sync` 里判定「已过点 + B 已开响」时收掉 A，
//           让灵动岛与锁屏只剩「已到时间」那一张 —— 即用户的
//           「下方代替上方 / 同一个模块的不同形态」。
//        ⚠️ 提醒（通知）逻辑**一律没动**：4 档时机、passive 静默判据
//           全部保持原样，本轮只改「灵动岛活动怎么排、怎么退场」。
//
//  ★ 倒计时不需要我们管：`Text(timerInterval:countsDown:)` 由系统每秒自己刷，
//    不需要 App 在后台推状态。
//
//  ★ 两个按钮的行为不依赖任何「阶段」字段：
//    `ExpiryMarkDoneIntent` / `ExpirySnoozeIntent` 是 `LiveActivityIntent`，
//    由**主 App 进程**执行，它们在那个时刻用 `Date()` 现判
//    （见 `ExpiryActivityBridge`）—— 所以哪怕活动是几小时前挂的，
//    功能仍然是对的。
//

import ActivityKit
import Foundation

@MainActor
final class ExpiryActivityManager {

    static let shared = ExpiryActivityManager()

    /// 提前多久就把灵动岛挂上去（见文件头）。
    static let window: TimeInterval = 8 * 60 * 60

    // MARK: 两条活动的灵动岛优先级（见文件头第十三轮说明）

    /// 倒计时活动（A）的优先级 —— **低**。
    static let countdownRelevance: Double = 50

    /// 到点警报活动（B）的优先级 —— **高**。
    ///
    /// ★★★ 只要它高于 `countdownRelevance`，到点那一刻 B 就会**立刻**
    ///   顶掉岛上的 A（Apple 规则：分高者显示在灵动岛）。
    ///   ⚠️ 两个值都必须是**明确的非零差**；都给默认 0 就会退回
    ///     「显示先启动的那条」，也就是用户截图里的错位现象。
    static let alertRelevance: Double = 100

    /// 「已经到点」之后还允许挂多久。
    ///
    /// ★★ 为什么需要这段宽限：如果只保留 `delta > 0`（还没到点），
    ///    `dueAt` 一到活动就会被下一次 `sync` 收掉 —— 用户根本没机会点
    ///    「已完成使用 / 稍后提醒」。给 30 分钟，让他有充裕时间处理；
    ///    这段时间岛上显示「已到时间 + 两个按钮」。
    static let graceWindow: TimeInterval = 30 * 60

    /// 到点警报的**提前量**（第十五轮，用户拍板 3 秒）。
    ///
    /// ★ 为什么需要：系统对预定式活动（`start:`）的触发精度是**秒级** ——
    ///   为省电会合并定时器，实测「倒计时归零 → 警报弹出」有 1~2 秒延迟。
    ///   提前 3 秒预定，让肉眼看到弹出的时刻落回真实到点附近。
    ///   代价：偶尔警报比真实到点早 ~3 秒响 —— 效期场景无感（用户已确认）。
    ///
    /// ⚠️ 提前量施加在 `scheduleAlertForNextMilestone` 的 target 上 ——
    ///    也就是说 `scheduledAlertDueKey` 存的是**提前后**的时刻，
    ///    `scheduleAlert` 里「已开响就别动它」的短路因此与真实启动时刻对齐；
    ///    别把提前量挪进 `scheduleAlert` 内部（那会让短路判断错位 3 秒，
    ///    在到点前 3 秒的窗口里把刚启动的警报撤掉重排 → 响两次）。
    static let alertFireLead: TimeInterval = 3

    private var activity: Activity<ExpiryActivityAttributes>?
    /// 当前这条活动对应的「记录 + 里程碑」。
    private var currentKey: String?

    // MARK: 预定式「到点警报」活动的持久化钥匙

    /// ★★★【第十轮】预定式（`start:`）活动是**系统托管**的 —— App 被杀也照样生效。
    ///   但也正因为它是系统托管的，`activity` 这个内存变量在冷启动后是 nil，
    ///   只有把 id 落到 UserDefaults，下次 `sync` 才找得到它，
    ///   才能做到「先撤旧的、再预定新的」而不是在岛上挂两条。
    private static let scheduledAlertIDKey = "expiry.scheduledAlertID"
    /// 预定警报对应的记录 id（点「已完成使用」时用来判断要不要一起收掉）。
    private static let scheduledAlertRecordKey = "expiry.scheduledAlertRecord"
    /// 预定警报的目标时刻 —— 用来判断它**有没有已经开响**（见 `scheduleAlert`）。
    private static let scheduledAlertDueKey = "expiry.scheduledAlertDue"

    // MARK: 「最后一次倒计时活动」的属性缓存（第十三轮新增）

    /// ★★★ 为什么要把活动属性存进 UserDefaults：
    ///   第十三轮起，`sync` 会在「已过点且到点警报已开响」时**主动收掉 A**
    ///   （为了让灵动岛/锁屏只剩「已到时间」那一张）。
    ///   但用户随后仍可能点灵动岛上的「稍后提醒」—— 那一刻 A 已经不在了，
    ///   而 `restart` 需要一份属性（标题/类别/里程碑名）才能重起 5 分钟倒计时。
    ///   ➜ 于是在每次建/更 A 时顺手把属性落盘，`restart` 时兜底取用。
    ///   ⚠️ 四个字段必须**成套**写入、成套读出；缺一个就当作没有缓存。
    private static let lastAttrsRecordKey = "expiry.lastAttrs.record"
    private static let lastAttrsTitleKey = "expiry.lastAttrs.title"
    private static let lastAttrsKindKey = "expiry.lastAttrs.kind"
    private static let lastAttrsMilestoneKey = "expiry.lastAttrs.milestone"

    /// 「稍后提醒」设下的新目标时刻（recordID → 时刻）。
    ///
    /// ★ 只活在内存里：它不是「数据」，只是给 `sync` 一个提示 ——
    ///   用户点过稍后提醒的话，回到前台时把倒计时区间接回那个 5 分钟目标。
    ///   App 被杀掉就丢了，此时退回「已到时间」展示，功能不丢。
    private var snoozeTargets: [String: Date] = [:]

    private init() {}

    // MARK: - 同步

    /// 由前台调用（App 激活 / 记录变化）：把灵动岛对齐到「最近的那个里程碑」。
    ///
    /// - Parameters:
    ///   - records: 全部记录。
    ///   - enabled: 到期提醒是否开着；关掉时直接把灵动岛收掉。
    func sync(records: [LabelRecord], enabled: Bool) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard enabled else {
            await endAll()
            return
        }

        let now = Date()
        // ★★【第十二轮】挑选逻辑抽成 `nearestMilestone` 纯函数 —— 这样
        //   `ExpiryStore` 判断「这条通知要不要静默」时用的是**同一份规则**，
        //   不会出现「岛上挂的是 A、判静默用的是 B」这种错位。
        let best = Self.nearestMilestone(records: records, now: now)

        // ★★★【第十轮】**不要**在「8 小时内没有里程碑」时直接 `endAll()` 返回 ——
        //   那会把预定的「到点警报」一起收掉。8 小时窗口只管**倒计时那条**；
        //   预定的警报活动不受它限制（它是 `pending` 状态，到点才开始计时）。
        guard let best else {
            await endCountdownOnly()
            await scheduleAlertForNextMilestone(records: records)
            return
        }

        let attrs = ExpiryActivityAttributes(
            recordID: best.record.id.uuidString,
            title: best.record.title,
            kindLabel: best.record.kind.label,
            milestoneLabel: best.milestone.label)

        // ★★★【第十三轮·用户「两个灵动岛并存」的修复】
        //   「已经过点」+ 用户**没点过**稍后提醒 + 到点警报 B 已经在岛上
        //   → 收掉倒计时那条 A。
        //
        //   此刻 B 正在显示「已到时间 + 两个按钮」，A 留在场上只会让锁屏
        //   多出一张「卡在 0:00」的重复卡片 —— 正是用户图3 绿框里的现象。
        //   收掉之后就是用户要的「下方代替上方 / 同一个模块的不同形态」。
        //
        //   ⚠️ 三个条件缺一不可：
        //     · `best.milestone.date <= now` —— 只有「已过点」才收 A；
        //       到点前 A 是唯一的倒计时来源，绝不能收。
        //     · `snoozedUntil(...) == nil` —— 用户点过稍后提醒时，
        //       A 本身就是那个新的 5 分钟倒计时，必须留着。
        //     · `scheduledAlertIsLive()` —— B 确实在岛上才收；
        //       否则收了 A 等于岛上什么都不剩。
        if best.milestone.date <= now,
           snoozedUntil(recordID: best.record.id.uuidString) == nil,
           scheduledAlertIsLive() {
            await endCountdownOnly()
            // ⚠️ **不要**在这里调 `scheduleAlertForNextMilestone` ——
            //   它在「已经没有下一个里程碑」时会 `cancelScheduledAlert()`，
            //   把**正在响的这条 B** 一起收掉（用户就再也看不到「已到时间」了）。
            //   此刻正确的动作只有一个：让 A 退场、原样保留 B。
            //   「下一条」的预定交给下一次 `sync`（记录变化 / 下次冷启动）。
            return
        }

        // 缓存活动属性 —— 供 `restart`（稍后提醒）在 A 已被收掉时重建。
        Self.saveAttributes(attrs)

        // ★★ 「已经到点」的两条岔路：
        //    ① 用户点过「稍后提醒」（`snoozedUntil` 是未来时刻）
        //       → 倒计时用那个未来时刻，`phase` 现算仍为 `.soon`，
        //         岛上就是一段新的 5 分钟倒计时。
        //    ② 没点过 → 倒计时区间已经走完，`phase` 现算为 `.due`，
        //         岛上显示「已到时间 + 两个按钮」，等他处理。
        let freshTarget = snoozedUntil(recordID: best.record.id.uuidString)
        let dueAt = freshTarget ?? best.milestone.date
        let state = ExpiryActivityAttributes.ContentState(
            startedAt: now,
            dueAt: dueAt)

        let key = "\(best.record.id.uuidString)#\(best.milestone.label)"
        // ★★★ 2026-10-10（第十四轮·无缝衔接根因修复）：`staleDate` **改回 `dueAt`**。
        //
        //   第七轮曾把它从 `dueAt` 延后到 `dueAt + graceWindow`（怕到点变灰
        //   压暗提示）—— 但当时没意识到：`staleDate` 不只是「变灰标记」，
        //   它还是**系统重绘这条活动的触发器**（App 被杀也会触发；
        //   见 Nalu Timers 文档："staleDate makes the system re-render the
        //   widget when the instant passes — no app code runs"）。
        //
        //   重绘时 `countdownInterval`（计算属性）因 `Date() >= dueAt` 返回 nil，
        //   渲染层 6 处双轨分支才会从 `Text(timerInterval:)` 翻成静态
        //   「已到时间 + 两个按钮」。第七轮把触发器推迟了 30 分钟 =
        //   分支加了却永远不执行 → 锁屏上 A 一直卡在 `0:00`（第七~十三轮的顽疾）。
        //
        //   代价（已确认可接受）：到点后 A 被系统标 stale **变灰**，
        //   但此刻灵动岛已由高分的 B 接管（`alertRelevance` > `countdownRelevance`），
        //   锁屏上变灰的 A 会在下一次前台 `sync` 被「A 退场」分支收掉。
        //   ⚠️ `staleDate` 最小值 ≈ 活动开始后 2 分钟（Apple 论坛，未写进文档）：
        //      倒计时短于此的系统会自行 clamp，最多晚一会儿翻页，无大碍。
        // ★★★【第十三轮】带上**低**优先级 —— 见 `countdownRelevance` 的注释：
        //   这样到点那一刻，后启动但分更高的到点警报（B）会立刻顶掉它。
        let content = ActivityContent(state: state,
                                      staleDate: dueAt,
                                      relevanceScore: Self.countdownRelevance)

        // ── 活动 A：倒计时。同一个目标就只刷新状态；换目标才重建 ──
        //（比如刚打开 App、用户点过「稍后提醒」要把区间换新）。
        if currentKey == key, let activity {
            await activity.update(content)
        } else {
            // 换目标了：先把**倒计时**那条收干净。
            // ⚠️ 这里**不能**用 `endAll()` —— 它会把预定的到点警报一起收掉。
            await endCountdownOnly()
            do {
                activity = try Activity.request(attributes: attrs,
                                                content: content,
                                                pushType: nil)
                currentKey = key
            } catch {
                NSLog("ExpiryActivityManager: 灵动岛启动失败 \(error.localizedDescription)")
                activity = nil
                currentKey = nil
            }
        }

        // ── 活动 B：预定「到点那一刻由系统自动拉起并弹出展开态」──
        // ★★★【第十轮·用户图1/图2 的真正解法】详见 `scheduleAlert` 的长注释。
        await scheduleAlertForNextMilestone(records: records)
    }

    // MARK: - 纯查询（给 `ExpiryStore` 判断「通知要不要静默」用）
    //
    // ★★★【第十二轮·用户第 3 条】用户原话：
    //   「如图的通知，仅应存在锁屏和通知中心中，不应存在横幅，因为横幅应该是
    //     灵动岛胶囊。需要更正为：**在手机任意 app 界面或主界面状态下，如果有
    //     灵动岛胶囊紧凑态存在，就关闭横幅的消息通知**」
    //
    //   ➜ 要落地这条，`ExpiryStore` 必须能回答一个问题：
    //     **「这颗胶囊现在挂的是哪条记录、哪个里程碑？」**
    //   ➜ 而那个挑选规则原本写死在 `sync` 里。这里把它抽成 `nonisolated static`
    //     纯函数，`sync` 与 `ExpiryStore.rescheduleReminders` **共用同一份**，
    //     从根上杜绝两边判断不一致。
    //   ➜ 标 `nonisolated` 是因为 `ExpiryStore` 不是 `@MainActor`（它自己用
    //     `onMain {}` 往主线程派活），从它那边同步调用不能要求主线程。

    /// 「此刻该挂在灵动岛上的那个里程碑」—— 纯计算，不碰任何活动状态。
    ///
    /// - Returns: 最近的那个里程碑；8 小时窗口内没有就返回 `nil`（= 岛上没东西）。
    nonisolated static func nearestMilestone(records: [LabelRecord], now: Date)
        -> (record: LabelRecord, milestone: ExpiryStore.ExpiryMilestone)? {
        var best: (record: LabelRecord, milestone: ExpiryStore.ExpiryMilestone)?
        for record in records where record.usedAt == nil {
            for milestone in ExpiryStore.milestones(of: record) {
                let delta = milestone.date.timeIntervalSince(now)
                // ★ 窗口扩到 `window + graceWindow`（8h + 30min）：
                //   刚过点半小时内的物料仍然要留在岛上（否则「到时间」那一刻
                //   活动就自己消失了，用户根本来不及点按钮）。这段时间
                //   `countdownInterval == nil`，岛上显示「已到时间 + 两个按钮」。
                guard delta > -graceWindow, delta <= window else { continue }
                if best == nil || milestone.date < best!.milestone.date {
                    best = (record, milestone)
                }
            }
        }
        return best
    }

    /// 系统「实时活动」总开关是否允许。
    ///
    /// ★★★【第十二轮】必须暴露给 `ExpiryStore`：
    ///   用户若在「设置 → 面容 ID 与密码 / 通知」里把实时活动关掉，
    ///   灵动岛上**根本不会有胶囊** —— 这时通知**不能**被静默，
    ///   否则用户既看不到胶囊、也收不到横幅，等于完全被漏掉。
    ///   ⚠️ 少了这一条判断，静默规则就会在「实时活动被关闭」时误伤。
    nonisolated static var liveActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - 预定「到点自动弹出」（第十轮新增）

    /// 找出「下一个会到点的里程碑」，为它预定一条由系统托管的警报活动。
    ///
    /// ★ 与 `sync` 里那个 8 小时窗口**无关**：这里是「将来任意时刻」的第一个
    ///   里程碑 —— 因为预定式活动在 `start` 之前只是 `pending`，
    ///   不占「8 小时寿命」（寿命从它真正开始那一刻才起算）。
    private func scheduleAlertForNextMilestone(records: [LabelRecord]) async {
        let now = Date()
        var next: (record: LabelRecord, milestone: ExpiryStore.ExpiryMilestone)?

        for record in records where record.usedAt == nil {
            for milestone in ExpiryStore.milestones(of: record) where milestone.date > now {
                if next == nil || milestone.date < next!.milestone.date {
                    next = (record, milestone)
                }
            }
        }

        guard let next else {
            await cancelScheduledAlert()
            return
        }

        // 用户点过「稍后提醒」→ 警报目标跟着那个 5 分钟目标走。
        // ★【第十五轮】统一减 `alertFireLead`（3 秒）—— 抵消系统触发延迟，
        //   理由与注意事项见该常量的注释。
        let target = (snoozedUntil(recordID: next.record.id.uuidString) ?? next.milestone.date)
            .addingTimeInterval(-Self.alertFireLead)
        let attrs = ExpiryActivityAttributes(
            recordID: next.record.id.uuidString,
            title: next.record.title,
            kindLabel: next.record.kind.label,
            milestoneLabel: next.milestone.label)
        await scheduleAlert(attrs: attrs, dueAt: target)
    }

    /// 预定一条「到点那一刻由系统自动拉起并弹出」的活动。
    ///
    /// ★★★【第十轮·用户图1/图2 的真正解法】
    ///
    ///  用户原话：
    ///    · 图1：「到期后依然是灵动岛紧凑态加消息通知，没有完成到期后灵动岛展开态」
    ///    · 图2b：「这个才是我想要的到时间后的灵动岛展开态样式，**而且需要她自己弹出**」
    ///
    ///  ⚠️ 为什么之前那套做法**注定做不到**（不管排版怎么调）：
    ///    本项目用的是 `pushType: nil` 的**纯本地** Live Activity，唯一的更新入口
    ///    是 App 自己调 `activity.update(...)` —— 而 App 不在前台时根本调不到。
    ///    所以「到点自动弹」在旧架构里**物理上不可能**。
    ///
    ///  ✅ 正解 = **预定式 Live Activity**（iOS 26 新增的重载）：
    ///       Activity.request(attributes:content:pushType:style:
    ///                        alertConfiguration:start:)
    ///     Apple 文档原文：
    ///       · 「The system starts the Live Activity at the specified date,
    ///          **even if the app is in the background**.」
    ///       · 「On iPhone and iPad with the Dynamic Island, the system shows
    ///          **the expanded Live Activity in the Dynamic Island**.」
    ///     ➜ 系统在 `start`（= `dueAt`）那一刻自己把活动拉起来并提示，
    ///       **完全不需要 App 在运行**。这正是用户要的「她自己弹出」。
    ///
    ///  ★ 为什么内容跟倒计时那条不一样：这里 `startedAt == dueAt` →
    ///    `ContentState.countdownInterval == nil` → 岛上直接渲染
    ///    「到点 / 已到时间」+ 两个按钮（就是用户图2b 圈出来的那个展开态）。
    ///
    ///  ⚠️ `alertConfiguration` 是**必填**的（Apple 明确要求）：它保证
    ///     「系统开始这条活动时会告诉用户」—— 也就是弹出展开态那一刻的提示。
    ///
    ///  ⚠️ 预定式活动**算进系统的活动数量上限**，所以务必先撤旧的再预定新的。
    private func scheduleAlert(attrs: ExpiryActivityAttributes, dueAt: Date) async {
        let defaults = UserDefaults.standard

        // 上一条已经**开响**（目标时刻已过、但还在宽限期内）→ 别动它。
        // 那一刻岛上正是用户要看的「到点展开态」，重排会把它粗暴收掉。
        if let fired = defaults.object(forKey: Self.scheduledAlertDueKey) as? Date,
           fired <= Date(),
           fired > Date().addingTimeInterval(-Self.graceWindow) {
            return
        }

        // 先撤掉上一次预定的（避免岛上挂两条 / 避免超出活动数量上限）。
        await cancelScheduledAlert()

        // 已经过点（或就在此刻）→ 交给倒计时那条现算的「到点」即可，
        // 不值得再预定一个马上要开始的活动。
        guard dueAt > Date().addingTimeInterval(1) else { return }

        let state = ExpiryActivityAttributes.ContentState(startedAt: dueAt, dueAt: dueAt)
        // ★★★【第十三轮】带上**高**优先级 —— 它必须高于倒计时那条，
        //   系统才会在 B 启动的瞬间把灵动岛从 A 切到 B。
        let content = ActivityContent(state: state,
                                      staleDate: dueAt.addingTimeInterval(Self.graceWindow),
                                      relevanceScore: Self.alertRelevance)
        let alert = AlertConfiguration(
            title: "\(attrs.title)",
            body: "\(attrs.milestoneLabel)已到，请在灵动岛上点「已完成使用」或「稍后提醒」。",
            sound: .default)

        do {
            let scheduled = try Activity.request(attributes: attrs,
                                                 content: content,
                                                 pushType: nil,
                                                 style: .standard,
                                                 alertConfiguration: alert,
                                                 start: dueAt)
            defaults.set(scheduled.id, forKey: Self.scheduledAlertIDKey)
            defaults.set(attrs.recordID, forKey: Self.scheduledAlertRecordKey)
            defaults.set(dueAt, forKey: Self.scheduledAlertDueKey)
            NSLog("ExpiryActivityManager: 已预定到点警报 \(attrs.title) @ \(dueAt)")
        } catch {
            NSLog("ExpiryActivityManager: 到点警报预定失败 \(error.localizedDescription)")
        }
    }

    /// 撤掉预定的到点警报（不影响倒计时那条）。
    private func cancelScheduledAlert() async {
        let defaults = UserDefaults.standard
        guard let id = defaults.string(forKey: Self.scheduledAlertIDKey) else { return }
        for item in Activity<ExpiryActivityAttributes>.activities where item.id == id {
            await item.end(nil, dismissalPolicy: .immediate)
        }
        defaults.removeObject(forKey: Self.scheduledAlertIDKey)
        defaults.removeObject(forKey: Self.scheduledAlertRecordKey)
        defaults.removeObject(forKey: Self.scheduledAlertDueKey)
    }

    /// **只**收掉倒计时那条活动，保留预定的到点警报。
    ///
    /// ★ 为什么不能直接用 `endAll()`：`endAll()` 会把 `Activity.activities` 里
    ///   每一条都收掉 —— 包括系统托管的那条警报。而「换目标时清理」这个场景
    ///   只需要清倒计时那条。
    ///
    /// ★ 兜底那一段（按 `scheduledAlertIDKey` 过滤）是为了覆盖「App 重启后
    ///   `activity` 内存变量是 nil、但岛上还挂着上次启动留下的活动」。
    private func endCountdownOnly() async {
        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let scheduledID = UserDefaults.standard.string(forKey: Self.scheduledAlertIDKey)
        for item in Activity<ExpiryActivityAttributes>.activities where item.id != scheduledID {
            await item.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        currentKey = nil
    }

    /// 把灵动岛的倒计时重置成「从现在起 5 分钟」。
    ///
    /// ★★ 用户反馈：「到时间后的稍后提醒，点击完无重新倒计时 5 分钟功能」。
    ///
    /// ★ 为什么是「重起」而不是「`update`」：
    ///   `Activity.update` 能让内容秒变，但倒计时的**区间下界**只有重起
    ///   才能干净地换成新值（同一条活动反复 update 容易出现视觉上的
    ///   「时间不连续」）。重起代价只是一次 request，用户体验更直观。
    ///
    /// ★ 重起前先把「5 分钟后的目标时刻」记进 `snoozeTargets`，
    ///   这样哪怕用户马上又杀掉 App，回到前台时 `sync` 也能把区间接回去
    ///   （见 `sync` 里的 `snoozedUntil`）。
    func restart(recordID: String, dueAt: Date) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        snoozeTargets[recordID] = dueAt

        // ★★★【第十三轮】A 可能已经被 `sync` 收掉了（到点后「A 退场」那一步）。
        //   所以这里**不能**只认内存里的 `activity`：
        //     ① 手上还有 → 用它的属性；
        //     ② 手上没有 → 用 `saveAttributes` 落盘的缓存重建（必须是同一条记录）；
        //     ③ 都没有   → 放弃重起。`snoozeTargets` 已记下目标，
        //                  App 下次回到前台时 `sync` 会把倒计时区间接回来。
        // ★【第十轮】这里**不能再 `endAll()`** —— 用户点的很可能正是刚刚
        //   自己弹出来的「到点警报」，`endAll()` 会把那条也收掉，
        //   而且它是一个刚刚才被用户看到的提示，收掉等于白弹。
        let attrs: ExpiryActivityAttributes
        if let activity {
            attrs = activity.attributes
        } else if let saved = Self.savedAttributes(), saved.recordID == recordID {
            attrs = saved
        } else {
            return
        }

        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.activity = nil
            currentKey = nil
        }

        Self.saveAttributes(attrs)

        let state = ExpiryActivityAttributes.ContentState(startedAt: Date(), dueAt: dueAt)
        // ★ 同 `sync`（第十四轮）：`staleDate = dueAt` —— 5 分钟走完那一刻
        //   系统重绘，`countdownInterval` 翻 nil，卡片从倒计时翻成「已到时间」。
        //   （5 分钟 > 2 分钟的 staleDate 最小值，不受 clamp 影响。）
        // ★ 优先级同样取「倒计时」这一档（低）—— 这样下一次到点时，
        //   到点警报还能像第一次那样顶掉它。
        let content = ActivityContent(state: state,
                                      staleDate: dueAt,
                                      relevanceScore: Self.countdownRelevance)

        do {
            self.activity = try Activity.request(attributes: attrs,
                                                 content: content,
                                                 pushType: nil)
            currentKey = "\(recordID)#\(attrs.milestoneLabel)"
        } catch {
            NSLog("ExpiryActivityManager: 稍后提醒重起失败 \(error.localizedDescription)")
        }

        // ★★★【第十轮】「稍后提醒」= 每 5 分钟再来一次。
        //   所以预定的到点警报也要挪到新的目标时刻 —— 否则它已经响过一次，
        //   就再也不会响了（用户原话：「每 5 分钟提醒一次」）。
        //   ⚠️ `scheduleAlert` 内部会因为「上一条已开响」而直接返回，
        //     所以这里先显式把旧的撤掉再排新的。
        if dueAt > Date() {
            await cancelScheduledAlert()
            await scheduleAlert(attrs: attrs, dueAt: dueAt)
        }
    }

    /// 「稍后提醒」设下的新目标时刻（如果用户点过）。
    private func snoozedUntil(recordID: String) -> Date? {
        guard let t = snoozeTargets[recordID], t > Date() else { return nil }
        return t
    }

    // MARK: - 结束

    /// 收掉某条记录对应的灵动岛（点了「已完成使用」时用）。
    func end(recordID: String) async {
        snoozeTargets.removeValue(forKey: recordID)

        // ★★★【第十轮】预定的到点警报如果也属于这条记录，必须一起撤掉 ——
        //   否则用户已经点了「已完成使用」，到点那一刻它还会再弹一次，
        //   而且会一直挂在岛上。
        //   ⚠️ 这一步对**已经开响**的那条同样有效（它就是用户此刻在点的东西），
        //     所以清除时机正好。
        if UserDefaults.standard.string(forKey: Self.scheduledAlertRecordKey) == recordID {
            await cancelScheduledAlert()
        }

        // ★★★【第十三轮】改成「按 recordID 遍历系统里的全部活动」再收。
        //   原因：A 可能已被 `sync` 收掉，而 `Activity.activities` 里还可能留着
        //   孤儿（App 重启后内存变量 `activity` 是 nil，只收它会漏掉）。
        //   ⚠️ 与 `endCountdownOnly()` 的区别：那里是「按 id 排除掉 B」，
        //      这里是「按记录的 recordID 精确命中」，两者互不干扰。
        for item in Activity<ExpiryActivityAttributes>.activities
        where item.attributes.recordID == recordID {
            await item.end(nil, dismissalPolicy: .immediate)
        }
        if currentKey?.hasPrefix(recordID) == true {
            self.activity = nil
            currentKey = nil
        }
    }

    /// 收掉本 App 的**全部**灵动岛（含预定的到点警报）。
    ///
    /// ★ 用系统的 `Activity.activities` 而不是只看自己手里那条：
    ///   App 重启后 `activity` 是 nil，但岛上可能还挂着上一次启动时留下的活动。
    ///
    /// ⚠️ 只在「彻底不要灵动岛了」（关掉到期提醒、清空记录）时才用。
    ///   只想清倒计时那条时请用 `endCountdownOnly()` —— 否则会把预定的警报
    ///   一起收掉（见该函数的注释）。
    func endAll() async {
        for item in Activity<ExpiryActivityAttributes>.activities {
            await item.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        currentKey = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.scheduledAlertIDKey)
        defaults.removeObject(forKey: Self.scheduledAlertRecordKey)
        defaults.removeObject(forKey: Self.scheduledAlertDueKey)
    }

    // MARK: - 辅助（第十三轮新增）

    /// 预定的「到点警报」（B）此刻是否**真的挂在岛上**。
    ///
    /// ★ 用途：`sync` 判断「A 能不能退场」时用。只有 B 确实在场才收 A，
    ///   否则（B 还没开响 / 被系统拒绝 / 还在 `pending`）收了 A
    ///   就等于岛上什么都不剩。
    /// ⚠️ 判据用 `activityState` 而**不是**「UserDefaults 里有没有 id」——
    ///   后者只代表「预定过」，活动可能还在 `pending`（尚未显示）。
    private func scheduledAlertIsLive() -> Bool {
        guard let id = UserDefaults.standard.string(forKey: Self.scheduledAlertIDKey) else {
            return false
        }
        return Activity<ExpiryActivityAttributes>.activities.contains { item in
            item.id == id && (item.activityState == .active || item.activityState == .stale)
        }
    }

    /// 把一条活动的属性落盘，供 `restart`（稍后提醒）在 A 已被收掉时重建。
    private static func saveAttributes(_ attrs: ExpiryActivityAttributes) {
        let defaults = UserDefaults.standard
        defaults.set(attrs.recordID, forKey: lastAttrsRecordKey)
        defaults.set(attrs.title, forKey: lastAttrsTitleKey)
        defaults.set(attrs.kindLabel, forKey: lastAttrsKindKey)
        defaults.set(attrs.milestoneLabel, forKey: lastAttrsMilestoneKey)
    }

    /// 读回上次落盘的活动属性；四个字段缺任何一个都当作「没有缓存」。
    private static func savedAttributes() -> ExpiryActivityAttributes? {
        let defaults = UserDefaults.standard
        guard let record = defaults.string(forKey: lastAttrsRecordKey),
              let title = defaults.string(forKey: lastAttrsTitleKey),
              let kind = defaults.string(forKey: lastAttrsKindKey),
              let milestone = defaults.string(forKey: lastAttrsMilestoneKey) else {
            return nil
        }
        return ExpiryActivityAttributes(recordID: record,
                                        title: title,
                                        kindLabel: kind,
                                        milestoneLabel: milestone)
    }
}
