//
//  TemplatesTab.swift
//  模板 Tab —— 三个模板卡片（通用效期 / 康普茶 / 奶制品）+ 使用流程说明。
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
                    }

                    howItWorks
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("效期管理系统")
            .background(Color(.systemGroupedBackground))
            .navigationDestination(for: TemplateRoute.self) { route in
                switch route {
                case .generic:
                    GenericTemplateView()
                case .kombucha:
                    KombuchaTemplateView()
                case .dairy:
                    DairyTemplateView()
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
                step(2, "填写信息", "标题与日期，日期可用快捷档位")
                Divider()
                step(3, "生成标签", "预览确认后打印、分享或存到手机")
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

/// 模板卡片：色块图标 + 标题 + 副标题，系统语义背景。
struct TemplateCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let fill: Color
    let route: TemplateRoute

    var body: some View {
        NavigationLink(value: route) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 52, height: 52)
                    .background(fill, in: RoundedRectangle(cornerRadius: 10))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 8)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TemplatesTab(path: .constant(NavigationPath()))
}
