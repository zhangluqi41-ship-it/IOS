//
//  ScanView.swift
//  扫码 —— AVFoundation 实时二维码识别。
//
//  目前接两条业务链：
//    ① **康普茶一发**标签 → 取回完成 / 最佳使用时间，直接进「二发」填写页；
//    ② **冷冻的肉类**标签 → 进「解冻」页（冷藏标签只入库、不跳转）。
//  扫到的物料同样会进「效期管理」列表。
//
//  ★ 二维码内容就是标签页面文字顺序拼接的结果，解析规则在
//    `LabelTemplate.parseKombuchaQr` / `LabelTemplate.parseMeatQr`，
//    与安卓/Flutter 版完全一致。
//
//  ★★ 2026-10-09：新增肉类。**判定顺序很重要** —— 先康普茶、再肉类。
//    两者正则不同（康普茶靠「完成时间」锚点、肉类靠「原始保质期」锚点），
//    理论上不会互相误吃，但顺序固定下来最稳。
//    ⚠️ 2026-10-10 起肉类锚点**同时收「原始保质期 / 完成时间」两种**
//      （解冻标签第二行已改成「完成时间」）—— 判定顺序依旧不变：
//      肉类解析器靠**标题前缀**（冷藏-/冷冻-/解冻-）把康普茶等挡在外面。
//
//  ★ 肉类为什么会走「扫码才能出来」这条路：用户要求解冻**不作为可选模板**
//    （见 `MeatThawView` 顶部注释）。
//

import AVFoundation
import SwiftUI
import UIKit

/// 扫码 Tab 的二级页路由。
enum ScanRoute: Hashable {
    case secondFermentation(KombuchaFirstLabel)
    /// 扫到**冷冻的肉类**标签 → 解冻页（冷藏 / 已解冻的标签不会走到这里）。
    case thaw(MeatLabelInfo)
}

// MARK: - 扫码模型

enum ScannerState: Equatable {
    case idle
    case running
    case denied
    case failed(String)

    var isRunning: Bool { self == .running }
}

final class QRScannerModel: NSObject, ObservableObject {

    @Published private(set) var state: ScannerState = .idle
    /// 最近一次识别到的内容；消费后调用 `resume()` 复位。
    @Published private(set) var lastCode: String?
    @Published private(set) var torchOn = false
    @Published private(set) var canSwitchCamera = false
    /// 当前摄像头有没有闪光灯（前置一般没有，按钮据此置灰）。
    @Published private(set) var canUseTorch = false

    let session = AVCaptureSession()

    /// 后置摄像头默认变焦倍数。
    ///
    /// ★ 用户反馈「经常无法对焦，比如使用 2 倍变焦镜头，对焦更快」。
    ///   2 倍有两个好处：
    ///     ① 二维码在画面里更大 → 每个模块占更多像素 → 解码更快更稳；
    ///     ② 走的是长焦/裁切，景深与反差更好，对焦判定更干脆。
    static let preferredZoom: CGFloat = 2.0

    private let sessionQueue = DispatchQueue(label: "com.xiaoqi.expiry.scanner")
    private var isConfigured = false
    private var isHandling = false
    private var device: AVCaptureDevice?
    /// ★ 必须自己持有 input 引用，否则换摄像头时无法 removeInput。
    private var currentInput: AVCaptureDeviceInput?

