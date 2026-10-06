//
//  PrinterService.swift
//  打印机服务 —— 硕方 T50 Pro 蓝牙（BLE）连接状态与打印协调。
//
//  真正的蓝牙跑在 ObjC 封装 `ExpiryPrinterSDK` 里（硕方 SDK 是 ObjC 框架，
//  且没有 modulemap，Swift 不能直接 import）。本类只做三件事：
//   1. 把 delegate 回调翻译成 SwiftUI 可观察的状态（@Published）；
//   2. 维护「已添加的打印机」持久化（与 Flutter 版共用同一 UserDefaults suite，
//      老数据可直接沿用）；
//   3. 给视图层提供 connect / print / testPage 这类语义化接口。
//
//  ★ iOS 硬限制（勿踩）：拿不到蓝牙 MAC 地址、系统不允许经典蓝牙 SPP，
//    所以「通用标签机（TSPL）/ 通用热敏机（ESC-POS）」在 iOS 上不可用，
//    只支持走 BLE 的硕方机型。iOS 侧用 peripheral.identifier（UUID）当设备地址。
//

import Combine
import Foundation
import SwiftUI
import UIKit

// MARK: - 机型

enum PrinterKind: String, CaseIterable, Identifiable {
    case supvan = "supvan_t50pro"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .supvan: return "硕方 T50 Pro"
        }
    }

    static func label(for code: String) -> String {
        PrinterKind(rawValue: code)?.label ?? "硕方 T50 Pro"
    }
}

// MARK: - 纸张类型（码值与安卓端一致：1 间隙 / 2 普通黑标 / 5 黑标卡纸）

enum LabelPaperType: Int, CaseIterable, Identifiable {
    case gap = 1
    case blackMark = 2
    case blackCard = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .gap: return "间隙纸"
        case .blackMark: return "普通黑标"
        case .blackCard: return "黑标卡纸"
        }
    }
}

// MARK: - 设备

struct PrinterDevice: Identifiable, Hashable {
    let uuid: String
    let name: String
    var id: String { uuid }
}

struct SavedPrinter: Identifiable, Codable, Hashable {
    let address: String
    var name: String
    var kind: String
    var id: String { address }
}

/// 蓝牙可用性。
enum BluetoothAvailability: Equatable {
    case unsupported
    case denied
    case off
    case ready

    var isReady: Bool { self == .ready }

    var message: String {
        switch self {
        case .unsupported: return "此设备不支持蓝牙"
        case .denied: return "蓝牙权限被拒绝，请到「设置」中允许"
        case .off: return "蓝牙未开启"
        case .ready: return "蓝牙已开启"
        }
    }
}

// MARK: - 服务

final class PrinterService: NSObject, ObservableObject {

    static let shared = PrinterService()

    /// 扫描发现的设备（同一轮内按 UUID 去重）。
    @Published private(set) var devices: [PrinterDevice] = []
    /// 已添加的打印机（持久化）。
    @Published private(set) var saved: [SavedPrinter] = []
    /// 当前连接。
    @Published private(set) var connectedUUID: String?
    @Published private(set) var connectedName: String?
    /// 正在扫描 / 正在连接 / 正在打印。
    @Published private(set) var isScanning = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isPrinting = false
    /// 蓝牙可用性（SDK 没有状态回调，用轻量轮询刷新）。
    @Published private(set) var bluetooth: BluetoothAvailability = .off
    /// 一次性提示文案（视图弹 toast 后置回 nil）。
    @Published var toast: String?

    private let defaults: UserDefaults

    /// ★ 延迟创建：构造 `ExpiryPrinterSDK` 会碰到 CoreBluetooth，
    /// 而一碰 CoreBluetooth 系统就弹蓝牙授权框。放在 lazy 里，
    /// 只有真正进「打印机」页（startMonitoring）或要扫描/打印时才创建，
    /// 权限弹窗才会出现在用户有预期的时刻。
    private lazy var sdk: ExpiryPrinterSDK = {
        let instance = ExpiryPrinterSDK.shared()
        instance.delegate = self
        return instance
    }()

    private var printCompletion: ((Bool, String?) -> Void)?
    private var lifecycleTimer: Timer?
    private var connectWatchdog: Timer?

    private static let savedKey = "saved_printers"

    override private init() {
        // 与 Flutter 版原生桥共用同一 suite，升级后可沿用已添加的打印机
        defaults = UserDefaults(suiteName: "expiry_printer") ?? .standard
        super.init()
        loadSaved()
    }

    // MARK: - 蓝牙状态

    func refreshBluetooth() {
        let value: BluetoothAvailability
        if !sdk.bluetoothSupported {
            value = .unsupported
        } else if sdk.bluetoothDenied {
            value = .denied
        } else if !sdk.bluetoothPoweredOn {
            value = .off
        } else {
            value = .ready
        }
        if bluetooth != value { bluetooth = value }
    }

