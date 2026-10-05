//
//  PrinterService.swift
//  打印机服务 —— CoreBluetooth BLE + 硕方 SFPrintSDK（后续接入）。
//  当前先提供打印协调器占位，保证预览页可编译；打印实现见 Task #48。
//

import Foundation

/// 打印协调器（单例）。
/// TODO(Task #48)：接入硕方 SFPrintSDK.xcframework，实现 BLE 扫描/连接/状态/打标。
final class PrintCoordinator {
    static let shared = PrintCoordinator()
    private init() {}

    /// 打印一张标签 PDF。
    func printLabel(pdfData: Data, fileName: String) {
        // 占位：尚未接入打印机，真机打印待实现。
        Swift.print("[PrinterService] print requested: \(fileName), \(pdfData.count) bytes")
    }
}