    // MARK: 生命周期

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureAndRun()
                    } else {
                        self.state = .denied
                    }
                }
            }
        default:
            state = .denied
        }
    }

    /// 消费掉上一次结果并重新开始识别。
    func resume() {
        lastCode = nil
        isHandling = false
        start()
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: 配置

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured { self.configure() }
            guard self.isConfigured else { return }
            if !self.session.isRunning { self.session.startRunning() }
            // ★ 变焦必须在会话**跑起来之后**才真正生效（之前设的会被首帧重置），
            //   所以这里再套一次参数。
            if let camera = self.device {
                Self.applyTuning(camera,
                                 zoom: camera.position == .back ? Self.preferredZoom : 1.0,
                                 preferNearFocus: camera.position == .back)
            }
            DispatchQueue.main.async {
                if self.state != .running { self.state = .running }
            }
        }
    }

    /// 给摄像头套上「扫码友好」的参数。
    ///
    /// 三件事，都是针对「经常无法对焦」：
    ///   ① **变焦** —— 二维码在画面里更大，模块更粗，解码更快；
    ///   ② **连续自动对焦** —— 不再对一次就停在糊的位置；
    ///   ③ **近景优先** —— 扫标签时手机离码 10~25cm，
    ///      把对焦范围限制到近景能明显减少「拉风箱」。
    ///
    /// ⚠️ 必须整段包在 `lockForConfiguration` 里，且每项都先用
    ///   `isXxxSupported` 问过 —— 虚拟多摄设备上设不支持的项会抛异常。
    static func applyTuning(_ device: AVCaptureDevice,
                            zoom: CGFloat,
                            preferNearFocus: Bool) {
        do {
            try device.lockForConfiguration()
        } catch {
            return   // 拿不到锁就跳过，不影响扫码本身
        }
        defer { device.unlockForConfiguration() }

        // ① 变焦：夹在 [1, min(格式上限, 10)] 之间。
        //    ★ 越界设 `videoZoomFactor` 会抛 ObjC 异常（Swift 捕不到，直接崩），
        //      所以这里的夹取是**必须**的，不是保险起见。
        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10)
        let target = min(max(zoom, 1.0), max(1.0, maxZoom))
        if abs(device.videoZoomFactor - target) > 0.01 {
            device.videoZoomFactor = target
        }

        // ② 连续自动对焦
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        // ③ 近景优先（前置不设 —— 自拍场景距离不定）
        if preferNearFocus, device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = .near
        }
        // ④ 平滑对焦：虚拟多摄切换镜头时不要出现呼吸感
        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = true
        }
    }

    private func configure() {
        // ★★ 优先用**虚拟多摄**设备，而不是写死 `builtInWideAngleCamera`。
        //
        //   用户反馈「扫码是不是只调用了一个摄像头？经常无法对焦」—— 是的，
        //   原来就写死了单颗广角。虚拟多摄（triple / dualWide / dual）会把
        //   底下几颗镜头合成一个逻辑设备，设 `videoZoomFactor = 2` 时由系统
        //   直接切到长焦（或 48MP 主摄的 2 倍裁切），比在主摄上做数字放大
        //   清晰得多，对焦也更快。
        //
        //   优先级：三摄（有真长焦）→ 双摄广角（超广+广角）→ 双摄 → 单广角。
        let virtualTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
        ]
        var back: AVCaptureDevice?
        for type in virtualTypes {
            if let candidate = AVCaptureDevice.default(type, for: .video, position: .back) {
                back = candidate
                break
            }
        }
        if back == nil {
            back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
        let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        guard let camera = back ?? front ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            DispatchQueue.main.async { self.state = .failed("无法访问摄像头，请确认设备有可用相机") }
            return
        }

        device = camera
        currentInput = input

        session.beginConfiguration()
        session.sessionPreset = .high
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            let desired: [AVMetadataObject.ObjectType] = [
                .qr, .aztec, .pdf417, .ean13, .ean8, .code128, .code39,
            ]
            output.metadataObjectTypes = desired.filter {
                output.availableMetadataObjectTypes.contains($0)
            }
        } else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.state = .failed("摄像头初始化失败") }
            return
        }

        session.commitConfiguration()
        isConfigured = true

        let switchable = back != nil && front != nil
        DispatchQueue.main.async {
            self.canSwitchCamera = switchable
            self.canUseTorch = camera.hasTorch
            // 回到后置时手电筒状态复位（前置没有闪光灯）
            self.torchOn = camera.hasTorch && camera.torchMode == .on
        }
    }

    // MARK: 前后摄像头切换

    func switchCamera() {
        guard canSwitchCamera else { return }
        sessionQueue.async { [weak self] in
            guard let self, let existing = self.currentInput else { return }
            let target: AVCaptureDevice.Position = existing.device.position == .back ? .front : .back
            guard let next = Self.camera(for: target),
                  let input = try? AVCaptureDeviceInput(device: next) else { return }

            self.session.beginConfiguration()
            self.session.removeInput(existing)
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.session.commitConfiguration()
                // 换完立刻套一遍参数：后置要 2 倍 + 近景对焦，前置只要 1 倍
                Self.applyTuning(next,
                                 zoom: target == .back ? Self.preferredZoom : 1.0,
                                 preferNearFocus: target == .back)
                DispatchQueue.main.async {
                    self.currentInput = input
                    self.device = next
                    // 前置无闪光灯 → 复位手电筒状态与可用性
                    self.canUseTorch = next.hasTorch
                    self.torchOn = next.hasTorch && next.torchMode == .on
                }
            } else {
                // 换失败就换回去，别把画面弄黑
                self.session.addInput(existing)
                self.session.commitConfiguration()
            }
        }
    }

    /// 按位置取摄像头，后置优先虚拟多摄（与 `configure` 保持同一套优先级）。
    static func camera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            for type in [AVCaptureDevice.DeviceType.builtInTripleCamera,
                         .builtInDualWideCamera, .builtInDualCamera] {
                if let candidate = AVCaptureDevice.default(type, for: .video, position: .back) {
                    return candidate
                }
            }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    // MARK: 手电筒

    func toggleTorch() {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            torchOn = (device.torchMode == .on)
            device.unlockForConfiguration()
        } catch {
            // 忽略：手电筒不可用不影响扫码
        }
    }

    func turnTorchOff() {
        guard let device, device.hasTorch, device.torchMode == .on else {
            torchOn = false
            return
        }
        try? device.lockForConfiguration()
        device.torchMode = .off
        torchOn = false
        device.unlockForConfiguration()
    }
}

