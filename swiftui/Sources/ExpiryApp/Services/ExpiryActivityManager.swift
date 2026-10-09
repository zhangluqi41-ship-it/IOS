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

    private var activity: Activity<ExpiryActivityAttributes>?
    /// 当前这条活动对应的「记录 + 里程碑」。
    private var currentKey: String?

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
                // 只要「还没到、且 8 小时内」的；越近越优先。
                guard delta > 0, delta <= Self.window else { continue }
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

        let state = ExpiryActivityAttributes.ContentState(
            startedAt: now,
            dueAt: best.milestone.date,
            phase: .soon)

        let key = "\(best.record.id.uuidString)#\(best.milestone.label)"
        let content = ActivityContent(state: state, staleDate: best.milestone.date)

        // 还是同一个目标：只刷新一下状态（比如用户刚打开 App、phase 该重算了）。
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

    // MARK: - 结束

    /// 收掉某条记录对应的灵动岛（点了「已完成使用」时用）。
    func end(recordID: String) async {
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
