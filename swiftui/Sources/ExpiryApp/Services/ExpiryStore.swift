//
//  ExpiryStore.swift
//  「效期管理」的数据仓库 —— 记录持久化 + 到期本地通知。
//
//  存储选型：写文件而不是 UserDefaults。
//    · 记录会随使用持续增长，UserDefaults 是给「小配置」用的，塞大数组会让
//      整个 plist 每次启动全量解析；
//    · 文件可以单独设置数据保护等级、可以原子替换、可以整体删除。
//
//  安全 / 健壮性措施：
//    · 单条记录长度上限 + 总条数上限（防止历史数据无限膨胀吃内存）；
//    · 原子写入 + `.completeFileProtection`（锁屏后不可读）；
//    · 解码失败不让 App 崩，退回空表并保留坏文件（改名 `.corrupt`）便于排查；
//    · 写盘放到 utility 队列，不占主线程。
//
//  通知策略（2026-10-09 起为**五档**）：
//    每个「里程碑」（最佳使用时间 / 原始保质期；康普茶是完成时间）排 5 条：
//      ① 前一天 09:00   正常推送
//      ② 当天   09:00   正常推送
//      ③ 提前 1 小时    正常推送
//      ④ 提前 10 分钟   正常推送 + 可带「已完成使用 / 稍后提醒」两个动作
//      ⑤ 到时间         正常推送 + 同上两个动作
//    （④⑤ 还会在 App 前台时被 `ExpiryActivityManager` 拿去挂灵动岛倒计时。）
//
//  ★ iOS 的待发通知上限是 **64 条**。五档之后每条记录要 10 条，
//    按记录数设上限（老的 `reminderRecordLimit`）已经不够用 ——
//    现在改成「把所有候选通知按触发时刻排序，只取最近的前 60 条」，
//    把余量留给真正快到期的物料。
//
//  ★ 「稍后提醒」的重复提醒（每 5 分钟）是一条 `repeats: true` 的独立通知，
//    它会在**任何一次 `rescheduleReminders`**（= 记录有增删改）时被一起清掉。
//
//  ★★★ 2026-10-10 第十二轮（用户第 3 条）—— **有灵动岛胶囊时不弹横幅**：
//    用户原话：「如图的通知，仅应存在锁屏和通知中心中，不应存在横幅，
//    因为横幅应该是灵动岛胶囊。需要更正为：在手机任意 app 界面或主界面状态下，
//    如果有灵动岛胶囊紧凑态存在，就关闭横幅的消息通知」。
//
//    ➜ 规则：若某个里程碑**此刻正挂在灵动岛上**（判据与
//      `ExpiryActivityManager.nearestMilestone` 同源），它的
//      「提前 1 小时 / 提前 10 分钟 / 到点」三档通知一律改成
//      `interruptionLevel = .passive` —— 只进**通知中心与锁屏**，不弹横幅。
//      「前一天 / 当天 09:00」两档是纯预告，**保留横幅**。
//    ➜ 没被挂上岛的里程碑（比如 App 超过 8 小时没打开、活动被系统回收）
//      照旧弹横幅 —— 保证「没有胶囊时不会漏掉提醒」。
//

import Combine
import Foundation
import UserNotifications

final class ExpiryStore: ObservableObject {

    static let shared = ExpiryStore()

    /// 全部记录（新→旧）。
    @Published private(set) var records: [LabelRecord] = []
    /// 到期提醒开关（持久化）。
    @Published private(set) var reminderEnabled: Bool = false
    /// 系统通知权限是否被拒（用来给用户一个「去设置」的入口）。
    @Published private(set) var notificationDenied: Bool = false

    /// 记录条数上限。
    static let maxRecords = 500
    /// 最多排多少条待发通知。
    ///
    /// ★ iOS 系统上限是 64 条；留 4 条余量给「稍后提醒」的重复通知等。
    ///   超出的部分按**触发时刻从近到远**截断 —— 快到期的物料一定要保得住。
    private static let maxPendingNotifications = 60
    /// 每个里程碑排几档通知（前一天 09:00 / 当天 09:00 / 提前 1 小时 / 提前 10 分钟 / 到时间强化）。
    ///
    /// ★★ 2026-10-09 第二轮：编号定为 5 档，第 5 档（到时间）**当时故意空着**，
    ///   理由是「那一刻由灵动岛承担」。**那个理由已被证伪** ——
    ///   灵动岛不会自动展开（平台无此 API），所以那一刻其实什么都没发生。
    /// ★★ 2026-10-10 第五轮：**第 5 档已启用**，改排
    ///   `timeSensitive` + 带按钮的强化通知（见 `candidates` 的 tier 4）。
    ///   编号仍保留 5 —— `ids(for:)` 与 `cancelNotifications(for:)` 的下标依赖它。
    private static let tiersPerMilestone = 5

