//
//  FontProvider.swift
//  字体加载 —— 与 Flutter 版一致用开源思源黑体（Noto Sans SC，OFL）。
//  字体文件放在 Resources/ 并通过 Info.plist 的 UIAppFonts 注册；
//  找不到时回落到系统字体（PingFang SC），保证中文一定可渲染。
//

import UIKit

enum FontProvider {
    /// 常规字重。
    static func regular(_ size: CGFloat) -> UIFont {
        UIFont(name: "NotoSansSC-Regular", size: size)
            ?? UIFont(name: "NotoSansCJKsc-Regular", size: size)
            ?? .systemFont(ofSize: size)
    }

    /// 粗体字重（标题、行值、制作人、黑条内文字）。
    static func bold(_ size: CGFloat) -> UIFont {
        UIFont(name: "NotoSansSC-Bold", size: size)
            ?? UIFont(name: "NotoSansCJKsc-Bold", size: size)
            ?? .boldSystemFont(ofSize: size)
    }
}
