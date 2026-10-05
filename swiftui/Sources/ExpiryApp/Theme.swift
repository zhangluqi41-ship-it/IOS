//
//  Theme.swift
//  效期管理系统 —— iOS 26 Liquid Glass 设计基座
//
//  SwiftUI 已内置语义字体（.largeTitle / .body / .footnote 等）与语义色
//  （.primary / .secondary / Color.accentColor），本文件只放品牌专属常量，
//  其余一律用系统语义，保证自动跟随 iOS 26 液态玻璃与深色模式。
//

import SwiftUI

enum Theme {
    /// 品牌主色 —— 沿用安卓端主色 #00695C，两端观感一致。
    static let brand = Color(red: 0x00 / 255.0, green: 0x69 / 255.0, blue: 0x5C / 255.0)

    /// 品牌亮色（图标高亮、强调态）。
    static let brandLight = Color(red: 0x4D / 255.0, green: 0xB6 / 255.0, blue: 0xAC / 255.0)

    // ---- 模板卡片专属标识色（与 Flutter 版一致）----
    /// 通用效期 = 蓝
    static let tplGenericTint = Color(red: 0x18 / 255.0, green: 0x5F / 255.0, blue: 0xA5 / 255.0)
    static let tplGenericFill = Color(red: 0xE6 / 255.0, green: 0xF1 / 255.0, blue: 0xFB / 255.0)
    /// 康普茶 = 品牌绿
    static let tplKombuchaTint = Color(red: 0x0F / 255.0, green: 0x6E / 255.0, blue: 0x56 / 255.0)
    static let tplKombuchaFill = Color(red: 0xE1 / 255.0, green: 0xF5 / 255.0, blue: 0xEE / 255.0)
    /// 奶制品 = 琥珀
    static let tplDairyTint = Color(red: 0x85 / 255.0, green: 0x4F / 255.0, blue: 0x0B / 255.0)
    static let tplDairyFill = Color(red: 0xFA / 255.0, green: 0xEE / 255.0, blue: 0xDA / 255.0)

    /// 卡片圆角（squircle 近似）。
    static let cardRadius: CGFloat = 16
    /// 按钮圆角。
    static let buttonRadius: CGFloat = 12
}