// MARK: - 识别回调

extension QRScannerModel: AVCaptureMetadataOutputObjectsDelegate {

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !isHandling else { return }
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  let value = readable.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            isHandling = true
            lastCode = value
            stop()
            return
        }
    }
}

// MARK: - 相机预览

/// 相机预览层（标签预览页 `PreviewView` 已删除，本名字无冲突顾虑）。
struct ScannerCameraView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraHostView {
        let view = CameraHostView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraHostView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

final class CameraHostView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass 已保证类型正确
        layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - 扫码页

struct ScanView: View {
    @Binding var path: NavigationPath

    @StateObject private var scanner = QRScannerModel()
    @State private var showInvalidAlert = false
    @State private var alertTitle = "无法识别的标签"
    @State private var invalidText = ""

    private let boxSide: CGFloat = 250

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.black.ignoresSafeArea()

                ScannerCameraView(session: scanner.session)
                    .ignoresSafeArea()

                overlay
            }
            .navigationTitle("扫码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: ScanRoute.self) { route in
                switch route {
                case .secondFermentation(let first):
                    KombuchaSecondView(first: first)
                case .thaw(let meat):
                    MeatThawView(meat: meat)
                }
            }
            .onAppear {
                guard path.isEmpty else { return }
                scanner.resume()
            }
            .onDisappear {
                scanner.stop()
                scanner.turnTorchOff()
            }
            .onChange(of: path.count) { _, count in
                if count == 0 { scanner.resume() }
            }
            .onChange(of: scanner.lastCode) { _, code in
                handle(code)
            }
            .alert(alertTitle, isPresented: $showInvalidAlert) {
                Button("继续扫描", role: .cancel) { scanner.resume() }
            } message: {
                Text(invalidText)
            }
        }
    }

    // MARK: 叠层

    private var overlay: some View {
        VStack(spacing: 0) {
            Spacer()

            viewfinder

            Text("将二维码放入框内")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 18)

            // 让「用了 2 倍镜头」这件事对用户可见（本轮按反馈改的）
            Text("后置 2× 变焦 · 近距自动对焦")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 4)

            Spacer()

            controls
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                .frame(width: boxSide, height: boxSide)

            CornerBrackets(side: boxSide)

            ScanLine(side: boxSide)
        }
        .frame(width: boxSide, height: boxSide)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                scanner.toggleTorch()
            } label: {
                Label(scanner.torchOn ? "关闭手电筒" : "打开手电筒",
                      systemImage: scanner.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .liquidGlassButton()
            .disabled(!scanner.state.isRunning || !scanner.canUseTorch)
            .opacity(scanner.canUseTorch ? 1 : 0.45)

            if scanner.canSwitchCamera {
                Button {
                    scanner.switchCamera()
                } label: {
                    Label("翻转", systemImage: "arrow.triangle.2.circlepath.camera")
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .liquidGlassButton()
                .disabled(!scanner.state.isRunning)
            }

            if case .denied = scanner.state {
                Button("打开设置") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
                .liquidGlassProminentButton()
                .tint(Theme.brand)
            }
        }
    }

    // MARK: 结果处理

    private func handle(_ code: String?) {
        guard let code, !code.isEmpty else { return }

        // ① 康普茶一发标签 → 进二发
        if let first = LabelTemplate.parseKombuchaQr(code) {
            // 扫到的物料同样进「效期管理」；同一条码重复扫会按 qrText 合并
            ExpiryStore.shared.add(
                LabelRecord(title: first.title,
                            kind: .kombucha,
                            maker: first.maker,
                            createdAt: Date(),
                            printedAt: nil,
                            expireAt: first.finished,
                            bestBefore: first.bestBefore,
                            usedAt: nil,
                            qrText: code,
                            source: .scanned)
            )
            path.append(ScanRoute.secondFermentation(first))
            return
        }

        // ② 肉类标签
        if let meat = LabelTemplate.parseMeatQr(code) {
            handleMeat(meat, code: code)
            return
        }

        // ③ 通用 / 奶制品标签 —— 没有后续流程，但**必须入库**
        //    （清单「二、扫码」第 1 条：所有物料扫码后若无后续操作，
        //      都要重新加入效期管理系统）。
        if let generic = LabelTemplate.parseGenericQr(code) {
            ExpiryStore.shared.add(
                LabelRecord(title: generic.title,
                            kind: .generic,
                            // 二维码里没有制作人，扫回来留空 —— 列表会显示占位。
                            maker: "",
                            createdAt: Date(),
                            printedAt: nil,
                            expireAt: generic.expireAt,
                            bestBefore: generic.bestBefore,
                            usedAt: nil,
                            qrText: code,
                            source: .scanned)
            )
            // ★ 不跳转任何页面（这就是「无后续操作」），
            //   只提示已入库，然后继续扫描。
            showAlert(title: "已加入效期管理",
                      message: "「\(generic.title)」已重新加入效期管理列表。")
            return
        }

        // ④ 都不是 —— 不是本 App 印出来的标签
        showAlert(title: "无法识别的标签",
                  message: "识别到的内容：\n\(code.prefix(160))\n\n请扫描本 App 生成的标签二维码。")
    }

    /// 肉类标签：先入库（和康普茶一样，按 qrText 去重合并），
    /// 再决定要不要进解冻流程。
    ///
    /// ★ 只有「**冷冻** 且 **尚未解冻**」才进解冻页 —— 逐条对应用户要求：
    ///     · 「冷冻打印出来的二维码，再次扫描就是解冻」
    ///     · 冷藏肉不需要解冻，「扫它不会再生成新标签」（模板页 footer 也是这么写的）
    ///     · 解冻标签自己再被扫，不能又解冻一次（否则会无限套娃）
    private func handleMeat(_ meat: MeatLabelInfo, code: String) {
        ExpiryStore.shared.add(
            LabelRecord(title: meat.title,
                        kind: .meat,
                        // 二维码里没有制作人（`LabelData.qrText` 只含后两组时间），
                        // 所以扫回来的记录 maker 为空 —— 列表会显示占位。
                        maker: "",
                        createdAt: Date(),
                        printedAt: nil,
                        expireAt: meat.expireAt,
                        bestBefore: meat.bestBefore,
                        usedAt: nil,
                        qrText: code,
                        source: .scanned)
        )

        if meat.alreadyThawed {
            showAlert(title: "这是解冻标签",
                      message: "「\(meat.title)」已经解冻过一次了，已加入效期管理，"
                             + "不会再触发解冻。")
            return
        }
        guard meat.storage.isFrozen else {
            showAlert(title: "冷藏肉类标签",
                      message: "「\(meat.title)」是冷藏肉类，不需要解冻。"
                             + "已加入效期管理。")
            return
        }

        // 冷冻 + 未解冻 → 进解冻页
        path.append(ScanRoute.thaw(meat))
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        invalidText = message
        showInvalidAlert = true
    }
}

