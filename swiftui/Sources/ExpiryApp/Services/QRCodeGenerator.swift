//
//  QRCodeGenerator.swift
//  二维码生成 —— CoreImage 的 CIQRCodeGenerator，M 级纠错。
//  对应 Flutter 的 `qr` 包（QrErrorCorrectLevel.M）。
//
//  ★ 性能：`CIContext` 构造一次很贵（要建 GPU 管线），复用同一个实例。
//
//  ★ 安全：二维码内容会被原样编码。内容来自用户输入，长度必须在上游
//    收紧（见 `LabelTemplate.maxTitleLength` 等），否则超长内容会让
//    CIQRCodeGenerator 直接返回 nil（二维码缺失）或撑大内存。
//
//  ★★ 为什么不像以前那样「CIColorInvert 之后直接交给 CGContext.draw」：
//    以前那条路有三个叠加的毛病，全都是实机上肉眼可见的：
//      1. **糊**：CoreImage 原生输出是「1 像素 = 1 模块」（二十来像素见方）。
//         把它当位图塞进 PDF，再放大到 600dpi 打印 / 或预览时放大十几倍，
//         就是一次剧烈的插值放大 → 模块边缘糊成一团。
//      2. **多一圈黑边**：原生输出自带的静默边被 CIColorInvert 一起反相，
//         于是二维码四周凭空多出一圈黑框，看起来脏乱。
//      3. **可能整个画反**：输出到底带不带静默边、明暗极性如何，不同系统
//         版本并不完全一致，靠「反相一次」是猜；猜错的表现就是整个二维码
//         变成一块黑底白点 —— 能看，但完全不是二维码该有的样子。
//    现在的做法：把原生输出**读成布尔模块矩阵**（用 QR 规范强制的定位图案
//    结构自动判定极性），再交给渲染器**逐块矢量绘制**。这样打印出来是纯
//    方块、任意 DPI 都锐利，静默边也完全由我们自己控制。
//

import CoreGraphics
import CoreImage
import UIKit

/// 二维码模块矩阵。`modules[row * size + col] == true` 表示该位置是深色模块。
/// 尺寸是符号本身的模块数，**不含**静默边。
struct QRMatrix {
    let size: Int
    let modules: [Bool]

    /// 越界一律当浅色，省得调用处到处判断。
    func isDark(_ row: Int, _ col: Int) -> Bool {
        guard row >= 0, row < size, col >= 0, col < size else { return false }
        return modules[row * size + col]
    }
}

enum QRCodeGenerator {

    /// ★ 用 CPU 渲染：二维码只有几十像素见方，软件渲染开销可忽略，
    ///   却换来了「不依赖 Metal/GPU」的确定性 —— 模拟器与云端 CI runner
    ///   拿不到 GPU 时 createCGImage 会直接返回 nil（标签上二维码就没了）。
    private static let context = CIContext(options: [.useSoftwareRenderer: true])

    /// 深/浅判定的灰度阈值（0~255）。
    private static let darkThreshold: UInt8 = 128

    /// 读出「深色 = 模块」的布尔矩阵；结构不合法时返回 nil（宁可不画，也不画错的）。
    static func matrix(for text: String) -> QRMatrix? {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.utf8.count <= LabelTemplate.maxQrBytes else { return nil }

        guard let gen = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        gen.setValue(Data(message.utf8), forKey: "inputMessage")
        gen.setValue("M", forKey: "inputCorrectionLevel")
        guard let ci = gen.outputImage else { return nil }

        let extent = ci.extent.integral
        let w = Int(extent.width), h = Int(extent.height)
        guard w > 0, h > 0, w == h, w <= 4096 else { return nil }

        guard let cg = context.createCGImage(ci, from: extent),
              // ★ 铺白底再合成：输出若带透明背景，透明处会变成白色而不是黑色，
              //   否则整张图会「因透明而全黑」，极性判定跟着一起错。
              let gray = GrayBuffer(cgImage: cg, whiteBackground: true) else { return nil }

        // 1) 去掉四周与符号无关的均匀边（其实就是静默边）。QR 符号最外圈
        //    永远含有定位图案或分隔符，不可能是整行/整列均匀的，所以只会削掉静默边。
        let box = gray.uniformBorderTrimmed()
        let size = box.width
        guard size >= 21, box.height == size else { return nil }

        // 2) 判定极性。QR 规范强制左上角是定位图案：
        //      · (0,0) 是定位图案外环 → 一定是**深色**
        //      · (1,1) 是定位图案内圈 → 一定是**浅色**
        //      · (0,7) 是定位图案右侧的分隔符 → 一定是**浅色**
        //    这三种特征两两组合就能确定「深色到底代表模块还是背景」。
        let at: (Int, Int) -> UInt8 = { r, col in
            gray.value(x: box.minX + col, y: box.minY + r)
        }
        func isDark(_ v: UInt8) -> Bool { v < darkThreshold }

        let cornerIsDark = isDark(at(0, 0))
        let innerIsLight = !isDark(at(1, 1))
        let separatorIsLight = !isDark(at(0, 7))

        // 深色 = 模块 时，上面三个「一定」必须原样成立；
        // 否则说明深色其实是背景（图像被反相过了），三个必须刚好反过来。
        let consistent = cornerIsDark
            ? (innerIsLight && separatorIsLight)
            : (!innerIsLight && !separatorIsLight)
        guard consistent else { return nil }

        let modulesAreDark = cornerIsDark
        var bits = [Bool](repeating: false, count: size * size)
        for r in 0..<size {
            for c in 0..<size {
                let dark = isDark(at(r, c))
                bits[r * size + c] = modulesAreDark ? dark : !dark
            }
        }
        return QRMatrix(size: size, modules: bits)
    }
}
