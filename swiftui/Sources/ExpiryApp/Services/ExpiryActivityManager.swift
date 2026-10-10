//
//  ExpiryActivityManager.swift
//  灵动岛（Live Activity）的起 / 更 / 收 —— **只属于主 App 目标**。
//
//  ★★ 为什么逻辑长这样（平台硬限制，别试图「优化」）：
//    Live Activity **只能由处于前台的 App 调 `Activity.request()` 启动**。
//    · 本地通知拉不起它（iOS 没有这个能力）；
//    · 后台 / 被杀时只能靠服务端 APNs **push-to-start**（iOS 17.2+），
//      而免费开发者账号根本没有推送能力。
//    所以现实可行的做法只有一条：
//      「用户最后一次打开 App 时，把**最近的、8 小时内会到期**的那个里程碑
//        先挂到灵动岛上」，让它带着系统自己走的倒计时在那里待着。
//    用户打开一次 App → 灵动岛就出现在那个里程碑前最多 8 小时。
//
//  ★ 为什么窗口取 8 小时：免费账号只能用 `pushType: nil`（纯本地更新）起活动，
//    这种活动**最长活 8 小时**，再长系统也会收掉。取 8 小时正好用满。
//
//  ★ 倒计时不需要我们管：`Text(timerInterval:countsDown:)` 由系统每秒自己刷，
//    不需要 App 在后台推状态 —— 这正是本地模式下唯一能做出「像快递一样」
//    倒计时的原因。
//
//  ★ 两个按钮的行为不依赖 `ContentState.phase`：
//    `ExpiryMarkDoneIntent` / `ExpirySnoozeIntent` 是 `LiveActivityIntent`，
//    由**主 App 进程**执行，它们在那个时刻用 `Date()` 现判
//    （见 `ExpiryActivityBridge`）—— 所以哪怕活动是几小时前挂的、`phase`
//    已经不准，功能仍然是对的。
//

import ActivityKit
import Foundation

@MainActor
final class ExpiryActivityManager {

    static let shared = ExpiryActivityManager()

    /// 提前多久就把灵动岛挂上去（见文件头）。
    static let window: TimeInterval = 8 * 60 * 60

    /// 「已经到点」之后还允许挂多久。
    ///
    /// ★★ 为什么需要这段宽限：如果只保留 `delta > 0`（还没到点），
    ///    `dueAt` 一到活动就会被下一次 `sync` 收掉 —— 用户根本没机会点
    ///    「已完成使用 / 稍后提醒」。给 30 分钟，让他有充裕时间处理；
    ///    这段时间岛上显示「已到时间 + 两个按钮」。
    static let graceWindow: TimeInterval = 30 * 60

    private var activity: Activity<ExpiryActivityAttributes>?
    /// 当前这条活动对应的「记录 + 里程碑」。
    private var currentKey: String?

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
        var best: (record: LabelRecord, milestone: ExpiryStore.ExpiryMilestone)?

        for record in records where record.usedAt == nil {
            for milestone in ExpiryStore.milestones(of: record) {
                let delta = milestone.date.timeIntervalSince(now)
                // ★ 窗口扩到 `window + graceWindow`（8h + 30min）：
                //   刚过点半小时内的物料仍然要留在岛上（否则「到时间」那一刻
                //   活动就自己消失了，用户根本来不及点按钮）。这段时间
                //   `ContentState.phase` 是 `.due`，岛上显示「已到时间 + 两个按钮」。
                guard delta > -Self.graceWindow, delta <= Self.window else { continue }
                if best == nil || milestone.date < best!.milestone.date {
                    best = (record, milestone)
                }
            }
        }

        guard let best else {
            await endAll()
            return
        }

        let attrs = ExpiryActivityAttributes(
            recordID: best.record.id.uuidString,
            title: best.record.title,
            kindLabel: best.record.kind.label,
            milestoneLabel: best.milestone.label)

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
        // ★★ 2026-10-10（第七轮）：`staleDate` 从 `dueAt` **延后到宽限期结束**。
        //
        //   为什么改：`staleDate` 一到，系统会把整块内容**降饱和 / 变灰**
        //   （表示「这个数据可能过期了」）。但我们的场景里，`dueAt` 那一刻
        //   恰恰是**最需要用户看清**的时刻（红色「到点」+ 两个按钮）。
        //   若在 `dueAt` 就变灰，等于把最强的提示压暗了。
        //
        //   ➜ 改成 `dueAt + graceWindow`（30 分钟）：这期间内容保持满色，
        //     用户有充裕时间看清并处理；过了宽限期才让系统标记为陈旧，
        //     与 `sync` 里「超过宽限期就收掉活动」的窗口**对齐**。
        //   ⚠️ 单位是秒，`graceWindow` 是 `TimeInterval`，直接相加即可。
        let content = ActivityContent(state: state,
                                      staleDate: dueAt.addingTimeInterval(Self.graceWindow))

        // 还是同一个目标：只刷新一下状态
        //（比如刚打开 App、用户点过「稍后提醒」要把区间换新）。
        if currentKey == key, let activity {
            await activity.update(content)
            return
        }

        // 换目标了：先把旧的收干净，避免岛上同时挂两条。
        await endAll()

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

        // 手上没有活动（缓存丢了）→ 让调用方之后走正常的 sync 重建。
        guard let activity else {
            await endAll()
            return
        }
        let attrs = activity.attributes
        let state = ExpiryActivityAttributes.ContentState(startedAt: Date(), dueAt: dueAt)
        // ★ 同 `sync`：`staleDate` 延后到宽限期结束（别让刚设的 5 分钟倒计时就变灰）。
        let content = ActivityContent(state: state,
                                      staleDate: dueAt.addingTimeInterval(Self.graceWindow))

        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        currentKey = nil

        do {
            self.activity = try Activity.request(attributes: attrs,
                                                 content: content,
                                                 pushType: nil)
            currentKey = "\(recordID)#\(attrs.milestoneLabel)"
        } catch {
            NSLog("ExpiryActivityManager: 稍后提醒重起失败 \(error.localizedDescription)")
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
        guard let activity, currentKey?.hasPrefix(recordID) == true else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        currentKey = nil
    }

    /// 收掉本 App 的**全部**灵动岛。
    ///
    /// ★ 用系统的 `Activity.activities` 而不是只看自己手里那条：
    ///   App 重启后 `activity` 是 nil，但岛上可能还挂着上一次启动时留下的活动。
    func endAll() async {
        for item in Activity<ExpiryActivityAttributes>.activities {
            await item.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        currentKey = nil
    }
}
