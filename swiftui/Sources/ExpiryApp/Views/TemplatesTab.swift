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
enum TemplateRoute: Hashable {
    case generic
    case kombucha
    case dairy
    case meat
}

struct TemplatesTab: View {
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        TemplateCard(
                            title: "通用效期",
                            subtitle: "自定标题与两个日期",
                            systemImage: "clock",
                            tint: Theme.tplGenericTint,
                            fill: Theme.tplGenericFill,
                            route: .generic
                        )
                        TemplateCard(
                            title: "康普茶",
                            subtitle: "自动算一发二发日期",
                            systemImage: "drop.fill",
                            tint: Theme.tplKombuchaTint,
                            fill: Theme.tplKombuchaFill,
                            route: .kombucha
                        )
                        TemplateCard(
                            title: "奶制品",
                            subtitle: "按品类套保质期",
                            systemImage: "flask.fill",
                            tint: Theme.tplDairyTint,
                            fill: Theme.tplDairyFill,
                            route: .dairy
                        )
                        // ★ 2026-10-09 新增（用户清单「一、模板二级菜单」第 4 条）：
                        //   肉类模板「菜单和奶制品一样」，所以直接作为第 4 张卡片。
                        //   ⚠️「解冻」**不是**卡片 —— 它只能由扫冷冻标签的二维码进入，
                        //   见 `MeatThawView`。
                        TemplateCard(
                            title: "肉类",
                            subtitle: "冷藏 / 冷冻自动算",
                            systemImage: "fork.knife",
                            tint: Theme.tplMeatTint,
                            fill: Theme.tplMeatFill,
                            route: .meat
                        )
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

/// 模板卡片（磁贴）。
///
/// ★★★ 2026-10-18（用户第 2 条）：「把它们换成**苹果官方类似磁贴样式**，
///   和上面这个苹果健身 App 内的一样的官方工具制作」
///   ➜ 参照「健康」App 摘要页的卡片结构重做：
///     · 左上 **图标**、右上 **圆形 chevron**（"可进入"的提示，健康 App 同款）；
///     · 内容**左对齐**（原来居中），标题在上、副标题在下；
///     · 底色用 **`.regularMaterial`**（系统材质，浅色白雾 / 深色深雾，随外观自动切换）
///       —— 不再用 `secondarySystemGroupedBackground` 那种"列表分组底色"，
///         磁贴要有明显的"悬浮块"层次；
///     · 圆角放大到 20（健康 App 磁贴的观感）。
///   ⚠️ 这是**卡片/链接**（`NavigationLink`），不是按钮 —— 按钮仍守「只能第一方玻璃」的规矩。
struct TemplateCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let fill: Color
    let route: TemplateRoute

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 46, height: 46)
                        .background(fill, in: RoundedRectangle(cornerRadius: 12))
                    Spacer(minLength: 8)
                    // 健康 App 磁贴右上角那颗"可进入"的小圆箭头。
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }

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
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TemplatesTab(path: .constant(NavigationPath()))
}