// MARK: - 取景框装饰

/// 四角取景框。
private struct CornerBrackets: View {
    let side: CGFloat
    private let length: CGFloat = 30
    private let thickness: CGFloat = 4

    var body: some View {
        ZStack {
            bracket.rotationEffect(.degrees(0)).offset(x: -(side / 2) + length / 2, y: -(side / 2) + length / 2)
            bracket.rotationEffect(.degrees(90)).offset(x: (side / 2) - length / 2, y: -(side / 2) + length / 2)
            bracket.rotationEffect(.degrees(270)).offset(x: -(side / 2) + length / 2, y: (side / 2) - length / 2)
            bracket.rotationEffect(.degrees(180)).offset(x: (side / 2) - length / 2, y: (side / 2) - length / 2)
        }
    }

    private var bracket: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: length, y: 0))
        }
        .stroke(Theme.brandLight, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
        .frame(width: length, height: length)
    }
}

/// 上下往复的扫描线。
private struct ScanLine: View {
    let side: CGFloat
    @State private var down = false

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Theme.brandLight.opacity(0.9), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: side - 24, height: 2)
            .offset(y: down ? (side / 2 - 16) : -(side / 2 - 16))
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    down = true
                }
            }
    }
}

#Preview {
    ScanView(path: .constant(NavigationPath()))
}
