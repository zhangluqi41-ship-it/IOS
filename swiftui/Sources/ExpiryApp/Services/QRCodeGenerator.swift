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

import CoreGraphics
import CoreImage

enum QRCodeGenerator {

    // ★ 用 CPU 渲染：二维码只有几十像素见方，软件渲染开销可忽略，
    //   却换来了「不依赖 Metal/GPU」的确定性——模拟器与云端 CI runner
    //   拿不到 GPU 时 createCGImage 会直接返回 nil（标签上二维码就没了）。
    private static let context = CIContext(options: [.useSoftwareRenderer: true])

    /// 生成「白底黑模块」的二维码 CGImage（1 模块 = 1 像素，无静默边）。
    ///
    /// CIQRCodeGenerator 原生输出是「黑底白模块」，这里用 CIColorInvert
    /// 反转成标准「白底黑模块」；反转会把透明背景变白，正好得到不透明白底。
    static func qrImage(for text: String) -> CGImage? {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.utf8.count <= 1200 else { return nil }

        guard let gen = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        gen.setValue(Data(message.utf8), forKey: "inputMessage")
        gen.setValue("M", forKey: "inputCorrectionLevel")
        guard let ci = gen.outputImage else { return nil }

        guard let invert = CIFilter(name: "CIColorInvert") else { return nil }
        invert.setValue(ci, forKey: kCIInputImageKey)
        guard let inverted = invert.outputImage else { return nil }

        // 直接栅格化到 1 像素/模块，避免放大带来的模糊
        let extent = inverted.extent.integral
        guard extent.width > 0, extent.height > 0, extent.width <= 4096 else { return nil }
        return context.createCGImage(inverted, from: extent)
    }
}
