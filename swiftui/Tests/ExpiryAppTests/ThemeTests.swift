//
//  ThemeTests.swift
//  主题配色 + 主壳导航策略的回归测试。
//
//  为什么值得测：
//  ① 用户明确要求「整体 ui 颜色改成和苹果 App Store 一样的蓝色，全部都改颜色」。
//     这类「视觉常量」最容易被后续改动不小心改回绿色，而且**没有任何编译期保护**。
//     用色相（hue）把「必须是蓝的」钉死，比断言具体 RGB 更宽松、也更耐微调。
//  ② 「切 Tab 黑屏」的修复依赖一条不变量：**绝不重置当前可见的 Tab 的导航栈**。
//     把它抽成纯函数后就能被单测钉住，避免以后有人为了「省事」又改回同步重置。
//

import SwiftUI
import UIKit
import XCTest
@testable import ExpiryManager

final class ThemeTests: XCTestCase {

    /// 取色相（0~360°）。
    private func hue(_ color: Color) -> CGFloat {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return h * 360
    }

    private func saturation(_ color: Color) -> CGFloat {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return s
    }

    /// 蓝色区间取 195°~255°：覆盖 #007AFF(211°)、#5AAAFF(211°)、
    /// 靛蓝 #5E5CE6(241°)，又能把原来的墨绿 #00695C(**173°**) 挡在外面。
    private let blueRange: ClosedRange<CGFloat> = 195...255

    func testBrandColorIsAppStoreBlue() {
        let h = hue(Theme.brand)
        XCTAssertTrue(blueRange.contains(h),
                      "品牌主色必须是蓝色 —— 当前色相 \(h)°；"
                      + "原来的墨绿 #00695C 是 173°，落在这个区间之外")
        XCTAssertGreaterThan(saturation(Theme.brand), 0.9,
                             "品牌色饱和度太低，看着会发灰")

        // 与 #007AFF 的容差比对（允许 ±2/255 的取整误差）
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Theme.brand).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0x00 / 255.0, accuracy: 0.01, "R 通道不是 0")
        XCTAssertEqual(g, 0x7A / 255.0, accuracy: 0.01, "G 通道不是 0x7A")
        XCTAssertEqual(b, 0xFF / 255.0, accuracy: 0.01, "B 通道不是 0xFF")
    }

    func testBrandLightIsBlue() {
        let h = hue(Theme.brandLight)
        XCTAssertTrue(blueRange.contains(h),
                      "品牌亮色必须是蓝色 —— 当前色相 \(h)°")
    }

    /// 三个模板卡片的标识色里，**不许再有绿色**。
    ///
    /// 注：奶制品保留琥珀色（暖色识别色，本来就不是绿色，而且三张卡片
    /// 需要互相区分），所以这里只断言前两个。
    func testTemplateTintsAreNotGreen() {
        XCTAssertTrue(blueRange.contains(hue(Theme.tplGenericTint)),
                      "通用效期标识色必须是蓝色 —— 当前 \(hue(Theme.tplGenericTint))°")
        XCTAssertTrue(blueRange.contains(hue(Theme.tplKombuchaTint)),
                      "康普茶标识色原来是品牌绿，必须改蓝 —— 当前 \(hue(Theme.tplKombuchaTint))°")
    }
}

final class NavigationPolicyTests: XCTestCase {

    /// 「切 Tab 后其它 Tab 要回一级菜单」= 重置**除当前之外**的全部。
    func testResetsEveryTabExceptCurrent() {
        for current in AppTab.allCases {
            let targets = RootNav.tabsToReset(current: current)
            XCTAssertFalse(targets.contains(current),
                           "绝不能重置当前可见的 Tab（\(current)）—— "
                           + "在切换动画期间动它的导航栈会直接黑屏")
            XCTAssertEqual(Set(targets), Set(AppTab.allCases).subtracting([current]),
                           "除当前之外的 Tab 必须全部被归位到一级菜单")
        }
    }
}
