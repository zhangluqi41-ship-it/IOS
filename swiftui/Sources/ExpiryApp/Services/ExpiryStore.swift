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
//  通知策略：每条记录排 **4 条**本地通知 ——
//    两个里程碑（最佳使用时间 / 原始保质期，康普茶是完成时间）× 前一天 09:00、当天 09:00。
//  只对最近 60 天内还有里程碑的记录排，最多 12 条记录 ——
//  iOS 的待发通知上限是 64 条，12 × 4 = 48，留出余量。
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
    /// 排通知时最多考虑多少条记录。
    ///
    /// ★ 每条记录现在要排 **4 条**通知（两个里程碑 × 前一天 / 当天），
    ///   而 iOS 的待发通知上限是 64 条 —— 12 × 4 = 48，留出余量。
    private static let reminderRecordLimit = 12
    /// 只给多少天内还有里程碑的记录排通知。
    private static let reminderHorizonDays = 60

    private static let reminderKey = "expiryReminderEnabled"
    private static let idPrefix = "expiry.milestone."
    /// 每条记录排几条通知（两个里程碑 × 2）。
    private static let notificationsPerRecord = 4

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
                }
            }
        }
    }

    /// 重排所有到期提醒；记录变化后调用。
    ///
    /// ★ 两个里程碑都要提醒（用户要求）：
    ///     · 最佳使用时间 —— 所有模板都有
    ///     · 原始保质期 —— 通用/奶制品有；康普茶没有，它的第二组时间是
    ///       「完成时间」（可以喝 / 可以做二发的时刻），提醒文案按这个语义出。
    func rescheduleReminders() {
        let center = UNUserNotificationCenter.current()
        // 本 App 是这些通知的唯一来源，整批清掉最干净 ——
        // ★ 也顺手清掉旧版本用别的 identifier 排下的残留通知（否则它们还会照常弹）。
        center.removeAllPendingNotificationRequests()

        setBadge(alertingCount)

        guard reminderEnabled else { return }
        let now = Date()
        let horizon = AppCalendar.shared.date(byAdding: .day,
                                              value: Self.reminderHorizonDays, to: now) ?? now

        let upcoming = records
            .filter { $0.usedAt == nil }
            .filter { record in
                Self.milestones(of: record).contains { $0.date > now && $0.date <= horizon }
            }
            .prefix(Self.reminderRecordLimit)

        for record in upcoming {
            let kindLabel = record.kind.label
            for (slot, milestone) in Self.milestones(of: record).enumerated() {
                guard milestone.date > now, milestone.date <= horizon else { continue }
                let day = AppCalendar.shared.startOfDay(for: milestone.date)
                let ids = Self.ids(for: record)
                if let pre = AppCalendar.shared.date(byAdding: .day, value: -1, to: day) {
                    schedule(id: ids[slot * 2],
                             at: pre,
                             title: milestone.tomorrowTitle,
                             body: "\(record.title)（\(kindLabel)）\(milestone.tomorrowBody)")
                }
                schedule(id: ids[slot * 2 + 1],
                         at: day,
                         title: milestone.todayTitle,
                         body: "\(record.title)（\(kindLabel)）\(milestone.todayBody)")
            }
        }
    }

    // MARK: - 里程碑

    /// 一条记录上的一个「值得提醒的时刻」。
    struct ExpiryMilestone {
        let date: Date
        let tomorrowTitle: String
        let tomorrowBody: String
        let todayTitle: String
        let todayBody: String
    }

    /// 一条记录要提醒的两个时刻（顺序固定：先 `expireAt` 再 `bestBefore`，
    /// 因为通知 identifier 的下标是按这个顺序算出来的，**不要改动顺序**）。
    static func milestones(of record: LabelRecord) -> [ExpiryMilestone] {
        switch record.kind {
        case .generic, .dairy:
            return [
                ExpiryMilestone(date: record.expireAt,
                                tomorrowTitle: "明天到原始保质期",
                                tomorrowBody: "明天到原始保质期，之后就别再用了。",
                                todayTitle: "今天到原始保质期",
                                todayBody: "今天到原始保质期。"),
                ExpiryMilestone(date: record.bestBefore,
                                tomorrowTitle: "明天到最佳使用时间",
                                tomorrowBody: "明天到最佳使用时间，记得处理。",
                                todayTitle: "今天到最佳使用时间",
                                todayBody: "今天到最佳使用时间。"),
            ]
        case .kombucha:
            return [
                // 康普茶的第二组数据是「完成时间」= 可以喝 / 可以做二发的时刻。
                ExpiryMilestone(date: record.expireAt,
                                tomorrowTitle: "康普茶明天完成",
                                tomorrowBody: "明天到完成时间，可以饮用或做二发了。",
                                todayTitle: "康普茶已完成",
                                todayBody: "今天到完成时间，可以饮用或做二发了。"),
                ExpiryMilestone(date: record.bestBefore,
                                tomorrowTitle: "明天到最佳使用时间",
                                tomorrowBody: "明天到最佳使用时间，记得处理。",
                                todayTitle: "今天到最佳使用时间",
                                todayBody: "今天到最佳使用时间。"),
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
            .removePendingNotificationRequests(withIdentifiers: Self.ids(for: record))
    }

    private func schedule(id: String, at date: Date, title: String, body: String) {
        let cal = AppCalendar.shared
        guard let fire = cal.date(bySettingHour: 9, minute: 0, second: 0, of: cal.startOfDay(for: date)),
              fire > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
            repeats: false
        )
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
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
