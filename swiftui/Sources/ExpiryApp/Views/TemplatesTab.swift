//
//  TemplatesTab.swift
//  模板 Tab —— 三个模板卡片（通用效期 / 康普茶 / 奶制品）+ 使用流程说明。
//

import SwiftUI

struct TemplatesTab: View {
    var body: some View {
        NavigationStack {
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
                            destination: AnyView(GenericTemplateView())
                        )
                        TemplateCard(
                            title: "康普茶",
                            subtitle: "自动算一发二发日期",
                            systemImage: "drop.fill",
                            tint: Theme.tplKombuchaTint,
                            fill: Theme.tplKombuchaFill,
                            destination: AnyView(KombuchaTemplateView())
                        )
                        TemplateCard(
                            title: "奶制品",
                            subtitle: "按品类套保质期",
                            systemImage: "flask.fill",
                            tint: Theme.tplDairyTint,
                            fill: Theme.tplDairyFill,
                            destination: AnyView(DairyTemplateView())
                        )
                    }

                    howItWorks
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("效期管理系统")
            .background(Color(.systemGroupedBackground))
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
            .liquidGlassCard()
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
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

/// 模板卡片：色块图标 + 标题 + 副标题，iOS 26 液态玻璃底。
struct TemplateCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let fill: Color
    let destination: AnyView

    var body: some View {
        NavigationLink {
            destination
        } label: {
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
    TemplatesTab()
}
