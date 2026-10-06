//
//  LiquidGlass.swift
//  效期管理系统 —— iOS 26 Liquid Glass 按钮样式封装
//
//  规格要求最低系统 iOS 26.0，因此直接使用系统原厂 Liquid Glass API，
//  不需要任何版本回落分支（有回落分支反而会让老系统的仿制实现混进来）。
//
//  设计红线（规格 6.1）：Liquid Glass 只属于导航层与浮层，
//  绝不用于列表 / 正文 / 卡片式内容区块。故本文件只封装按钮样式，
//  内容卡片一律使用系统语义背景色。
//

import SwiftUI

extension View {
    /// 主操作按钮：iOS 26 原厂液态玻璃（prominent 变体）。
    func liquidGlassProminentButton() -> some View {
        buttonStyle(.glassProminent)
    }

    /// 次操作按钮：iOS 26 原厂液态玻璃。
    func liquidGlassButton() -> some View {
        buttonStyle(.glass)
    }
}
