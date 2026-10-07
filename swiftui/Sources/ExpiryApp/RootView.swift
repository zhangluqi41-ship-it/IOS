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
///   重置导航栈必须**延后**到 Tab 切换动画之后（原因见下方 `onChange`），
///   而延后的闭包是在 `body` 里捕获的 —— SwiftUI 的 View 是**值类型**，
///   闭包里的 `self.selection` 会永远停在「创建那一刻」的值。
///   放进 class 里，闭包读到的就永远是**当前**值。
final class RootNav: ObservableObject {
    @Published var selection: AppTab = .templates

    /// 需要归位到一级菜单的 Tab = **除当前之外**的全部。
    ///
    /// ★ 单独抽成静态函数是为了能被单测钉住：**绝不重置当前可见的 Tab**
    ///   是这次「切 Tab 黑屏」修复的核心约束 —— 在切换动画期间（或之后
    ///   立刻）动当前 Tab 的导航栈，就会渲染成一片黑。
    static func tabsToReset(current: AppTab,
                            all: [AppTab] = AppTab.allCases) -> [AppTab] {
        all.filter { $0 != current }
    }
}

struct RootView: View {
    @StateObject private var nav = RootNav()

    @State private var templatesPath = NavigationPath()
    @State private var scanPath = NavigationPath()
    @State private var expiryPath = NavigationPath()
    @State private var printerPath = NavigationPath()

    @ObservedObject private var store = ExpiryStore.shared

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                resetInactiveTabs(current: nav.selection)
            }
        }
        .onAppear { resetInactiveTabs(current: nav.selection) }
    }

    /// 把所有**非当前** Tab 的导航栈归位到一级菜单。
    ///
    /// 幂等、可重复调用；只碰看不见的 Tab，所以不会造成可见的弹栈动画。
    private func resetInactiveTabs(current: AppTab) {
        if current != .templates, !templatesPath.isEmpty { templatesPath = NavigationPath() }
        if current != .scan, !scanPath.isEmpty { scanPath = NavigationPath() }
        if current != .expiry, !expiryPath.isEmpty { expiryPath = NavigationPath() }
        if current != .printer, !printerPath.isEmpty { printerPath = NavigationPath() }
    }
}

#Preview {
    RootView()
}