    private static let reminderKey = "expiryReminderEnabled"
    private static let idPrefix = "expiry.milestone."
    /// 每个里程碑 5 个档位 → 一条记录最多 2 × 5 = 10 个 identifier。
    private static let notificationsPerRecord = 2 * tiersPerMilestone

    /// 提前多久的「临期提醒」（正常推送）。
    private static let soonTier: TimeInterval = 60 * 60          // 1 小时
    /// 提前多久的「临近提醒」（带按钮 + 可上灵动岛）。
    private static let imminentTier: TimeInterval = 10 * 60      // 10 分钟
    /// 「稍后提醒」的重复间隔。
    static let snoozeInterval: TimeInterval = 5 * 60             // 5 分钟

    // MARK: - 通知分类（动作按钮）

    /// 普通推送：没有按钮。
    static let categoryNotice = "expiry.notice"
    /// 临期 / 到时间：带「已完成使用」「稍后提醒」两个按钮。
    static let categoryDue = "expiry.due"
    static let actionDone = "expiry.action.done"
    static let actionSnooze = "expiry.action.snooze"

    /// 注册通知分类。**必须尽早调用**（App 启动时），否则通知上不会有按钮。
    ///
    /// ★ 「稍后提醒」的重复通知也用 `categoryDue`，这样用户从通知上
    ///   直接点「已完成使用」就能让它停下来。
    static func registerCategories() {
        let done = UNNotificationAction(identifier: actionDone,
                                        title: "已完成使用",
                                        options: [])
        let snooze = UNNotificationAction(identifier: actionSnooze,
                                          title: "稍后提醒",
                                          options: [])
        let due = UNNotificationCategory(identifier: categoryDue,
                                         actions: [done, snooze],
                                         intentIdentifiers: [],
                                         options: [.customDismissAction])
        let notice = UNNotificationCategory(identifier: categoryNotice,
                                            actions: [],
                                            intentIdentifiers: [],
                                            options: [])
        UNUserNotificationCenter.current().setNotificationCategories([due, notice])
    }

    private let io = DispatchQueue(label: "com.xiaoqi.expiry.store", qos: .utility)
    private let fileURL: URL

    // MARK: - 生命周期

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("ExpiryRecords", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("records.json")

        reminderEnabled = UserDefaults.standard.bool(forKey: Self.reminderKey)
        load()
        // ★ 通知分类要尽早注册 —— 否则已排好的通知上不会出现
        //   「已完成使用 / 稍后提醒」两个按钮（分类是投递那一刻从系统查的）。
        Self.registerCategories()
        refreshNotificationStatus()
    }

    // MARK: - 查询

    /// 需要提醒的条数（进 Tab 角标）。
    var alertingCount: Int {
        records.filter { ExpiryStatus.of($0).isAlerting }.count
    }

    /// 按「到期阶段」分组后的记录，组内按到期时间升序。
    /// - Parameter includeUsed: 是否显示已用完的记录。
    func grouped(includeUsed: Bool = false, now: Date = Date()) -> [ExpiryGroup] {
        var buckets: [ExpiryStage: [LabelRecord]] = [:]
        for record in records {
            let status = ExpiryStatus.of(record, now: now)
            if status.stage == .used && !includeUsed { continue }
            buckets[status.stage, default: []].append(record)
        }
        return ExpiryStage.allCases
            .sorted()
            .compactMap { stage in
                guard let items = buckets[stage], !items.isEmpty else { return nil }
                let sorted = items.sorted { $0.dueDate < $1.dueDate }
                let title = ExpiryStatus.of(sorted[0], now: now).groupTitle
                return ExpiryGroup(status: stage, title: title, items: sorted)
            }
    }

    // MARK: - 增删改

