//
//  RootView.swift
//  主壳：四个一级页签（效期打印 / 扫码 / 效期管理 / 打印机）。
//
//  ★ 导航语义（用户明确要求）：
//    切走某个 Tab 后，它必须回到一级菜单 ——
//    否则「模板 → 二级页 → 切到打印机 → 切回模板」会停在二级页。
//    要做到这一点，四个 NavigationStack 必须用显式 path 绑定，
//    且页面跳转必须走 value-based（`navigationDestination(for:)`）——
//    只有 value-based 导航才会写进 NavigationPath，重置才生效。
//
//  ★★ 但**不能在切换动画中同步重置** —— 那会让切回来时是一片黑屏
//     （用户实测）。具体成因与修法见下方 `onChange` 里的长注释。
//

import SwiftUI

/// 四个一级页签。
enum AppTab: Hashable, CaseIterable {
    case templates
    case scan
    case expiry
    case printer
}

/// 主壳的导航状态。
///
/// ★ 为什么 `selection` 要放在**引用类型**里而不是 `@State`：
///   重置导航栈必须**延后**到 Tab 切换动画之后（原因见 `RootView.onChange`），
///   而延后的闭包是在 `body` 里捕获的 —— SwiftUI 的 View 是**值类型**，
///   闭包里的 `self.selection` 会永远停在「创建那一刻」的值。
///   放进 class 里，闭包读到的就永远是**当前**值。
final class RootNav: ObservableObject {
    @Published var selection: AppTab = .templates

    /// 已经离开过、但还没完成「归位到一级菜单」的 Tab。
    ///
    /// 为什么要登记而不是当场重置：切换动画期间动导航栈会黑屏（见 `onChange`）。
    /// 而「等动画结束再重置」又会漏掉一种情况 —— 用户切走之后**很快又切回来**，
    /// 那时目标 Tab 已经重新可见，就不能再动它了。登记下来，下一轮再清。
    private(set) var pendingReset: Set<AppTab> = []

    func noteLeft(_ tab: AppTab) {
        pendingReset.insert(tab)
    }

    /// 取走现在可以安全重置的 Tab（**当前不可见**的那些）。
    ///
    /// - Parameter force: 重试用尽时置 true —— 说明用户已经在别的 Tab 上待稳了，
    ///   此时即便它又变成当前 Tab 也要清掉（极罕见：切走又秒切回来）。
    ///   宁可有一次可见的「弹回一级」，也不要留下一个退不出去的黑屏。
    func takeResettable(force: Bool) -> [AppTab] {
        let ready = force ? pendingReset : pendingReset.subtracting([selection])
        pendingReset.subtract(ready)
        return ready.sorted { $0.order < $1.order }
    }

    var hasPending: Bool { !pendingReset.isEmpty }

    /// 需要归位到一级菜单的 Tab = **除当前之外**的全部。
    ///
    /// ★ 单独抽成静态函数是为了能被单测钉住：**绝不重置当前可见的 Tab**
    ///   是这次「切 Tab 黑屏」修复的核心约束。
    static func tabsToReset(current: AppTab,
                            all: [AppTab] = AppTab.allCases) -> [AppTab] {
        all.filter { $0 != current }
    }
}

extension AppTab {
    /// 稳定的先后顺序（只用于让 `Set` 转数组的结果确定，便于测试与日志）。
    var order: Int {
        switch self {
        case .templates: return 0
        case .scan: return 1
        case .expiry: return 2
        case .printer: return 3
        }
    }
}

struct RootView: View {
    @StateObject private var nav = RootNav()

    @State private var templatesPath = NavigationPath()
    @State private var scanPath = NavigationPath()
    @State private var expiryPath = NavigationPath()
    @State private var printerPath = NavigationPath()

