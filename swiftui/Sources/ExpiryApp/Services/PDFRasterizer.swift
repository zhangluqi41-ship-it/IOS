//
//  PDFRasterizer.swift
//  把生成的标签 PDF 栅格化成位图 —— 预览页与「有没有画出东西」的自检都用它。
//
//  为什么不用 PDFKit 的 PDFView：
//  PDFView 的 `autoScales` 依赖自身 bounds 去算缩放。放进 SwiftUI 的
//  UIViewRepresentable 时，`makeUIView` 里视图还没有尺寸（bounds 为 0），
//  此时算出的 scaleFactor 是错的，结果就是**整页空白**。
//  自己栅格化没有这个时序问题，而且能顺手统计墨迹，判断是不是真的画出来了。
//

import CoreGraphics
import UIKit

enum PDFRasterizer {

    /// 把 PDF 首页栅格化为白底位图。
    /// - Parameter maxPixel: 长边像素上限，避免超大页面吃内存。
    static func firstPageImage(from data: Data, maxPixel: CGFloat = 1400) -> UIImage? {
        guard !data.isEmpty,
              let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }

        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }

        let scale = min(maxPixel / box.width, maxPixel / box.height)
        let pixelW = max((box.width * scale).rounded(), 1)
        let pixelH = max((box.height * scale).rounded(), 1)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelW, height: pixelH),
                                               format: format)
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor.white.cgColor)
            c.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
            c.interpolationQuality = .high
            // UIGraphicsImageRenderer 的上下文是 y 向下，而 drawPDFPage 要 y 向上，
            // 所以先翻转成 PDF 原生坐标再画，否则整页会上下颠倒。
            c.translateBy(x: 0, y: pixelH)
            c.scaleBy(x: scale, y: -scale)
            c.translateBy(x: -box.origin.x, y: -box.origin.y)
            c.drawPDFPage(page)
        }
    }

    // MARK: - 墨迹统计

    /// 统计位图里「非白像素」的比例（0~1）。用来判断画面是不是空的。
    static func inkRatio(of image: UIImage, threshold: UInt8 = 200) -> Double {
        guard let s = graySamples(of: image) else { return 0 }
        let dark = s.pixels.reduce(0) { $0 + ($1 < threshold ? 1 : 0) }
        return Double(dark) / Double(max(s.pixels.count, 1))
    }

    /// 统计指定区域内的墨迹比例。
    /// - Parameter rect: 归一化坐标（0~1），原点在**左上**，与看图的直觉一致。
    ///   单元测试靠它来断言「标题在顶部而不是底部」这类方位问题。
    static func inkRatio(of image: UIImage, in rect: CGRect, threshold: UInt8 = 200) -> Double {
        guard let s = graySamples(of: image) else { return 0 }

        let x0 = clamp(Int((rect.minX * CGFloat(s.width)).rounded(.down)), 0, s.width)
        let x1 = clamp(Int((rect.maxX * CGFloat(s.width)).rounded(.up)), 0, s.width)
        let y0 = clamp(Int((rect.minY * CGFloat(s.height)).rounded(.down)), 0, s.height)
        let y1 = clamp(Int((rect.maxY * CGFloat(s.height)).rounded(.up)), 0, s.height)
        guard x1 > x0, y1 > y0 else { return 0 }

        var dark = 0
        var total = 0
        for y in y0..<y1 {
            let row = y * s.width
            for x in x0..<x1 {
                total += 1
                if s.pixels[row + x] < threshold { dark += 1 }
            }
        }
        return total == 0 ? 0 : Double(dark) / Double(total)
    }

    /// 把位图打成 ASCII 墨迹图，用于单元测试与排障时肉眼确认版式。
    /// - Returns: 每行一个字符串（`#` 有墨、`.` 空白），第一行对应画面顶部。
    static func asciiArt(of image: UIImage, columns: Int = 64, rows: Int = 24) -> [String] {
        guard let cg = image.cgImage,
              let s = graySamples(of: cg, width: columns, height: rows) else { return [] }
        return (0..<rows).map { r in
            (0..<columns).map { c in
                s.pixels[r * columns + c] < 200 ? "#" : "."
            }.joined()
        }
    }

    // MARK: - 私有

    private struct Samples {
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        min(max(v, lo), hi)
    }

    /// 采样成一张灰度小图（默认宽 160），统计开销可忽略。
    private static func graySamples(of image: UIImage, width: Int = 160) -> Samples? {
        guard let cg = image.cgImage else { return nil }
        let ratio = image.size.height / max(image.size.width, 1)
        let height = max(Int((CGFloat(width) * ratio).rounded()), 1)
        return graySamples(of: cg, width: width, height: height)
    }

    private static func graySamples(of cg: CGImage, width: Int, height: Int) -> Samples? {
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: &pixels,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: width,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Samples(pixels: pixels, width: width, height: height)
    }
}
