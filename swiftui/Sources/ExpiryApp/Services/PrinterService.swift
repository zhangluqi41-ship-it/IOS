//
//  PrinterService.swift
//  打印机服务 —— 蓝牙（BLE）连接状态与打印协调。
//
//  真正的蓝牙跑在 ObjC 封装 `ExpiryPrinterSDK` 里（硕方 SDK 是 ObjC 框架，
//  且没有 modulemap，Swift 不能直接 import）。本类只做四件事：
//   1. 把 delegate 回调翻译成 SwiftUI 可观察的状态（@Published）；
//   2. 维护「已添加的打印机」持久化（与 Flutter 版共用同一 UserDefaults suite）；
//   3. 给视图层提供 connect / print / testPage 这类语义化接口；
//   4. 兜住「回调没来但实际已连上」的情况（轮询 SDK 的连接状态）。
//
//  ★ iOS 硬限制（勿踩）：拿不到蓝牙 MAC 地址、系统不允许经典蓝牙 SPP，
//    所以「通用标签机（TSPL）/ 通用热敏机（ESC-POS）」在 iOS 上不可用，
//    只支持走 BLE 的机型。iOS 侧用 peripheral.identifier（UUID）当设备地址。
//
//  ★★ 关于「重装之后就连不上了」：iOS 的 `peripheral.identifier` 是**按 App 安装**
//    分配的，重装 App（我们每 7 天都要重签重装一次）之后旧 UUID 就失效了。
//    「已添加」里存的就是这种旧 UUID —— 点它必然扫不到、永远连不上。
//    现在连接时会带设备名，原生层在 UUID 匹配失败后按**名字回退匹配**，
//    连上后再把新 UUID 回写覆盖旧记录。
//

import Combine
import Foundation
import SwiftUI
import UIKit

// MARK: - 机型

