//
//  PrimaryActionBar.swift
//  主操作条 —— 底部悬浮的液态玻璃主按钮。
//
//  为什么不做成 List 的一个 Section：
//  `.glassProminent` 这类玻璃按钮放在列表行里，会叠出「行背景 + 玻璃底」
//  两层背景，观感发灰、边界糊；而液态玻璃在 iOS 26 里本就属于**浮层**语义。
//  放到 `safeAreaInset(edge: .bottom)` 里，既拿到系统滚动边缘效果，
//  又是苹果自家的标准做法（浮起的操作条）。
//

import SwiftUI

struct PrimaryActionBar: View {
    let title: String
    var busyTitle: String = "处理中…"
    var hint: String? = nil
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: action) {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isBusy ? busyTitle : title)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 4)
            }
            .liquidGlassProminentButton()
            .tint(Theme.brand)
            .disabled(isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

#Preview {
    VStack {
        Spacer()
        PrimaryActionBar(
            title: "生成标签",
            busyTitle: "生成中…",
            hint: "标签规格 50 × 30 mm",
            isBusy: false,
            action: {}
        )
    }
    .background(Color(.systemGroupedBackground))
}
