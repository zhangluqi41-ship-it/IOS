//
//  FontProvider.swift
//  字体加载 —— 与 Flutter 版一致用开源思源黑体（Noto Sans SC，OFL）。
//  字体文件放在 Resources/ 并通过 Info.plist 的 UIAppFonts 注册；
//  找不到时回落到系统字体（PingFang SC），保证中文一定可渲染。
//
//  ★★ 光靠 Info.plist 的 `UIAppFonts` 是不够的，见 registerBundledFonts()。
//

import CoreText
import UIKit

enum FontProvider {
    /// `Bundle(for:)` 需要一个类，用这个空壳拿到「本模块」的 bundle。
    private final class BundleToken {}

    private static let lock = NSLock()
    private static var didRegister = false

    /// ★★ 显式注册包内字体（进程内幂等）。
    ///
    /// 只靠 Info.plist 的 `UIAppFonts` 有一个很隐蔽的**时序**问题：
    /// 系统是在 **App 启动流程里**完成字体注册的，而单元测试跑在 XCTest
    /// 宿主进程里、不保证已经走完那一步 —— 于是
    /// `UIFont(name: "NotoSansSC-Bold", size:)` 返回 nil，
    /// 这里就静默回落到系统字体（SF Pro + PingFang）。
    ///
    /// 后果不是「难看一点」，而是**版式结论全错**。同一串
    /// `"2026/10/07 18:40"` 在 2.7mm 下：
    ///   · 包内 NotoSansSC-Bold 的 advance = 8.406 em = **22.696 mm**
    ///   · CI 上回落后量到                        = **25.210 mm**（宽 11%，多吃 2.5mm）
    /// 而「文字 + 二维码放不放得下」的余量一共才 1.45mm —— 直接翻转结论。
    /// （实测：CI 报「剩余 −1.06mm」，按真字体算是「剩余 +1.45mm」。）
    ///
    /// 所以第一次取字体时主动注册一次，让**测试环境与真机一致**；
    /// 同时保留 `UIFont(name:)` 失败后的回落，中文永远有字体可用。
    /// 重复注册只会返回 already-registered 的错误码，可安全忽略。
    private static func registerBundledFonts() {
        lock.lock()
        defer { lock.unlock() }
        guard !didRegister else { return }
        didRegister = true

        var urls: [URL] = []
        for bundle in [Bundle.main, Bundle(for: BundleToken.self)] {
            urls += bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        }
        guard !urls.isEmpty else { return }
        // scope = .process：只对当前进程生效，不动系统字体表。
        _ = CTFontManagerRegisterFontsForURLs(urls as CFArray, .process, nil)
    }

    /// 常规字重。
    static func regular(_ size: CGFloat) -> UIFont {
        registerBundledFonts()
        return UIFont(name: "NotoSansSC-Regular", size: size)
            ?? UIFont(name: "NotoSansCJKsc-Regular", size: size)
            ?? .systemFont(ofSize: size)
    }

    /// 粗体字重（标题、行值、制作人、黑条内文字）。
    static func bold(_ size: CGFloat) -> UIFont {
        registerBundledFonts()
        return UIFont(name: "NotoSansSC-Bold", size: size)
            ?? UIFont(name: "NotoSansCJKsc-Bold", size: size)
            ?? .boldSystemFont(ofSize: size)
    }
}