enum PrinterKind: String, CaseIterable, Identifiable {
    case supvan = "supvan_t50pro"
    case urovoK329 = "urovo_k329"
    case generic = "generic"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .supvan: return "硕方 T50 Pro"
        case .urovoK329: return "UROVO K329"
        case .generic: return "通用"
        }
    }

    /// 该机型在 iOS 上能不能直接打印。
    ///
    /// ★ iOS 不允许经典蓝牙 SPP，也没有通用的 BLE 打印协议 ——
    ///   目前只有硕方 SDK 这一条可用通路。其余机型可以扫描、尝试连接，
    ///   但打印不保证成功（如实告知，不要假装支持）。
    var printsOnIOS: Bool { self == .supvan }

    var note: String? {
        switch self {
        case .supvan: return nil
        case .urovoK329:
            return "UROVO K329 尚未验证。iOS 不允许经典蓝牙 SPP，只能尝试 BLE 连接，打印可能不成功。"
        case .generic:
            return "通用机型需要经典蓝牙 SPP 或厂商协议，iOS 系统不支持，仅能扫描/连接，无法打印。"
        }
    }

    static func label(for code: String) -> String {
        PrinterKind(rawValue: code)?.label ?? PrinterKind.supvan.label
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

    /// 当前选择的打印机型号（持久化）。
    @Published var kind: PrinterKind = .supvan {
        didSet {
            guard kind != oldValue else { return }
            defaults.set(kind.rawValue, forKey: Self.kindKey)
        }
    }

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

    /// 正在进行的连接意图。连上之后才据此写入「已添加」。
    private struct ConnectIntent {
        let uuid: String
        let name: String
        let kind: String
        /// 是不是从「已添加」里点进来的（失败时给更准确的提示）。
        let fromSaved: Bool
    }

    private var intent: ConnectIntent?
    private var printCompletion: ((Bool, String?) -> Void)?
    private var pendingRecord: LabelRecord?
    private var lifecycleTimer: Timer?
    private var connectWatchdog: Timer?
    private var connectPollTimer: Timer?

    private static let savedKey = "saved_printers"
    private static let kindKey = "printer_kind"

    override private init() {
        // 与 Flutter 版原生桥共用同一 suite，升级后可沿用已添加的打印机
        defaults = UserDefaults(suiteName: "expiry_printer") ?? .standard
        super.init()
        loadSaved()
        if let raw = defaults.string(forKey: Self.kindKey),
           let value = PrinterKind(rawValue: raw) {
            kind = value
        }
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

    /// 「刷新」：强制重开一轮扫描。
    ///
    /// ★ 原来这里直接调 startScan，而原生 `startScan` 有「已在扫描就忽略」的保护，
    ///   再加上扫描有 30 秒自动收尾 —— 结果在这 30 秒里点刷新毫无反应，
    ///   按钮还因为 `isScanning` 被禁用（用户实测反馈）。所以必须先停再起。
    func restartScan() {
        guard bluetooth.isReady else {
            toast = bluetooth.message
            return
        }
        sdk.stopScan()
        isScanning = false
        devices = []
        sdk.startScan()
    }

    func stopScan() {
        // ★ 连接进行中绝不停扫描：扫描表一关就会走 onDisappear -> stopScan，
        //   而那时 BLE 连接才刚发起，停扫描很容易把这次连接一起打断。
        guard !isConnecting else { return }
        sdk.stopScan()
    }

    // MARK: - 连接

    func connect(_ uuid: String, name: String, kind: String? = nil) {
        beginConnect(uuid: uuid, name: name,
                     kind: kind ?? self.kind.rawValue, fromSaved: false)
    }

    func connect(_ printer: SavedPrinter) {
        beginConnect(uuid: printer.address, name: printer.name,
                     kind: printer.kind, fromSaved: true)
    }

    private func beginConnect(uuid: String, name: String, kind: String, fromSaved: Bool) {
        guard bluetooth.isReady else {
            toast = bluetooth.message
            return
        }
        guard !isConnecting else { return }

        // ★★ 这里**故意不停扫描**。
        //   真机验证过能连上的 Flutter 版（`SFPrinterBridge.m` 的 `connect`）
        //   就是「一边扫描一边连」—— 拿到 CBPeripheral 后直接调
        //   `connectedBlueteeth:`，中间没有 stopScan。
        //   硕方 SDK 是闭源的，无法确认它的 `stopScan` 会不会顺手把内部
        //   CBCentralManager 收掉；一旦收掉，紧跟其后的连接请求就会静默失败。
        //   「不主动停扫描」才是已验证的路径。
        //
        //   至于「扫描表一关就 onDisappear -> stopScan 把连接掐掉」，
        //   由本类的 `stopScan()` 在 `isConnecting` 时直接返回来兜住。
        intent = ConnectIntent(uuid: uuid, name: name, kind: kind, fromSaved: fromSaved)
        isConnecting = true
        connectedUUID = nil
        connectedName = nil

        connectWatchdog?.invalidate()
        connectWatchdog = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            self?.failConnect(message: "连接超时，请确认打印机已开机并在附近")
        }

        // ★ 兜底：硕方的 connectSuccessBlock 偶发不回调（真机反馈过），
        //   而 SDK 自己的 getDeviceStatus 是可靠的。连上就主动落状态。
        connectPollTimer?.invalidate()
        connectPollTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            // ★ ObjC 的 `- (BOOL)isConnected` 被 Swift 导入成**方法**（不是属性），
            //   必须带括号调用；写成 `sdk.isConnected` 会编译不过。
            guard let self, self.isConnecting, self.sdk.isConnected() else { return }
            self.markConnected(uuid: self.sdk.connectedUUID ?? self.intent?.uuid ?? "",
                               name: self.intent?.name ?? self.connectedDisplayName)
        }

        sdk.connectDeviceUUID(uuid, name: name)
    }

    func disconnect() {
        sdk.disconnect()
        connectedUUID = nil
        connectedName = nil
        isConnecting = false
        intent = nil
        connectWatchdog?.invalidate()
        connectWatchdog = nil
        connectPollTimer?.invalidate()
        connectPollTimer = nil
    }

    var isConnected: Bool { connectedUUID != nil }

    /// 当前连接名（用于状态卡展示）。
    var connectedDisplayName: String {
        connectedName ?? kind.label
    }

    // MARK: - 连接结果

    private func markConnected(uuid: String, name: String) {
        connectWatchdog?.invalidate()
        connectWatchdog = nil
        connectPollTimer?.invalidate()
        connectPollTimer = nil

        let pending = intent
        intent = nil
        isConnecting = false

        let finalUUID = uuid.isEmpty ? (pending?.uuid ?? "") : uuid
        let finalName = name.isEmpty ? (pending?.name ?? kind.label) : name
        connectedUUID = finalUUID
        connectedName = finalName

        // ★ 连上了才写进「已添加」。以前是「点一下设备就加」，无论成败都加，
        //   结果列表里堆一堆连不上的僵尸条目（用户实测反馈）。
        if let pending, !finalUUID.isEmpty {
            addSaved(uuid: finalUUID, name: finalName, kind: pending.kind)
        }
        toast = "已连接 \(finalName)"
    }

    private func failConnect(message: String) {
        connectWatchdog?.invalidate()
        connectWatchdog = nil
        connectPollTimer?.invalidate()
        connectPollTimer = nil

        let pending = intent
        intent = nil
        isConnecting = false
        connectedUUID = nil
        connectedName = nil

        // 从「已添加」进来的失败，多半是重装 App 后旧标识失效 —— 直接给出可操作的建议。
        if pending?.fromSaved == true {
            toast = "没找到这台打印机。重装 App 后设备标识会变，请在右上角「+」里重新扫描添加。"
        } else {
            toast = message
        }
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
            ? PrinterKind.label(for: kind) : name.trimmingCharacters(in: .whitespacesAndNewlines)

        // ★ 同名也去重：按名字回退连上后 UUID 会变，旧记录得被顶掉，
        //   否则「已添加」里会同时留下新旧两条同名记录。
        var list = [SavedPrinter(address: address, name: safeName, kind: kind)]
        list.append(contentsOf: saved.filter { $0.address != address && $0.name != safeName })
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

    /// 清掉连不上的历史条目（重装后 UUID 全失效时用）。
    func removeAllSaved() {
        persistSaved([])
    }

    // MARK: - 打印

    /// 打印一张标签 PDF。
    /// - Parameter record: 打印成功后会写进「效期管理」的记录（在这里统一入库，
    ///   保证无论是模板页直接打印还是预览页打印，都只走同一条路径）。
    func printLabel(pdf: Data,
                    fileName: String,
                    copies: Int,
                    density: Int,
                    paperType: Int,
                    record: LabelRecord? = nil,
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
        pendingRecord = record

        let ok = sdk.printPDF(pdf,
                              widthMm: Int32(parsed.width),
                              heightMm: Int32(parsed.height),
                              copies: Int32(max(copies, 1)),
                              density: Int32(density),
                              paperType: Int32(paperType))
        if !ok {
            isPrinting = false
            printCompletion = nil
            pendingRecord = nil
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
        pendingRecord = nil
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

// MARK: - SDK 回调

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
        markConnected(uuid: uuid, name: name)
    }

    func printerDidFailToConnect() {
        failConnect(message: "连接失败，请确认打印机已开机并在附近")
    }

    func printerDidDisconnect() {
        connectedUUID = nil
        connectedName = nil
        isConnecting = false
        intent = nil
        connectPollTimer?.invalidate()
        connectPollTimer = nil
        toast = "打印机已断开"
    }

    func printerDidFinishPrint(_ success: Bool, message: String?) {
        isPrinting = false
        let completion = printCompletion
        let record = pendingRecord
        printCompletion = nil
        pendingRecord = nil
        completion?(success, message)

        if success, var record {
            // 打印成功才算「已打印」——写进效期管理列表
            record.printedAt = record.printedAt ?? Date()
            ExpiryStore.shared.add(record)
        } else if !success {
            toast = message?.isEmpty == false ? "打印失败：\(message!)" : "打印失败"
        }
    }
}
