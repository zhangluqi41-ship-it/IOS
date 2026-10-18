//
//  TemplatesTab.swift
//  模板 Tab —— 四个模板卡片（通用效期 / 康普茶 / 奶制品 / 肉类）+ 使用流程说明。
//
//  ★ 导航采用 value-based（`NavigationLink(value:)` + `navigationDestination(for:)`），
//    因为只有 value-based 跳转才会写进父级传入的 NavigationPath；
//    首页切走 Tab 时要靠清空这个 path 回到一级菜单，destination-based 的
//    NavigationLink 不会写 path，重置会失效。
//

import SwiftUI

/// 模板二级页路由。
enum TemplateRoute: Hashable, CaseIterable {
    case generic
    case kombucha
    case dairy
    case meat

    /// 持久化用的稳定 key（拖动排序要存进 UserDefaults）。
    var key: String {
        switch self {
        case .generic: return "generic"
        case .kombucha: return "kombucha"
        case .dairy: return "dairy"
        case .meat: return "meat"
        }
    }

    static func from(key: String) -> TemplateRoute? {
        allCases.first { $0.key == key }
    }

    var title: String {
        switch self {
        case .generic: return "通用效期"
        case .kombucha: return "康普茶"
        case .dairy: return "奶制品"
        case .meat: return "肉类"
        }
    }

    var subtitle: String {
        switch self {
        case .generic: return "自定标题与两个日期"
        case .kombucha: return "自动算一发二发日期"
        case .dairy: return "按品类套保质期"
        case .meat: return "冷藏 / 冷冻自动算"
        }
    }

    var systemImage: String {
        switch self {
        case .generic: return "clock"
        case .kombucha: return "drop.fill"
        case .dairy: return "flask.fill"
        case .meat: return "fork.knife"
        }
    }

    var tint: Color {
        switch self {
        case .generic: return Theme.tplGenericTint
        case .kombucha: return Theme.tplKombuchaTint
        case .dairy: return Theme.tplDairyTint
        case .meat: return Theme.tplMeatTint
        }
    }

    var fill: Color {
        switch self {
        case .generic: return Theme.tplGenericFill
        case .kombucha: return Theme.tplKombuchaFill
        case .dairy: return Theme.tplDairyFill
        case .meat: return Theme.tplMeatFill
        }
    }
}

struct TemplatesTab: View {
    @Binding var path: NavigationPath

    /// 磁贴顺序 —— 长按拖动排序后写进 `Prefs.templateOrder`，下次启动保持。
    @State private var order: [TemplateRoute] = TemplatesTab.loadOrder()

    /// 读保存的顺序；**补上缺失的路由**（新增模板 / 老版本没有这个键时不会丢卡片）。
    private static func loadOrder() -> [TemplateRoute] {
        let saved = Prefs.templateOrder.compactMap { TemplateRoute.from(key: $0) }
        let missing = TemplateRoute.allCases.filter { !saved.contains($0) }
        return saved + missing
    }

    /// 按路由生成一张磁贴（4 张卡片的元数据都收在 `TemplateRoute` 里了）。
    private func card(for route: TemplateRoute) -> some View {
        TemplateCard(title: route.title,
                     subtitle: route.subtitle,
                     systemImage: route.systemImage,
                     tint: route.tint,
                     fill: route.fill,
                     route: route)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    // ★★★ 2026-10-18（用户第 2 条）：
                    //   「你只是把他做成磁贴样式了，但是是否使用了苹果第一方功能呢？
                    //    **长按可以进行位置移动**，每个磁贴右上角那个箭头是什么意思呢？」
                    //   ➜ ① 磁贴支持**长按拖动排序** —— 用苹果第一方的拖放 API
                    //        `.draggable(_:preview:)` + `.dropDestination(for:)`，
                    //        顺序写进 `Prefs.templateOrder`，下次启动保持；
                    //     ② **右上角箭头已删除**（用户看不懂它的含义）。
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        ForEach(order, id: \.self) { route in
                            card(for: route)
                                .draggable(route.key) {
                                    card(for: route)
                                        .frame(width: 160)
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let key = items.first,
                                          let moving = TemplateRoute.from(key: key),
                                          let from = order.firstIndex(of: moving),
                                          let to = order.firstIndex(of: route),
                                          from != to else { return false }
                                    withAnimation(.snappy) {
                                        let item = order.remove(at: from)
                                        order.insert(item, at: to)
                                    }
                                    Prefs.templateOrder = order.map(\.key)
                                    return true
                                }
                        }
                    }

                    howItWorks
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("效期打印")
            .background(Color(.systemGroupedBackground))
            .navigationDestination(for: TemplateRoute.self) { route in
                switch route {
                case .generic:
                    GenericTemplateView()
                case .kombucha:
                    KombuchaTemplateView()
                case .dairy:
                    DairyTemplateView()
                case .meat:
                    MeatTemplateView()
                }
            }
        }
    }

    private var header: some View {
        Text("选择一个模板开始制作标签")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("使用流程")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                step(1, "选择模板", "按要标注的品类进入对应模板")
                Divider()
                step(2, "填写信息", "物料名称、操作人与日期")
                Divider()
                step(3, "打印标签", "底部「打印」一键出纸")
            }
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }

    private func step(_ n: Int, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(n)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Theme.brand)
                .frame(width: 24, height: 24)
                .background(Theme.brand.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
}

/// 模板磁贴。
///
/// ★★★ 2026-10-18 定版（用户确认「A. GroupBox（系统容器）」）：
///   磁贴容器改用**苹果系统自带的 `GroupBox`** ——
///   背景、圆角、内边距**全部由系统渲染**，这里只负责内容排版。
///   ❌ 不要再用 `.background(..., in: RoundedRectangle(...))` 自己画卡片外形
///     （那是"用系统色块拼一个卡片"，不是系统组件）。
///   ❌ 右上角的圆形箭头已按用户要求删除（他看不懂那是什么）。
///   ✅ 长按拖动排序：外层 `.draggable` / `.dropDestination`（见 `TemplatesTab`）。
struct TemplateCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let fill: Color
    let route: TemplateRoute

    var body: some View {
        GroupBox {
            NavigationLink(value: route) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 46, height: 46)
                        .background(fill, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 让整块内容区都能点（否则只有文字本身响应）。
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    TemplatesTab(path: .constant(NavigationPath()))
}
