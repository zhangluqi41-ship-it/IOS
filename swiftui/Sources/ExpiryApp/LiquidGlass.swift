//
//  LiquidGlass.swift
//  效期管理系统 —— 液态玻璃修饰符（含老系统回落）
//
//  iOS 26 起用系统原厂 Liquid Glass（.glassEffect() / .buttonStyle(.glass)）。
//  为把最低系统降到 iOS 17（覆盖更多设备、兼容爱思等第三方签名工具），
//  老系统回落到语义等价的系统材质/按钮样式，iOS 26+ 观感不变。
//

import SwiftUI

extension View {
    /// 玻璃卡片背景：iOS 26+ 液态玻璃，老系统回落系统毛玻璃材质。
    @ViewBuilder
    func liquidGlassCard() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect()
        } else {
            background(.ultraThinMaterial)
        }
    }

    /// 玻璃主按钮：iOS 26+ 液态玻璃，老系统回落填充主按钮。
    @ViewBuilder
    func liquidGlassProminentButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// 玻璃次按钮：iOS 26+ 液态玻璃，老系统回落描边按钮。
    @ViewBuilder
    func liquidGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}
