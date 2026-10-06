//
//  PrinterMenuView.swift
//  打印机 —— 蓝芽状态 / 当前连接 / 已添加的打印机 / 打印参数。
//
//  设计红线（规格 6.1）：Liquid Glass 只属于导航层与浮层。
//  本页是内容页，所以列表行一律用系统语义背景 + 系统按钮，
//  不把玻璃材质塞进列表（那样会出现「双层背景」的观感问题）。
//

import SwiftUI

struct PrinterMenuView: View {
    @Binding var path: NavigationPath

    @ObservedObject private var printer = PrinterService.shared

    @State private var showScanner = false
    @State private var testResult: String?

    @AppStorage("printDensity") private var density: Int = 0
    @AppStorage("printCopies") private var copies: Int = 1
    @AppStorage("paperType") private var paperType: Int = 1

    var body: some View {
        NavigationStack(path: $path) {
            List {
                bluetoothSection
                currentSection
                savedSection
                optionsSection
            }
            .navigationTitle("打印机")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!printer.bluetooth.isReady)
                }
            }
            .sheet(isPresented: $showScanner) {
                ScanDevicesSheet()
            }
            .onAppear { printer.startMonitoring() }
            .onDisappear { printer.stopMonitoring() }
            .alert("提示", isPresented: toastBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(printer.toast ?? "")
            }
            .alert("打印测试页", isPresented: testResultBinding) {
                Button("好", role: .cancel) { testResult = nil }
            } message: {
                Text(testResult ?? "")
            }
        }
    }

    // MARK: - 绑定

    private var toastBinding: Binding<Bool> {
        Binding(
            get: { printer.toast != nil },
            set: { if !$0 { printer.toast = nil } }
        )
    }

    private var testResultBinding: Binding<Bool> {
        Binding(
            get: { testResult != nil },
            set: { if !$0 { testResult = nil } }
        )
    }

    // MARK: - 蓝牙状态

    private var bluetoothSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: bluetoothIcon)
                    .foregroundStyle(printer.bluetooth.isReady ? Theme.brand : .secondary)
                    .frame(width: 22)
                Text("蓝牙")
                Spacer()
                Text(printer.bluetooth.message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if printer.bluetooth == .denied || printer.bluetooth == .off {
                Button("打开系统设置") {
                    printer.openSystemSettings()
                }
            }
        } header: {
            Text("连接环境")
        } footer: {
            Text("硕方 T50 Pro 通过蓝牙低功耗（BLE）连接。iOS 不提供蓝牙 MAC 地址，设备以系统分配的标识区分。")
        }
    }

    private var bluetoothIcon: String {
        switch printer.bluetooth {
        case .ready: return "dot.radiowaves.left.and.right"
        case .off: return "bolt.horizontal.circle"
        case .denied: return "lock.circle"
        case .unsupported: return "xmark.circle"
        }
    }

    // MARK: - 当前打印机

    @ViewBuilder
    private var currentSection: some View {
        Section {
            if printer.isConnected {
                HStack(spacing: 12) {
                    Image(systemName: "printer.fill")
                        .foregroundStyle(Theme.brand)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(printer.connectedDisplayName)
                            .font(.body)
                        Text("已连接")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(Theme.brand)
                        .frame(width: 8, height: 8)
                }

                Button {
                    printTestPage()
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("打印标尺测试页")
                        Spacer()
                        if printer.isPrinting {
                            ProgressView()
                        }
                    }
                }
                .disabled(printer.isPrinting)

                Button("断开连接", role: .destructive) {
                    printer.disconnect()
                }
            } else if printer.isConnecting {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在连接…")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "printer")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    Text("未连接")
                        .foregroundStyle(.secondary)
                }
                Button {
                    showScanner = true
                } label: {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        Text("扫描并连接打印机")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .disabled(!printer.bluetooth.isReady)
            }
        } header: {
            Text("当前打印机")
        } footer: {
            if printer.isConnected {
                Text("测试页用于确认走纸、边距与浓度是否合适。")
            }
        }
    }

    // MARK: - 已添加

    @ViewBuilder
    private var savedSection: some View {
        Section {
            if printer.saved.isEmpty {
                Text("还没有添加打印机")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(printer.saved) { saved in
                    Button {
                        printer.connect(saved)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "printer")
                                .foregroundStyle(Theme.brand)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(saved.name)
                                    .foregroundStyle(.primary)
                                Text(PrinterKind.label(for: saved.kind))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if printer.connectedUUID == saved.address {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                    }
                    .disabled(printer.isConnecting)
                }
                .onDelete { indexSet in
                    for index in indexSet where printer.saved.indices.contains(index) {
                        printer.removeSaved(printer.saved[index])
                    }
                }
            }
        } header: {
            Text("已添加")
        } footer: {
            Text("左滑可删除。点一下即连接。")
        }
    }

    // MARK: - 打印参数

    private var optionsSection: some View {
        Section {
            Picker("纸张类型", selection: $paperType) {
                ForEach(LabelPaperType.allCases) { type in
                    Text(type.label).tag(type.rawValue)
                }
            }

            Picker("浓度", selection: $density) {
                Text("自动").tag(0)
                ForEach(1...9, id: \.self) { level in
                    Text("\(level)").tag(level)
                }
            }

            Stepper(value: $copies, in: 1...10) {
                HStack {
                    Text("份数")
                    Spacer()
                    Text("\(copies)")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("默认打印参数")
        } footer: {
            Text("标签规格 50 × 30 mm。浓度选「自动」时由打印机自行判断。")
        }
    }

    // MARK: - 动作

    private func printTestPage() {
        printer.printTestPage(copies: copies, density: density) { ok, message in
            if ok {
                testResult = "测试页已发送到打印机。\n请确认走纸、边距与浓度是否合适。"
            } else {
                testResult = message?.isEmpty == false ? message! : "打印失败"
            }
        }
    }
}

// MARK: - 扫描附近设备

struct ScanDevicesSheet: View {
    @ObservedObject private var printer = PrinterService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if printer.devices.isEmpty {
                    HStack(spacing: 12) {
                        if printer.isScanning {
                            ProgressView()
                        }
                        Text(printer.isScanning ? "正在扫描附近设备…" : "未发现设备")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(printer.devices) { device in
                    Button {
                        printer.addSaved(uuid: device.uuid, name: device.name)
                        printer.connect(device.uuid, name: device.name)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "printer")
                                .foregroundStyle(Theme.brand)
                                .frame(width: 22)
                            Text(device.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .disabled(printer.isConnecting)
                }
            }
            .navigationTitle("附近的打印机")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        printer.startScan()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(printer.isScanning)
                }
            }
            .onAppear { printer.startScan() }
            .onDisappear { printer.stopScan() }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    PrinterMenuView(path: .constant(NavigationPath()))
}