    /// 新增或更新一条记录。
    /// 同一条标签重复打印 / 重复扫码时，按二维码原文去重，更新旧记录而不是堆一条新的。
    func add(_ record: LabelRecord) {
        onMain { [weak self] in
            guard let self else { return }
            var list = self.records
            if let index = list.firstIndex(where: {
                !$0.qrText.isEmpty && $0.qrText == record.qrText
            }) {
                var merged = record
                merged.id = list[index].id
                merged.usedAt = list[index].usedAt
                list[index] = merged
            } else {
                list.insert(record, at: 0)
            }
            if list.count > Self.maxRecords {
                list = Array(list.prefix(Self.maxRecords))
            }
            self.commit(list)
        }
    }

    func markUsed(_ record: LabelRecord, used: Bool = true) {
        onMain { [weak self] in
            guard let self else { return }
            let list = self.records.map { item -> LabelRecord in
                guard item.id == record.id else { return item }
                var copy = item
                copy.usedAt = used ? Date() : nil
                return copy
            }
            self.commit(list)
        }
    }

    func delete(_ record: LabelRecord) {
        cancelNotifications(for: record)
        onMain { [weak self] in
            guard let self else { return }
            self.commit(self.records.filter { $0.id != record.id })
        }
    }

    func clearAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        onMain { [weak self] in
            guard let self else { return }
            self.commit([])
        }
    }

    // MARK: - 到期提醒

    func setReminderEnabled(_ enabled: Bool) {
        guard enabled else {
            reminderEnabled = false
            UserDefaults.standard.set(false, forKey: Self.reminderKey)
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            // 提醒关了，灵动岛也不该继续挂着。
            syncActivity()
            return
        }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.notificationDenied = !granted
                    self.reminderEnabled = granted
                    UserDefaults.standard.set(granted, forKey: Self.reminderKey)
                    if granted { self.rescheduleReminders() }
                }
            }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                let denied = settings.authorizationStatus == .denied
                self.notificationDenied = denied
                if denied && self.reminderEnabled {
                    self.reminderEnabled = false
                    UserDefaults.standard.set(false, forKey: Self.reminderKey)
                    self.syncActivity()
                }
            }
        }
    }

    /// 重排所有到期提醒；记录变化后调用。
    ///
    /// ★ 两个里程碑都要提醒（用户要求）：
    ///     · 最佳使用时间 —— 所有模板都有
    ///     · 原始保质期 —— 通用/奶制品/肉类有；康普茶没有，它的第二组时间是
    ///       「完成时间」（可以喝 / 可以做二发的时刻），提醒文案按这个语义出。
    ///
    /// ★★ 2026-10-09 改成「五档 + 按时刻择优」：
    ///     · 每个里程碑 5 档（前一天 09:00 / 当天 09:00 / 提前 1 小时 /
    ///       提前 10 分钟 / 到时间），见文件头；
    ///     · 候选通知先全部生成，再**按触发时刻排序取前 60 条** ——
    ///       不再按记录数拍脑袋限流，快到期的物料永远排在前面。
    func rescheduleReminders() {
        let center = UNUserNotificationCenter.current()
        // 本 App 是这些通知的唯一来源，整批清掉最干净 ——
        // ★ 也顺手清掉旧版本用别的 identifier 排下的残留通知（否则它们还会照常弹），
        //   以及上一轮的「稍后提醒」重复通知。
        center.removeAllPendingNotificationRequests()

        setBadge(alertingCount)

        // 灵动岛跟着一起对齐（关掉提醒时它会自己收掉）。
        syncActivity()

        guard reminderEnabled else { return }
        let now = Date()

        // ★★★【第十二轮·用户第 3 条】先算出「此刻挂在灵动岛上的那个里程碑」。
        //   命中它的那几档通知要**静默**（只进通知中心 / 锁屏、不弹横幅）——
        //   因为那一刻屏幕上已经有灵动岛胶囊在显示同一件事，横幅纯属重复。
        //   ⚠️ 规则与 `ExpiryActivityManager.nearestMilestone` **同源**，
        //     不会出现「岛上挂 A、判静默用 B」。
        //   ⚠️ **必须先确认系统实时活动开关是开着的** —— 关掉时岛上根本
        //     不会有胶囊，此时若还静默通知，用户会两头都收不到。
        let island = ExpiryActivityManager.liveActivitiesEnabled
            ? ExpiryActivityManager.nearestMilestone(records: records, now: now)
            : nil

        var candidates: [Candidate] = []
        for record in records where record.usedAt == nil {
            candidates.append(contentsOf: Self.candidates(for: record, now: now,
                                                          island: island))
        }
        candidates.sort { $0.fire < $1.fire }

        for item in candidates.prefix(Self.maxPendingNotifications) {
            center.add(UNNotificationRequest(identifier: item.id,
                                             content: item.content,
                                             trigger: item.trigger))
        }
    }

    /// 一条待排的通知（先生成、后排序截断）。
    private struct Candidate {
        let id: String
        let fire: Date
        let content: UNMutableNotificationContent
        let trigger: UNNotificationTrigger
    }

    /// 为一条记录生成全部候选通知。
    ///
    /// identifier 的下标规则：`slot * 5 + tier` ——
    /// `slot` 是里程碑序号（**顺序不能改**，见 `milestones(of:)`），
    /// `tier` 是上面那 5 档。`cancelNotifications(for:)` 靠同一套规则整组删。
    ///
    /// ★★★【第十二轮】新增 `island` 参数：**此刻挂在灵动岛上的那个里程碑**
    ///   （由 `ExpiryActivityManager.nearestMilestone` 按同一套规则算出）。
    ///   命中它的那几档通知会带 `quiet: true` → `interruptionLevel = .passive`
    ///   → **只进通知中心与锁屏，不弹横幅**（用户第 3 条要求）。
    private static func candidates(for record: LabelRecord,
                                   now: Date,
                                   island: (record: LabelRecord,
                                            milestone: ExpiryMilestone)?) -> [Candidate] {
        var out: [Candidate] = []
        let ids = ids(for: record)
        let kindLabel = record.kind.label

        for (slot, milestone) in milestones(of: record).enumerated() {
            let base = slot * tiersPerMilestone
            let day = AppCalendar.shared.startOfDay(for: milestone.date)

            // ★★★【第十二轮】这条里程碑是不是**正挂在灵动岛上**？
            //   是 → 下面那几档通知一律静默（只进通知中心 / 锁屏）。
            //   ⚠️ 判据必须是「**同一条记录 + 同一个时刻**」，不能只看
            //     「岛上有没有东西」—— 多条记录同时临期时，没被挂上去的
            //     那些必须照旧弹横幅，否则用户会漏掉真正的提醒。
            let onIsland = island.map {
                $0.record.id == record.id
                    && abs($0.milestone.date.timeIntervalSince(milestone.date)) < 1
            } ?? false

            // ①② 前一天 / 当天 09:00（沿用旧行为：把「哪一天」提前一天告诉用户）
            for (offset, tier) in [(-1, 0), (0, 1)] {
                guard let d = AppCalendar.shared.date(byAdding: .day, value: offset, to: day),
                      let fire = AppCalendar.shared.date(bySettingHour: 9, minute: 0, second: 0,
                                                         of: d),
                      fire > now else { continue }
                let content = makeContent(
                    title: offset < 0 ? milestone.tomorrowTitle : milestone.todayTitle,
                    body: "\(record.title)（\(kindLabel)）"
                        + (offset < 0 ? milestone.tomorrowBody : milestone.todayBody),
                    record: record, milestone: milestone,
                    category: categoryNotice, timeSensitive: false,
                    // ★【第十二轮】前一天 / 当天 09:00 这两档**永远保留横幅**：
                    //   它们是「预告」，且 9 点这一刻岛上的倒计时还没进入
                    //   用户要处理的那个窗口（多数情况下里程碑还在 8 小时之外）。
                    quiet: false)
                out.append(Candidate(
                    id: ids[base + tier],
                    fire: fire,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: AppCalendar.shared.dateComponents(
                            [.year, .month, .day, .hour, .minute], from: fire),
                        repeats: false)))
            }

            // ③④ 提前 1 小时 / 提前 10 分钟
            for (delta, tier) in [(soonTier, 2), (imminentTier, 3)] {
                let fire = milestone.date.addingTimeInterval(-delta)
                guard fire > now else { continue }
                // 提前 1 小时：纯告知。提前 10 分钟：带按钮 + 时效性。
                let isImminent = (tier == 3)
                let content = makeContent(
                    title: isImminent ? milestone.dueTitle : milestone.soonTitle,
                    body: "\(record.title)（\(kindLabel)）"
                        + (isImminent ? milestone.dueBody : milestone.soonBody),
                    record: record, milestone: milestone,
                    category: isImminent ? categoryDue : categoryNotice,
                    timeSensitive: isImminent,
                    // ★【第十二轮】提前 1 小时 / 提前 10 分钟 —— 这两档到点时
                    //   灵动岛基本一定在显示这条（它就在 8 小时窗口里），
                    //   所以命中岛上时改走静默。
                    quiet: onIsland)
                out.append(Candidate(
                    id: ids[base + tier],
                    fire: fire,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: AppCalendar.shared.dateComponents(
                            [.year, .month, .day, .hour, .minute], from: fire),
                        repeats: false)))
            }

            // ⑤ 到时间那一刻 —— **强化通知**（tier 4）。
            //
            // ★★ 2026-10-10 第五轮修正（用户反复反馈「倒计时结束后无铃感/无强化通知」）：
            //    之前这里**故意空着**，理由是「那一刻由灵动岛自动展开承担」——
            //    但那是**错的**：**灵动岛不会自动展开**（平台没这个 API，
            //    只有用户长按或系统事件才会展开，见 ExpiryLiveActivity.swift 文件头）。
            //    所以那一刻其实**什么都没发生** → 用户完全被漏掉。
            //
            //    ✅ 现在补回这一档：到点即弹一条
            //       · `interruptionLevel = .timeSensitive`（能穿透专注模式，
            //         这是免费账号能拿到的最强级别 —— `.critical` 需要苹果特批）；
            //       · 走 `categoryDue` 类别 → 通知上直接带
            //         「已完成使用 / 稍后提醒」两个按钮，不用打开 App；
            //       · 用 `UNTimeIntervalNotificationTrigger`（而不是日历触发器），
            //         因为到点时刻就是「现在」，秒级精度更稳。
            //
            //    ➜ 这才是「强化通知」在无推送能力下的正确形态：
            //      **声音 + 时效性横幅 + 直接可操作按钮**。
            //      ⚠️ tier 4 的编号是历史约定（见文件头的 5 档说明），**别改**。
            let dueDelta = milestone.date.timeIntervalSince(now)
            if dueDelta > 0, dueDelta <= 60 * 60 * 24 * 30 {
                let content = makeContent(
                    title: milestone.strengthenTitle,
                    body: "\(record.title)（\(kindLabel)）" + milestone.strengthenBody,
                    record: record, milestone: milestone,
                    category: categoryDue,
                    timeSensitive: true,
                    // ★★★【第十二轮·用户第 3 条的正主】用户截图里那条横幅就是这一档。
                    //   它响的那一刻，灵动岛上正挂着同一条记录（到点 / 已到时间 + 两个按钮）
                    //   → 改走静默：只进通知中心与锁屏，不再弹横幅。
                    //   ⚠️ 若这一刻**岛上没有**它（例如 App 已 8 小时没打开、
                    //     活动被系统回收），`onIsland` 为 false，横幅照旧 ——
                    //     这正是用户说的「如果有胶囊存在才关掉横幅」。
                    quiet: onIsland)
                out.append(Candidate(
                    id: ids[base + 4],
                    fire: milestone.date,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(
                        timeInterval: max(dueDelta, 1),
                        repeats: false)))
            }
        }
        return out
    }

    /// 造一条通知内容。
    ///
    /// ★★★【第十二轮·用户第 3 条】新增 `quiet` —— 「有灵动岛胶囊时不弹横幅」。
    ///
    ///   做法是把 `interruptionLevel` 设成 **`.passive`**。这是 iOS 上**唯一**
    ///   能做到「只进通知中心 / 锁屏、不弹横幅、不亮屏、不响铃」的档位 ——
    ///   Apple 官方原文（UNNotificationInterruptionLevel.passive）：
    ///     「The system adds the notification to the notification list
    ///       **without lighting up the screen or playing a sound**.」
    ///   HIG 里那张表也印证：Passive 不打断用户、不穿透专注模式。
    ///
    ///   ⚠️ 它会**连声音一起去掉** —— 这是系统行为，不是我们额外关的；
    ///      iOS 没有「不弹横幅但保留声音」的档位。
    ///   ➜ 所以这一刻的「响铃 + 打断」交给**灵动岛那条预定警报**
    ///     （`ExpiryActivityManager.scheduleAlert` 的 `AlertConfiguration`
    ///      `sound: .default`）—— 用户要的正是「横幅就是灵动岛胶囊」。
    ///
    ///   ⚠️ 顺序很重要：`quiet` 优先于 `timeSensitive`。两者同时设没有意义，
    ///     `.passive` 的「不打断」会被 `.timeSensitive` 的「穿透专注」抵消。
    private static func makeContent(title: String,
                                    body: String,
                                    record: LabelRecord,
                                    milestone: ExpiryMilestone,
                                    category: String,
                                    timeSensitive: Bool,
                                    quiet: Bool = false) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        if quiet {
            content.interruptionLevel = .passive
        } else if timeSensitive {
            content.interruptionLevel = .timeSensitive
        }
        content.userInfo = [
            Self.userInfoRecordID: record.id.uuidString,
            Self.userInfoDueAt: milestone.date.timeIntervalSince1970,
        ]
        return content
    }

    /// 通知里携带的记录定位信息（点了按钮之后要用）。
    static let userInfoRecordID = "expiryRecordID"
    static let userInfoDueAt = "expiryDueAt"

    // MARK: - 通知动作

    /// 用户点了通知 / 灵动岛上的按钮之后，由 `UNUserNotificationCenterDelegate` 转发进来。
    func handleNotificationResponse(actionIdentifier: String,
                                    userInfo: [AnyHashable: Any]) {
        guard let id = userInfo[Self.userInfoRecordID] as? String else { return }
        switch actionIdentifier {
        case Self.actionDone:
            markUsed(byID: id)
            Task { await ExpiryActivityManager.shared.end(recordID: id) }
        case Self.actionSnooze:
            let due = (userInfo[Self.userInfoDueAt] as? Double)
                .map { Date(timeIntervalSince1970: $0) }
            startSnooze(byID: id, dueAt: due)
        default:
            break
        }
    }

    /// 「已完成使用」——按 id 找记录并标记用完。
    ///
    /// ★ 为什么不直接用 `markUsed(_:)`：通知 / 灵动岛只拿得到一个 uuid 字符串，
    ///   而且回调可能不在主线程上；这里统一走 `onMain`，查找与写入都在主线程做。
    func markUsed(byID idString: String) {
        onMain { [weak self] in
            guard let self else { return }
            let list = self.records.map { item -> LabelRecord in
                guard item.id.uuidString == idString else { return item }
                var copy = item
                copy.usedAt = Date()
                return copy
            }
            self.commit(list)
        }
    }

    /// 「稍后提醒」。
    ///
    /// ★★ 用户规则（清单「三、效期管理」第 2 条）：
    ///     · 「提前 10 分钟」那条点稍后提醒 → **不做任何操作**
    ///     · 「到时间」那条点稍后提醒 → **每 5 分钟提醒一次**
    ///   判据就是「点下去的这一刻有没有到时间」。
    ///
    /// ★ 每 5 分钟循环靠一条 `repeats: true` 的本地通知做心跳
    ///   （只占 1 个待发名额）。灵动岛那边的倒计时重置是另一条路：
    ///   按钮走 `ExpiryActivityBridge.snooze` → `ExpiryActivityManager.restart`。
    ///
    /// ★★ 2026-10-09 修「点击完无重新倒计时 5 分钟」：通知里带的
    ///   `userInfoDueAt` 改成 **新的 5 分钟目标时刻**，而不是原来那个已经过去的
    ///   `dueAt` —— 否则用户从**通知上**再点一次「稍后提醒」会被
    ///   `guard Date() >= dueAt` 通过（对），但活动那边拿到的还是旧时刻，
    ///   倒计时依旧不动。
    ///
    /// 停止它的方式：点「已完成使用」，或任何一次记录改动
    /// （`rescheduleReminders` 会整批清掉）。identifier 固定按记录 id 生成，
    /// 重复点「稍后提醒」也只会有一条。
    func startSnooze(byID idString: String, dueAt: Date?) {
        // 还没到时间（= 提前 10 分钟那一档）→ 什么都不做。
        guard let dueAt, Date() >= dueAt else { return }
        onMain { [weak self] in
            guard let self,
                  let record = self.records.first(where: { $0.id.uuidString == idString }),
                  record.usedAt == nil else { return }
            // ★ 新的目标时刻 = 现在 + 5 分钟（不是原来的 dueAt）。
            let target = Date().addingTimeInterval(Self.snoozeInterval)
            let content = UNMutableNotificationContent()
            content.title = "还不处理吗？"
            content.body = "\(record.title)（\(record.kind.label)）已经到时间了。"
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = Self.categoryDue
            content.userInfo = [
                Self.userInfoRecordID: record.id.uuidString,
                Self.userInfoDueAt: target.timeIntervalSince1970,
            ]
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: Self.snoozeInterval, repeats: true)
            let center = UNUserNotificationCenter.current()
            let id = Self.snoozeID(for: record)
            // 先删同 id 的旧请求，避免叠加出好几条
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    private static func snoozeID(for record: LabelRecord) -> String {
        "\(idPrefix)snooze.\(record.id.uuidString)"
    }

    // MARK: - 里程碑

    /// 一条记录上的一个「值得提醒的时刻」。
    ///
    /// ★ 2026-10-09 扩成五档（前一天 / 当天 / 提前 1 小时 / 到时间 / 到时间强化，
    ///   「提前 1 小时」与「到时间」的正文复用同一套语义）。
    ///   标题里「明天到 xxx / 今天到 xxx / 快到 xxx 了 / xxx 到了」
    ///   多半能从 `label` 自动拼出来，只有康普茶需要自带一套（见 `init`）。
    struct ExpiryMilestone {
        let date: Date
        /// 里程碑名，如「原始保质期」—— 灵动岛上直接显示它。
        let label: String
        let tomorrowTitle: String
        let tomorrowBody: String
        let todayTitle: String
        let todayBody: String
        let soonTitle: String
        let soonBody: String
        let dueTitle: String
        let dueBody: String
        /// ★ 2026-10-10 第五轮：**到时间那一刻的强化通知**专用文案。
        ///   与 `dueTitle` 的区别在于语气更急、更「必须现在处理」，
        ///   并且这一条是带按钮 + `timeSensitive` 的（见 `candidates` 的 tier 4）。
        let strengthenTitle: String
        let strengthenBody: String

        /// 默认标题按 `label` 拼；`tomorrowTitle` / `todayTitle` 传了就用自己的。
        init(date: Date,
             label: String,
             tomorrowTitle: String? = nil,
             tomorrowBody: String,
             todayTitle: String? = nil,
             todayBody: String,
             dueBody: String) {
            self.date = date
            self.label = label
            self.tomorrowTitle = tomorrowTitle ?? "明天到\(label)"
            self.tomorrowBody = tomorrowBody
            self.todayTitle = todayTitle ?? "今天到\(label)"
            self.todayBody = todayBody
            self.soonTitle = "快到\(label)了"
            self.soonBody = "还差 1 小时到\(label)。"
            self.dueTitle = "\(label)到了"
            self.dueBody = dueBody
            // ★ 强化通知：标题用「⚠️」开头 + 明确的「请立即处理」，
            //   和提前 10 分钟那条（`dueTitle`）**刻意不同** ——
            //   用户在锁屏上一眼能分清「还有 10 分钟」和「已经到点」。
            self.strengthenTitle = "⚠️ \(label)已到，请立即处理"
            self.strengthenBody = dueBody + "（现在）"
        }
    }

    /// 一条记录要提醒的时刻（顺序固定：先 `expireAt` 再 `bestBefore`，
    /// 因为通知 identifier 的下标是按这个顺序算出来的，**不要改动顺序**）。
    ///
    /// ★ 一般返回 **2 条**（通知因此是「2 里程碑 × 5 档 = 10 条」）；
    ///   唯一例外是肉类 —— 它两个日期按规则相同，会去重成 1 条（见下方 `.meat` 分支）。
    static func milestones(of record: LabelRecord) -> [ExpiryMilestone] {
        switch record.kind {
        case .generic, .dairy:
            return [
                ExpiryMilestone(date: record.expireAt,
                                label: "原始保质期",
                                tomorrowBody: "明天到原始保质期，之后就别再用了。",
                                todayBody: "今天到原始保质期。",
                                dueBody: "已到原始保质期，之后就别再用了。"),
                ExpiryMilestone(date: record.bestBefore,
                                label: "最佳使用时间",
                                tomorrowBody: "明天到最佳使用时间，记得处理。",
                                todayBody: "今天到最佳使用时间。",
                                dueBody: "已到最佳使用时间，记得处理。"),
            ]
        case .kombucha:
            return [
                // 康普茶的第二组数据是「完成时间」= 可以喝 / 可以做二发的时刻。
                ExpiryMilestone(date: record.expireAt,
                                label: "完成时间",
                                tomorrowTitle: "康普茶明天完成",
                                tomorrowBody: "明天到完成时间，可以饮用或做二发了。",
                                todayTitle: "康普茶已完成",
                                todayBody: "今天到完成时间，可以饮用或做二发了。",
                                dueBody: "已到完成时间，可以饮用或做二发了。"),
                ExpiryMilestone(date: record.bestBefore,
                                label: "最佳使用时间",
                                tomorrowBody: "明天到最佳使用时间，记得处理。",
                                todayBody: "今天到最佳使用时间。",
                                dueBody: "已到最佳使用时间，记得处理。"),
            ]
        case .meat:
            // ★ 2026-10-09 新增肉类。
            //
            // ★ 为什么这里要做「去重」而不是照抄 `.generic, .dairy`：
            //   肉类的两个日期**按规则是完全相同的**（冷藏都 +5 天，冷冻都 +3 个月，
            //   见 `MeatRule.dates`）。若原样返回两条里程碑，就会在**同一时刻**
            //   排出两条 identifier 不同、正文几乎一样的通知 ——
            //   用户一次收到两条「今天到原始保质期 / 今天到最佳使用时间」，很吵。
            //   所以日期相同时只保留「原始保质期」那一条（它是硬底线，语义更强）。
            //   用户手动把其中一个日期改掉时两者不等，两条都排，与通用模板一致。
            let expireMilestone = ExpiryMilestone(
                date: record.expireAt,
                label: "原始保质期",
                tomorrowBody: "明天到原始保质期，之后就别再用了。",
                todayBody: "今天到原始保质期。",
                dueBody: "已到原始保质期，之后就别再用了。")
            guard record.expireAt != record.bestBefore else { return [expireMilestone] }
            return [
                expireMilestone,
                ExpiryMilestone(date: record.bestBefore,
                                label: "最佳使用时间",
                                tomorrowBody: "明天到最佳使用时间，记得处理。",
                                todayBody: "今天到最佳使用时间。",
                                dueBody: "已到最佳使用时间，记得处理。"),
            ]
        }
    }

    // MARK: - 私有

    private static func ids(for record: LabelRecord) -> [String] {
        (0..<notificationsPerRecord).map {
            "\(idPrefix)\($0).\(record.id.uuidString)"
        }
    }

    private func cancelNotifications(for record: LabelRecord) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: Self.ids(for: record) + [Self.snoozeID(for: record)])
    }

    private func setBadge(_ count: Int) {
        guard reminderEnabled else {
            UNUserNotificationCenter.current().setBadgeCount(0)
            return
        }
        UNUserNotificationCenter.current().setBadgeCount(count)
    }

    private func commit(_ list: [LabelRecord]) {
        records = list
        rescheduleReminders()
        persist(list)
    }

    /// 把灵动岛对齐到「最近的那个、8 小时内会到期的里程碑」。
    ///
    /// ★ 为什么放在 Store 里触发而不是只靠页面 `onAppear`：
    ///   记录一变（打印 / 删记录 / 点「已完成」）就应该立刻重算；
    ///   否则会出现「刚把唯一快到期的物料标成用完，岛上还挂着它」。
    ///   冷启动那一次由 `RootView.onAppear` 兜底（那时 `rescheduleReminders`
    ///   还没被调用过）。
    ///
    /// ★ 先快照再异步：`sync` 是 `@MainActor` 的 async 函数，
    ///   不能直接在同步上下文里读 `records`（避免 Swift 并发告警）。
    private func syncActivity() {
        let snapshot = records
        let enabled = reminderEnabled
        Task { await ExpiryActivityManager.shared.sync(records: snapshot, enabled: enabled) }
    }

    private func persist(_ list: [LabelRecord]) {
        let url = fileURL
        io.async {
            do {
                let data = try JSONEncoder().encode(list)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                NSLog("ExpiryStore: 记录写入失败 \(error.localizedDescription)")
            }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder().decode([LabelRecord].self, from: data)
        } catch {
            // 不让坏文件把 App 拖死：留证据、起空表
            NSLog("ExpiryStore: 记录解析失败 \(error.localizedDescription)")
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            records = []
        }
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
