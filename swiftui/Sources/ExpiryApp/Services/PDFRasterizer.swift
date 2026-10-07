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

    /// ★ 全分辨率统计：归一化区域内「接近纯白」的像素比例。
    ///
    /// 为什么不能用 `inkRatio` 代替：`inkRatio` 是**降采样**后按阈值 200 数深色像素，
    /// 而黑条本身已经全黑 —— 里面有没有白字，统计结果都一样是「深色」，
    /// 于是「竖排白字根本没画出来」这种 bug 它永远发现不了（实测踩过）。
    /// 这个方法不降采样、只数亮像素，才能真的验证黑底上的白字存在。
    ///
    /// - Parameter rect: 归一化坐标（0~1），原点在**左上**。
    static func brightRatio(of image: UIImage, in rect: CGRect, above: UInt8 = 220) -> Double {
        guard let cg = image.cgImage,
              let buf = GrayBuffer(cgImage: cg, whiteBackground: false) else { return 0 }

        let x0 = clamp(Int((rect.minX * CGFloat(buf.width)).rounded(.down)), 0, buf.width)
        let x1 = clamp(Int((rect.maxX * CGFloat(buf.width)).rounded(.up)), 0, buf.width)
        let y0 = clamp(Int((rect.minY * CGFloat(buf.height)).rounded(.down)), 0, buf.height)
        let y1 = clamp(Int((rect.maxY * CGFloat(buf.height)).rounded(.up)), 0, buf.height)
        guard x1 > x0, y1 > y0 else { return 0 }

        var bright = 0
        var total = 0
        for y in y0..<y1 {
            let row = y * buf.width
            for x in x0..<x1 {
                total += 1
                if buf.pixels[row + x] > above { bright += 1 }
            }
        }
        return total == 0 ? 0 : Double(bright) / Double(total)
    }

    /// ★★ 全分辨率**墨迹**比例（不降采样）。
    ///
    /// ⚠️ 窄带判「有没有东西」必须用这个，**不要用 `inkRatio`**。
    ///
    /// `inkRatio` 会把整页降采样成 **160 像素宽**再数深色像素 ——
    /// 50mm 的标签上 **1 个采样像素 = 0.3125mm**，于是：
    ///   · 任何窄于 ~0.6mm 的窗口只有一两列，边界完全被栅格吞掉；
    ///   · 窗口边界压在黑条边缘上时，那一列会**把黑条本身算进来**。
    /// 实测踩过一次：一条 0.3mm 宽的「右黑条左侧应该是干净的」检测带，
    /// 量出 45% 墨迹（= 10/22，全是右黑条漏进来的），白红了两轮 CI ——
    /// 被测的内容其实老老实实待在 44.9mm 以内。
    ///
    /// - Parameter rect: 归一化坐标（0~1），原点在**左上**。
    static func darkRatio(of image: UIImage, in rect: CGRect, below: UInt8 = 200) -> Double {
        guard let cg = image.cgImage,
              let buf = GrayBuffer(cgImage: cg, whiteBackground: false) else { return 0 }

        let x0 = clamp(Int((rect.minX * CGFloat(buf.width)).rounded(.down)), 0, buf.width)
        let x1 = clamp(Int((rect.maxX * CGFloat(buf.width)).rounded(.up)), 0, buf.width)
        let y0 = clamp(Int((rect.minY * CGFloat(buf.height)).rounded(.down)), 0, buf.height)
        let y1 = clamp(Int((rect.maxY * CGFloat(buf.height)).rounded(.up)), 0, buf.height)
        guard x1 > x0, y1 > y0 else { return 0 }

        var dark = 0
        var total = 0
        for y in y0..<y1 {
            let row = y * buf.width
            for x in x0..<x1 {
                total += 1
                if buf.pixels[row + x] < below { dark += 1 }
            }
        }
        return total == 0 ? 0 : Double(dark) / Double(total)
    }

    /// 归一化区域内**最右侧**深色像素的归一化 x（原点左上）；区域内没有深色返回 nil。
    ///
    /// 用来断言「内容没有越过某条线」—— 比在固定窗口里数比例可靠得多：
    /// 比例只能回答「这块区域里有没有东西」，回答不了「东西停在哪」。
    /// 全分辨率，不降采样（原因见 `darkRatio`）。
    static func rightmostDarkX(of image: UIImage, in rect: CGRect,
                               below: UInt8 = 200) -> CGFloat? {
        guard let cg = image.cgImage,
              let buf = GrayBuffer(cgImage: cg, whiteBackground: false) else { return nil }

        let x0 = clamp(Int((rect.minX * CGFloat(buf.width)).rounded(.down)), 0, buf.width)
        let x1 = clamp(Int((rect.maxX * CGFloat(buf.width)).rounded(.up)), 0, buf.width)
        let y0 = clamp(Int((rect.minY * CGFloat(buf.height)).rounded(.down)), 0, buf.height)
        let y1 = clamp(Int((rect.maxY * CGFloat(buf.height)).rounded(.up)), 0, buf.height)
        guard x1 > x0, y1 > y0 else { return nil }

        var found: Int? = nil
        for y in y0..<y1 {
            let row = y * buf.width
            for x in x0..<x1 where buf.pixels[row + x] < below {
                if found == nil || x > found! { found = x }
            }
        }
        guard let fx = found else { return nil }
        return CGFloat(fx + 1) / CGFloat(buf.width)
    }

    /// 归一化区域内的**最大灰度值**（0~255）。
    /// 和 `brightRatio` 配合用来分辨两种失败：
    ///   · maxLuma ≈ 0   → 那儿根本什么都没有（字没画出来 / 画到别处去了）
    ///   · maxLuma = 255 → 有白字，只是比例低（多半是抗锯齿/字号问题）
    static func maxLuma(of image: UIImage, in rect: CGRect) -> UInt8 {
        guard let cg = image.cgImage,
              let buf = GrayBuffer(cgImage: cg, whiteBackground: false) else { return 0 }
        let x0 = clamp(Int((rect.minX * CGFloat(buf.width)).rounded(.down)), 0, buf.width)
        let x1 = clamp(Int((rect.maxX * CGFloat(buf.width)).rounded(.up)), 0, buf.width)
        let y0 = clamp(Int((rect.minY * CGFloat(buf.height)).rounded(.down)), 0, buf.height)
        let y1 = clamp(Int((rect.maxY * CGFloat(buf.height)).rounded(.up)), 0, buf.height)
        guard x1 > x0, y1 > y0 else { return 0 }
        var best: UInt8 = 0
        for y in y0..<y1 {
            let row = y * buf.width
            for x in x0..<x1 { best = max(best, buf.pixels[row + x]) }
        }
        return best
    }

    /// 指定区域的 ASCII 墨迹图（归一化 rect，原点左上）。排障用。
    /// 黑底白字会显示成 `#` 里的 `.`，一眼能看出字有没有画出来、画在哪儿。
    static func asciiArt(of image: UIImage, in rect: CGRect,
                         columns: Int = 40, rows: Int = 30) -> [String] {
        guard let cg = image.cgImage else { return [] }
        let px = Int((rect.minX * CGFloat(cg.width)).rounded(.down))
        let py = Int((rect.minY * CGFloat(cg.height)).rounded(.down))
        let pw = Int((rect.width * CGFloat(cg.width)).rounded(.up))
        let ph = Int((rect.height * CGFloat(cg.height)).rounded(.up))
        let x = max(px, 0)
        let y = max(py, 0)
        let w = min(pw, cg.width - x)
        let h = min(ph, cg.height - y)
        guard w >= 1, h >= 1,
              let crop = cg.cropping(to: CGRect(x: x, y: y, width: w, height: h)),
              let s = graySamples(of: crop, width: columns, height: rows) else { return [] }
        return (0..<rows).map { r in
            (0..<columns).map { c in
                s.pixels[r * columns + c] < 200 ? "#" : "."
            }.joined()
        }
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

// MARK: - 全分辨率灰度位图

/// 一张 CGImage 的**全分辨率**灰度像素。
///
/// 与 `PDFRasterizer` 内部那个降采样到 160px 的快速统计不同，这里一个像素都不丢，
/// 用来做「某个位置到底是黑是白」这种精确判断 —— 比如读取二维码的模块矩阵。
struct GrayBuffer {
    let pixels: [UInt8]
    let width: Int
    let height: Int

    /// - Parameter whiteBackground: 为 true 时先把缓冲区铺成白色再合成，
    ///   这样源图里的**透明**区域会变成白色而不是黑色。
    ///   二维码就是这么用的：CIQRCodeGenerator 的输出有时带透明背景，
    ///   铺黑底会让整张图变成一块黑，极性判断跟着一起错。
    init?(cgImage: CGImage, whiteBackground: Bool = true) {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }

        var buffer = [UInt8](repeating: whiteBackground ? 255 : 0, count: w * h)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base,
                                      width: w,
                                      height: h,
                                      bitsPerComponent: 8,
                                      bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            // 1:1 读取，绝不能插值 —— 否则模块边缘被平滑，极性判定就会在
            // 阈值附近摇摆。
            ctx.interpolationQuality = .none
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        pixels = buffer
        width = w
        height = h
    }

    /// 越界返回白色，省得调用处到处判边界。
    func value(x: Int, y: Int) -> UInt8 {
        guard x >= 0, x < width, y >= 0, y < height else { return 255 }
        return pixels[y * width + x]
    }

    /// 去掉四周「整行/整列颜色均匀」的边，返回剩下的矩形。
    ///
    /// 二维码用它来剥掉静默边：QR 符号最外一圈永远含定位图案或分隔符，
    /// 不可能是均匀的，所以只会削掉真正的静默边。
    func uniformBorderTrimmed(tolerance: Int = 8) -> (minX: Int, minY: Int, width: Int, height: Int) {
        func rowVaries(_ y: Int) -> Bool {
            var lo: UInt8 = 255
            var hi: UInt8 = 0
            for x in 0..<width {
                let v = pixels[y * width + x]
                lo = min(lo, v)
                hi = max(hi, v)
            }
            return Int(hi) - Int(lo) > tolerance
        }
        func colVaries(_ x: Int) -> Bool {
            var lo: UInt8 = 255
            var hi: UInt8 = 0
            for y in 0..<height {
                let v = pixels[y * width + x]
                lo = min(lo, v)
                hi = max(hi, v)
            }
            return Int(hi) - Int(lo) > tolerance
        }

        var minX = 0
        var maxX = width - 1
        var minY = 0
        var maxY = height - 1
        while minY < maxY && !rowVaries(minY) { minY += 1 }
        while maxY > minY && !rowVaries(maxY) { maxY -= 1 }
        while minX < maxX && !colVaries(minX) { minX += 1 }
        while maxX > minX && !colVaries(maxX) { maxX -= 1 }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }
}
