//
//  QRCodeGenerator.swift
//  二维码生成 —— CoreImage 的 CIQRCodeGenerator，M 级纠错。
//  对应 Flutter 的 `qr` 包（QrErrorCorrectLevel.M）。
//

import CoreImage
import UIKit

enum QRCodeGenerator {
    /// 生成「白底黑模块」的二维码 CGImage（1 模块 = 1 像素，无静默边）。
    ///
    /// CIQRCodeGenerator 原生输出是「黑底白模块」，这里用 CIColorInvert
    /// 反转成标准「白底黑模块」；反转会把透明背景变白，正好得到不透明白底。
    static func qrImage(for text: String) -> CGImage? {
        guard let gen = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        gen.setValue(Data(text.utf8), forKey: "inputMessage")
        gen.setValue("M", forKey: "inputCorrectionLevel")
        guard let ci = gen.outputImage else { return nil }

        guard let invert = CIFilter(name: "CIColorInvert") else { return nil }
        invert.setValue(ci, forKey: kCIInputImageKey)
        guard let inverted = invert.outputImage else { return nil }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(inverted, from: inverted.extent)
    }
}
