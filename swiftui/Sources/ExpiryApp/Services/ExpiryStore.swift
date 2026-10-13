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
//  通知策略（2026-10-13 起为**单档**）：
//    每个「里程碑」（完成时间 / 最佳使用时间 / 原始保质期，按标签类型）
//    只排 **1 条**通知 —— **提前 5 分钟**提醒一次：
//      · `interruptionLevel = .timeSensitive`（穿透专注模式）；
//      · 动作按钮**按里程碑**定制：「完成时间」→ 只有「已完成」（点击数据零操作）；
//        其余 → 「已完成使用 + 稍后提醒」（点击标用完）。
//    到时间那一刻由系统托管的「到点警报」灵动岛承担（见 `ExpiryActivityManager`），
//    不再另发通知。
//
//  ★★★ 2026-10-13（用户第 2 条）改版说明 ——
//    旧版是「前一天 09:00 / 当天 09:00 / 提前 1 小时 / 提前 10 分钟 / 到点」五档阶梯。
//    用户原话：「倒计时应该是在完成时间、最佳使用时间、原始保质期都做提醒，
//    并且是提前 5 分钟」。➜ 全部收敛成「每时刻一条、提前 5 分钟」。
//    **不要**把五档加回来，除非用户再改需求。
//      · 「完成时间」覆盖：康普茶（= `expireAt` 槽位）、肉类解冻
//        （= 解冻 + 1 天，**也存在 `expireAt` 槽位** —— 2026-10-13 用户第 6 条定版）；
//      · ★★★ 2026-10-13（用户第 6 条）：**按钮文案与点击行为都按「里程碑」判** ——
//        「完成时间」→「已完成」（`categoryDueComplete`，点击数据零操作）；
//        其余（最佳使用时间 / 原始保质期）→「已完成使用」（点击标用完）。
//        ⚠️ 别再退回"按记录判"（`usesCompletionTime`）—— 肉类解冻记录同时挂
//          两种里程碑，记录级判据会把「最佳使用时间」的点击也变成零操作。
//    ⚠️ 旧的「有岛上胶囊时静默横幅（`.passive`）」规则随五档一并删除 ——
//      现在唯一一条提醒**必须带声音**（横幅就是提醒本体）。
//
//  ★ iOS 的待发通知上限是 **64 条**；候选通知按触发时刻排序，只取最近的前 60 条，
//    把余量留给真正快到期的物料。
//
//  ★ 「稍后提醒」的重复提醒（每 5 分钟）是一条 `repeats: true` 的独立通知，
//    它会在**任何一次 `rescheduleReminders`**（= 记录有增删改）时被一起清掉。
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
    private static let reminderKey = "expiryReminderEnabled"
    private static let idPrefix = "expiry.milestone."
    /// identifier 槽位数：每个里程碑 1 条 → 一条记录最多 **2 条**通知
    /// （完成时间 + 最佳使用时间；通用/奶制品是原始保质期 + 最佳使用时间）。
    /// ⚠️ 保留 3（而不是收到 2）：多出来的槽位用于**清理旧版本留下的残留**
    ///   （v1.1.13 及更早给肉类解冻排过 slot 2 的「原始保质期」通知）。
    private static let notificationsPerRecord = 3
    /// ★★★ 2026-10-13（用户第 2 条）：**提前多久提醒** —— 统一 5 分钟。
    ///   （旧版的 1 小时 / 10 分钟两档随五档阶梯一起删除。）
    private static let reminderLead: TimeInterval = 5 * 60
    /// 「稍后提醒」的重复间隔。
    static let snoozeInterval: TimeInterval = 5 * 60             // 5 分钟

    // MARK: - 通知分类（动作按钮）

    /// 提醒通知：带「已完成使用」「稍后提醒」两个按钮。
    static let categoryDue = "expiry.due"
    /// ★★★ 2026-10-13（用户第 6 条）：**「完成时间」里程碑**专用分类 ——
    ///   按钮只有「已完成」一个（没有「稍后提醒」），点击后**不改记录数据**。
    ///   （康普茶完成、肉类解冻完成，以及以后所有使用完成时间的场景。）
    ///   ⚠️ 判据是**里程碑**（`milestone.label == "完成时间"`），不是记录 ——
    ///     肉类解冻的「最佳使用时间」必须走 `categoryDue`（点击标用完）。
    static let categoryDueComplete = "expiry.due.complete"
    static let actionDone = "expiry.action.done"
    /// 「已完成」按钮的动作 id（真实行为由**里程碑**决定，见 `completeOrUse`）。
    static let actionComplete = "expiry.action.complete"
    static let actionSnooze = "expiry.action.snooze"

    /// 注册通知分类。**必须尽早调用**（App 启动时），否则通知上不会有按钮。
    ///
    /// ★ 「稍后提醒」的重复通知也用这两个分类，这样用户从通知上
    ///   直接点按钮就能让它停下来。
    /// ★★★ 2026-10-13（用户第 6 条）：`categoryDueComplete`（「完成时间」用）
    ///   **只保留「已完成」一个按钮** —— 完成是"可以开始使用"的确认，
    ///   没有"稍后提醒"的语义（用户原话：「按钮应该只有已完成」）。
    ///   其余里程碑走的 `categoryDue` 保持「已完成使用 + 稍后提醒」。
    static func registerCategories() {
        let done = UNNotificationAction(identifier: actionDone,
                                        title: "已完成使用",
                                        options: [])
        let complete = UNNotificationAction(identifier: actionComplete,
                                            title: "已完成",
                                            options: [])
        let snooze = UNNotificationAction(identifier: actionSnooze,
                                          title: "稍后提醒",
                                          options: [])
        let due = UNNotificationCategory(identifier: categoryDue,
                                         actions: [done, snooze],
                                         intentIdentifiers: [],
                                         options: [.customDismissAction])
        let dueComplete = UNNotificationCategory(identifier: categoryDueComplete,
                                                 actions: [complete],
                                                 intentIdentifiers: [],
                                                 options: [.customDismissAction])
        UNUserNotificationCenter.current().setNotificationCategories([due, dueComplete])
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
    /// ★ 提醒覆盖的时刻（2026-10-13 用户第 2 条）：
    ///     · 最佳使用时间 —— 所有模板都有；
    ///     · 原始保质期 —— 通用 / 奶制品 / 肉类有；康普茶没有（它的第二组
    ///       时间是「完成时间」）；
    ///     · 完成时间 —— 康普茶（`expireAt` 槽位）与肉类解冻（= 解冻 + 1 天）。
    ///   每个时刻在**提前 5 分钟**提醒一条（见文件头）。
    ///
    /// ★ 候选通知先全部生成，再**按触发时刻排序取前 60 条** ——
    ///   快到期的物料永远排在前面。
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

        // ★★★ 2026-10-13（用户第 2 条）：提醒唯一一条，**必须带声音** ——
        //   旧的「有岛上胶囊时静默横幅」规则（第十二轮）随五档阶梯一并删除。
        var candidates: [Candidate] = []
        for record in records where record.usedAt == nil {
            candidates.append(contentsOf: Self.candidates(for: record, now: now))
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
    /// identifier 的下标规则：`slot`（里程碑序号，见 `milestones(of:)` 的固定顺序）
    /// —— `cancelNotifications(for:)` 靠同一套规则整组删。
    ///
    /// ★★★ 2026-10-13（用户第 2 条）**重新定版：每个里程碑只排一条** ——
    ///   **提前 5 分钟**（`reminderLead`）提醒；旧五档阶梯（前一天 09:00 /
    ///   当天 09:00 / 提前 1 小时 / 提前 10 分钟 / 到点）全部删除，
    ///   到点那一刻由系统托管的「到点警报」灵动岛承担，不再另发通知。
    private static func candidates(for record: LabelRecord, now: Date) -> [Candidate] {
        var out: [Candidate] = []
        let ids = ids(for: record)
        let kindLabel = record.kind.label

        for (slot, milestone) in milestones(of: record).enumerated() {
            let fire = milestone.date.addingTimeInterval(-reminderLead)
            guard fire > now else { continue }

            // ★★★ 2026-10-13（用户第 6 条）：分类按**里程碑**选（不是按记录）——
            //   「完成时间」→ `categoryDueComplete`（按钮只有「已完成」、点击零操作）；
            //   其余（最佳使用时间 / 原始保质期）→ `categoryDue`
            //   （「已完成使用」→ 标用完）。
            //   ⚠️ 肉类解冻记录同时挂这两种里程碑，原来按记录判会让它的
            //     「最佳使用时间」也变成"已完成 + 点击无操作" —— 用户明确否掉。
            let category = milestone.label == ExpiryActivityAttributes.completionMilestoneLabel
                ? categoryDueComplete
                : categoryDue

            let content = UNMutableNotificationContent()
            content.title = "还有 \(Int(Self.reminderLead / 60)) 分钟到\(milestone.label)"
            content.body = "\(record.title)（\(kindLabel)）"
            content.sound = .default
            content.categoryIdentifier = category
            // 时效性：能穿透专注模式（免费账号能拿到的最强级别）。
            content.interruptionLevel = .timeSensitive
            content.userInfo = [
                Self.userInfoRecordID: record.id.uuidString,
                Self.userInfoDueAt: milestone.date.timeIntervalSince1970,
                // ★ 里程碑名一并带上 —— 点按钮时的数据行为按它判定（见 `completeOrUse`）。
                Self.userInfoMilestone: milestone.label,
            ]
            out.append(Candidate(
                id: ids[slot],
                fire: fire,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: AppCalendar.shared.dateComponents(
                        [.year, .month, .day, .hour, .minute], from: fire),
                    repeats: false)))
        }
        return out
    }

    /// 通知里携带的记录定位信息（点了按钮之后要用）。
    static let userInfoRecordID = "expiryRecordID"
    static let userInfoDueAt = "expiryDueAt"
    /// ★★★ 2026-10-13（用户第 6 条）：通知里一并带的**里程碑名** ——
    ///   点按钮时按它区分「已完成（数据零操作）」与「已完成使用（标用完）」。
    ///   ⚠️ 老通知（本版之前排下的）没有这个键 → 读取为 nil，
    ///      `completeOrUse` 会退回按记录判（兼容，见其注释）。
    static let userInfoMilestone = "expiryMilestone"

    // MARK: - 通知动作

    /// 用户点了通知 / 灵动岛上的按钮之后，由 `UNUserNotificationCenterDelegate` 转发进来。
    func handleNotificationResponse(actionIdentifier: String,
                                    userInfo: [AnyHashable: Any]) {
        guard let id = userInfo[Self.userInfoRecordID] as? String else { return }
        switch actionIdentifier {
        case Self.actionDone, Self.actionComplete:
            // ★★★ 2026-10-13（用户第 6 条）：动作的真实行为由**里程碑**决定 ——
            //   「完成时间」（康普茶完成 / 肉类解冻完成）→ 数据零操作；
            //   其余（最佳使用时间 / 原始保质期）→ 标记用完。两种情况都收掉灵动岛。
            completeOrUse(byID: id, milestoneLabel: userInfo[Self.userInfoMilestone] as? String)
            Task { await ExpiryActivityManager.shared.end(recordID: id) }
        case Self.actionSnooze:
            let due = (userInfo[Self.userInfoDueAt] as? Double)
                .map { Date(timeIntervalSince1970: $0) }
            startSnooze(byID: id, dueAt: due)
        default:
            break
        }
    }

    /// 「已完成 / 已完成使用」的统一入口（通知动作与灵动岛按钮都走这里）。
    ///
    /// ★★★ 2026-10-13（用户第 6 条）：**判据从「记录」改成「里程碑」** ——
    ///   · 里程碑是「完成时间」（康普茶完成 / 肉类解冻完成）→ **数据零操作**
    ///     （完成 ≠ 吃掉：记录继续留在效期管理里接受「最佳使用时间」的后续提醒）；
    ///   · 其余里程碑（最佳使用时间 / 原始保质期）→ 标记为「已用完」。
    ///   ⚠️ 肉类解冻记录同时挂这两种里程碑，按记录判会让「最佳使用时间」
    ///     的点击也变成零操作 —— 那正是用户第 6 条纠的点。
    ///   ⚠️ `milestoneLabel == nil`（老通知 / 旧入口没带）→ 退回按记录判（兼容）。
    ///
    /// ★ 通知 / 灵动岛只拿得到一个 uuid 字符串，而且回调可能不在主线程上；
    ///   这里统一走 `onMain`，查找与写入都在主线程做。
    func completeOrUse(byID idString: String, milestoneLabel: String? = nil) {
        onMain { [weak self] in
            guard let self,
                  let record = self.records.first(where: { $0.id.uuidString == idString })
            else { return }

            let isCompletion: Bool
            if let milestoneLabel {
                isCompletion = (milestoneLabel == ExpiryActivityAttributes.completionMilestoneLabel)
            } else {
                // 兼容路径：老通知没有里程碑字段，按记录判 —— 与旧行为一致。
                isCompletion = record.usesCompletionTime
            }
            if isCompletion { return }   // 「已完成」：数据零操作。

            // 其余里程碑 → 标记用完。
            let list = self.records.map { item -> LabelRecord in
                guard item.id == record.id else { return item }
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
        // 还没到时间（= 提前 5 分钟那条）→ 什么都不做。
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
    /// ★★★ 2026-10-13（用户第 2 条）大幅简化：每个时刻只在**提前 5 分钟**
    ///   提醒一次，文案由 `candidates` 现拼（「还有 5 分钟到X」）——
    ///   所以这里只需要「时刻 + 名称」。
    ///   （旧版的五档文案字段 —— tomorrowTitle / todayTitle / soonTitle /
    ///     dueTitle / strengthenTitle 及各 Body —— 连同五档排程一起删除。）
    struct ExpiryMilestone {
        /// 时刻本身（提醒 = 这个时刻**提前 5 分钟**）。
        let date: Date
        /// 里程碑名，如「完成时间」/「最佳使用时间」/「原始保质期」——
        /// 通知文案、灵动岛、倒计时全部直接显示它。
        let label: String
    }

    /// 一条记录要提醒的时刻（顺序固定，通知 identifier 的下标按它算，**不要改**）。
    ///
    /// ★ 覆盖（2026-10-13 用户第 2 条）：
    ///     · 通用 / 奶制品：原始保质期 + 最佳使用时间（2 条）；
    ///     · 康普茶：完成时间（`expireAt` 槽位）+ 最佳使用时间（2 条，无原始保质期）；
    ///     · 肉类：解冻标签三个时刻 —— 完成时间（解冻 + 1 天，**派生值**）+
    ///       最佳使用时间 + 原始保质期；非解冻的按原规则去重（多为 1 条）。
    static func milestones(of record: LabelRecord) -> [ExpiryMilestone] {
        switch record.kind {
        case .generic, .dairy:
            return [
                ExpiryMilestone(date: record.expireAt, label: "原始保质期"),
                ExpiryMilestone(date: record.bestBefore, label: "最佳使用时间"),
            ]
        case .kombucha:
            // 康普茶的第二组数据是「完成时间」= 可以喝 / 可以做二发的时刻。
            return [
                ExpiryMilestone(date: record.expireAt,
                                label: ExpiryActivityAttributes.completionMilestoneLabel),
                ExpiryMilestone(date: record.bestBefore, label: "最佳使用时间"),
            ]
        case .meat:
            // ★★★ 2026-10-13（用户第 6 条）：解冻标签只有**两个**提醒时刻 ——
            //   完成时间 / 最佳使用时间。
            //   ⚠️ **没有「原始保质期」** —— 解冻后冷冻原保不再适用；解冻标签的
            //     数据里也没有它（「完成时间」就存在 `expireAt` 槽位，与康普茶同构）。
            //   ⚠️ 完成时间**直接读 `expireAt`**（不是由 `createdAt` 现算）：
            //     打印路径（`MeatThawView`）存的是完成时间、扫码路径从二维码
            //     解析的也是完成时间；若拿 `createdAt` 现算，扫码合并后
            //     （`add` 整体替换记录、只保留 id/usedAt）createdAt 变成扫码时刻
            //     → 算出来的完成时间就错了。
            if record.usesCompletionTime {
                return [
                    ExpiryMilestone(date: record.expireAt,
                                    label: ExpiryActivityAttributes.completionMilestoneLabel),
                    ExpiryMilestone(date: record.bestBefore, label: "最佳使用时间"),
                ]
            }
            // 非解冻肉类：两个日期**按规则完全相同**（冷藏都 +5 天，冷冻都 +3 个月，
            // 见 `MeatRule.dates`）。原样返回会在**同一时刻**排出两条几乎一样的
            // 通知 —— 去重成一条（「原始保质期」是硬底线，语义更强）。
            // 用户手动把其中一个日期改掉时两者不等，两条都排（与通用模板一致）。
            let expireMilestone = ExpiryMilestone(date: record.expireAt, label: "原始保质期")
            guard record.expireAt != record.bestBefore else { return [expireMilestone] }
            return [
                expireMilestone,
                ExpiryMilestone(date: record.bestBefore, label: "最佳使用时间"),
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

    /// 把灵动岛对齐到「最近的那个、窗口内（`ExpiryActivityManager.window`，
    /// 2026-10-13 起 5 分钟）会到期的里程碑」。
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
