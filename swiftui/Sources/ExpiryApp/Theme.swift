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
    /// 品牌主色 —— **App Store 蓝**（就是 iOS 系统蓝 #007AFF）。
    ///
    /// ★ 用户反馈「整体 ui 颜色目前是绿色，改成和苹果 App Store 一样的蓝色，
    ///   全部都改颜色」。这里是全局唯一的品牌色入口：
    ///   Tab 栏选中色、按钮、图标高亮、快捷档位 chip、扫码取景框……
    ///   全部走 `Theme.brand` / `Theme.brandLight`，由 `RootView` 的
    ///   `.tint(Theme.brand)` 统一下发，所以改这两行就是全量改色。
    ///
    ///   原来用的是安卓端主色 #00695C（墨绿），是一致的，但用户现在要求改蓝。
    static let brand = Color(red: 0x00 / 255.0, green: 0x7A / 255.0, blue: 0xFF / 255.0)

    /// 品牌亮色（深色底上的强调色：扫描取景框四角、扫描线）。
    static let brandLight = Color(red: 0x5A / 255.0, green: 0xAA / 255.0, blue: 0xFF / 255.0)

    // ---- 模板卡片专属标识色 ----
    /// 通用效期 = 蓝（跟随品牌色，保持卡片之间的区分度）
    static let tplGenericTint = Color(red: 0x0A / 255.0, green: 0x7A / 255.0, blue: 0xFF / 255.0)
    static let tplGenericFill = Color(red: 0xE6 / 255.0, green: 0xF1 / 255.0, blue: 0xFF / 255.0)
    /// 康普茶 = 靛蓝（原来是品牌绿，随本轮改色一起去绿）
    static let tplKombuchaTint = Color(red: 0x5E / 255.0, green: 0x5C / 255.0, blue: 0xE6 / 255.0)
    static let tplKombuchaFill = Color(red: 0xED / 255.0, green: 0xEC / 255.0, blue: 0xFF / 255.0)
    /// 奶制品 = 琥珀（★ 这一项**保留**：它是暖色识别色、本来就不是绿色，
    ///   三张卡片需要互相区分。如果也要统一成蓝色，改这两行即可。）
    static let tplDairyTint = Color(red: 0x85 / 255.0, green: 0x4F / 255.0, blue: 0x0B / 255.0)
    static let tplDairyFill = Color(red: 0xFA / 255.0, green: 0xEE / 255.0, blue: 0xDA / 255.0)
    /// 肉类 = 玫红（★ 2026-10-09 新增，第 4 张卡片）。
    ///   选玫红是因为其余三张已经占了蓝 / 靛蓝 / 琥珀 —— 再上一个暖色系的红，
    ///   既能一眼和奶制品的琥珀分开，又符合「肉类」的直觉。
    static let tplMeatTint = Color(red: 0xC1 / 255.0, green: 0x33 / 255.0, blue: 0x54 / 255.0)
    static let tplMeatFill = Color(red: 0xFD / 255.0, green: 0xE8 / 255.0, blue: 0xEC / 255.0)

    /// 卡片圆角（squircle 近似）。
    static let cardRadius: CGFloat = 16
    /// 按钮圆角。
    static let buttonRadius: CGFloat = 12
}