    @ObservedObject private var store = ExpiryStore.shared
    /// ★★★【第十轮·用户图5】外部入口（通知 / 灵动岛卡片）→ App 页面的路由信箱。
    @ObservedObject private var router = AppRouter.shared

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $nav.selection) {
            Tab("效期打印", systemImage: "square.grid.2x2", value: AppTab.templates) {
                TemplatesTab(path: $templatesPath)
            }
            Tab("扫码", systemImage: "qrcode.viewfinder", value: AppTab.scan) {
                ScanView(path: $scanPath)
            }
            Tab("效期管理", systemImage: "calendar.badge.clock", value: AppTab.expiry) {
                ExpiryListView(path: $expiryPath)
            }
            .badge(store.alertingCount)
            Tab("打印机", systemImage: "printer", value: AppTab.printer) {
                PrinterMenuView(path: $printerPath)
            }
        }
        .onChange(of: nav.selection) { old, new in
            guard old != new else { return }
            // ★★ 不能在 onChange 里**同步**重置 path（会黑屏，用户实测）。
            //
            //   现象：在模板二级页（比如通用效期）打印完 → 切到别的 Tab →
            //   再切回「效期打印」，看到的是一片**黑屏**，必须再点一次
            //   「效期打印」才回到一级菜单。
            //
            //   原因：`onChange` 是在 TabView 的**切换动画过程中**触发的。
            //   此刻同步清空被切走那个 Tab 的 `NavigationPath`，SwiftUI 的
            //   模型层已经弹栈、但背后的 UIKit 导航控制器还停在没弹完的中间态，
            //   切回来时就渲染成一个空的（也就是黑的）容器。
            //   再点一次 Tab 会触发系统自带的「点已选中 Tab 弹回根」，
            //   正好把这个坏状态清掉 —— 跟用户描述完全一致。
            //
            //   修法：① 延后到切换动画结束之后再重置；
            //        ② 只重置**当前不可见**的那些 Tab —— 既天然满足
            //           「切走就回一级菜单」，又绝不会在用户眼前弹栈。
            nav.noteLeft(old)
            scheduleResetFlush()
        }
        .onAppear {
            // 冷启动时四个栈本来就是空的；这一句是防状态恢复后残留二级页。
            resetInactiveTabs(current: nav.selection)
            // ★ 蓝牙随 App 启动：预启 CoreBluetooth + 起常驻轮询 +
            //   蓝牙就绪后自动连上次那台打印机。
            //   放在 RootView（而不是「打印机」页）是因为自动连接要在
            //   用户还没进过打印机页时就生效。
            PrinterService.shared.startAppSession()
            // ★ 灵动岛对齐（冷启动时 `ExpiryStore.init` 还没有触发过重排）。
            syncLiveActivity()
        }
        .onChange(of: scenePhase) { _, phase in
            // ★★ 只有回到前台才可能启动 Live Activity —— 这是 ActivityKit 的硬限制
            //    （本地通知 / 后台都拉不起它，见 `ExpiryActivityManager` 顶部说明）。
            //    所以每次用户打开 App 都重算一次：把「8 小时内会到期」的那个
            //    里程碑挂到灵动岛上。
            guard phase == .active else { return }
            syncLiveActivity()
        }
        // ★★★【第十轮·用户图5】把外部 entry 送进来的「要去哪」落到实处。
        //
        //  来源有二：
        //    ① λ 锁定屏幕卡片 / 灵动岛卡片上的 `widgetURL(expirymanager://…)`
        //       → 系统以 URL 形式拉起 App → 走 `onOpenURL`；
        //    ② 用户点通知横幅本体（不是上面的按钮）
        //       → `NotificationPresenter.didReceive` 直接往 `AppRouter` 投递。
        //
        //  ⚠️ 必须**消费后清空**（`takeTab()` 内部会置 nil）——
        //     否则用户手动切走之后，任意一次重绘都会把他拽回效期管理。
        .onOpenURL { url in
            router.handle(url)
        }
        .onChange(of: router.pendingTab) { _, newValue in
            guard newValue != nil, let tab = router.takeTab() else { return }
            nav.selection = tab
        }
    }

    /// 让灵动岛对齐到最近那个里程碑。
    private func syncLiveActivity() {
        let records = store.records
        let enabled = store.reminderEnabled
        Task { await ExpiryActivityManager.shared.sync(records: records, enabled: enabled) }
    }

    /// 延后把所有已登记、且**当前不可见**的 Tab 归位到一级菜单。
    ///
    /// 幂等；只碰看不见的 Tab。若登记表里还有「又变回可见」的残留，
    /// 会在下一轮重试（最多 3 轮，然后强制清掉）。
    ///
    /// 延迟 0.35 秒 = Tab 切换转场动画的典型时长；到那时再动导航栈就不会黑屏。
    private func scheduleResetFlush(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let force = attempt >= 2
            for tab in nav.takeResettable(force: force) { clearPath(tab) }
            if nav.hasPending { scheduleResetFlush(attempt: attempt + 1) }
        }
    }

    private func clearPath(_ tab: AppTab) {
        switch tab {
        case .templates: if !templatesPath.isEmpty { templatesPath = NavigationPath() }
        case .scan: if !scanPath.isEmpty { scanPath = NavigationPath() }
        case .expiry: if !expiryPath.isEmpty { expiryPath = NavigationPath() }
        case .printer: if !printerPath.isEmpty { printerPath = NavigationPath() }
        }
    }

    /// 把所有**非当前** Tab 的导航栈归位到一级菜单（一次性做完，测试/兜底用）。
    private func resetInactiveTabs(current: AppTab) {
        for tab in RootNav.tabsToReset(current: current) { clearPath(tab) }
    }
}

#Preview {
    RootView()
}