    /// 页面出现时开始轻量轮询（SDK 不提供蓝牙开关回调）。
    func startMonitoring() {
        refreshBluetooth()
        guard lifecycleTimer == nil else { return }
        lifecycleTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshBluetooth()
        }
    }

    func stopMonitoring() {
        lifecycleTimer?.invalidate()
        lifecycleTimer = nil
    }

    /// 跳系统设置（蓝牙/隐私）。
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    // MARK: - 扫描

    func startScan() {
        guard bluetooth.isReady else {
            toast = bluetooth.message
            return
        }
        devices = []
        sdk.startScan()
    }

    func stopScan() {
        sdk.stopScan()
    }

    // MARK: - 连接

    func connect(_ uuid: String, name: String) {
        guard bluetooth.isReady else {
            toast = bluetooth.message
            return
        }
        guard !isConnecting else { return }
        isConnecting = true
        connectedUUID = nil
        connectedName = nil

        connectWatchdog?.invalidate()
        connectWatchdog = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self, self.isConnecting else { return }
            self.isConnecting = false
            self.toast = "连接超时，请确认打印机已开机并在附近"
        }

        sdk.connectDeviceUUID(uuid)
    }

    func connect(_ printer: SavedPrinter) {
        connect(printer.address, name: printer.name)
    }

    func disconnect() {
        sdk.disconnect()
        connectedUUID = nil
        connectedName = nil
        isConnecting = false
        connectWatchdog?.invalidate()
        connectWatchdog = nil
    }

    var isConnected: Bool { connectedUUID != nil }

    /// 当前连接名（用于状态卡展示）。
    var connectedDisplayName: String {
        connectedName ?? PrinterKind.supvan.label
    }

    // MARK: - 已添加的打印机

    private func loadSaved() {
        guard let raw = defaults.string(forKey: Self.savedKey),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([SavedPrinter].self, from: data) else {
            saved = []
            return
        }
        saved = list
    }

    private func persistSaved(_ list: [SavedPrinter]) {
        saved = list
        guard let data = try? JSONEncoder().encode(list),
              let raw = String(data: data, encoding: .utf8) else { return }
        defaults.set(raw, forKey: Self.savedKey)
    }

    @discardableResult
    func addSaved(uuid: String, name: String, kind: String = PrinterKind.supvan.rawValue) -> Bool {
        let address = uuid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return false }
        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? PrinterKind.label(for: kind) : name
        var list = [SavedPrinter(address: address, name: safeName, kind: kind)]
        list.append(contentsOf: saved.filter { $0.address != address })
        persistSaved(list)
        return true
    }

    func removeSaved(_ printer: SavedPrinter) {
        persistSaved(saved.filter { $0.address != printer.address })
    }

    func renameSaved(_ printer: SavedPrinter, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        persistSaved(saved.map {
            $0.address == printer.address
                ? SavedPrinter(address: $0.address, name: trimmed, kind: $0.kind)
                : $0
        })
    }

    // MARK: - 打印

    /// 打印一张标签 PDF。
    func printLabel(pdf: Data,
                    fileName: String,
                    copies: Int,
                    density: Int,
                    paperType: Int,
                    completion: ((Bool, String?) -> Void)? = nil) {
        guard isConnected else {
            toast = "请先连接打印机"
            completion?(false, "打印机未连接")
            return
        }
        guard !isPrinting else { return }

        let parsed = parseLabelSize(from: fileName)
        isPrinting = true
        printCompletion = completion

        let ok = sdk.printPDF(pdf,
                              widthMm: Int32(parsed.width),
                              heightMm: Int32(parsed.height),
                              copies: Int32(max(copies, 1)),
                              density: Int32(density),
                              paperType: Int32(paperType))
        if !ok {
            isPrinting = false
            printCompletion = nil
        }
    }

    /// 打印标尺测试页。
    func printTestPage(copies: Int, density: Int, completion: ((Bool, String?) -> Void)? = nil) {
        guard isConnected else {
            toast = "请先连接打印机"
            completion?(false, "打印机未连接")
            return
        }
        guard !isPrinting else { return }

        isPrinting = true
        printCompletion = completion
        let ok = sdk.printTestPageWidthMm(50,
                                          heightMm: 30,
                                          copies: Int32(max(copies, 1)),
                                          density: Int32(density))
        if !ok {
            isPrinting = false
            printCompletion = nil
        }
    }

    /// 标签尺寸固定 50 × 30 mm；文件名里带尺寸时以文件名为准（预留）。
    private func parseLabelSize(from fileName: String) -> (width: Int, height: Int) {
        _ = fileName
        return (50, 30)
    }
}

// MARK: - 硕方 SDK 回调

extension PrinterService: ExpiryPrinterSDKDelegate {

    func printerDidStartScan() {
        if !isScanning { isScanning = true }
    }

    func printerDidStopScan() {
        if isScanning { isScanning = false }
    }

    func printerDidFindDeviceUUID(_ uuid: String, name: String) {
        guard !uuid.isEmpty else { return }
        guard !devices.contains(where: { $0.uuid == uuid }) else { return }
        devices.append(PrinterDevice(uuid: uuid, name: name))
    }

    func printerDidConnectUUID(_ uuid: String, name: String) {
        connectWatchdog?.invalidate()
        connectWatchdog = nil
        isConnecting = false
        connectedUUID = uuid
        connectedName = name
        toast = "已连接 \(name)"
    }

    func printerDidFailToConnect() {
        connectWatchdog?.invalidate()
        connectWatchdog = nil
        isConnecting = false
        connectedUUID = nil
        connectedName = nil
        toast = "连接失败，请确认打印机已开机并在附近"
    }

    func printerDidDisconnect() {
        connectedUUID = nil
        connectedName = nil
        isConnecting = false
        toast = "打印机已断开"
    }

    func printerDidFinishPrint(_ success: Bool, message: String?) {
        isPrinting = false
        let completion = printCompletion
        printCompletion = nil
        completion?(success, message)
        if !success {
            toast = message?.isEmpty == false ? "打印失败：\(message!)" : "打印失败"
        }
    }
}
