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
    ///
    /// ★★★ 2026-10-17（用户第 2 条）：「能不能优化摄像头，比如微信扫描的时候
    ///   起始就是 2x，**找到二维码但是看不清会变成 4x 换长焦镜头**」
    ///   ➜ 起始值就是 2x（这里），识别不出来时按 `zoomLadder` 自动升档（见下）。
    static let preferredZoom: CGFloat = 2.0

    // MARK: 自动变焦（★ 2026-10-17 用户第 2 条，仿微信扫码）

    /// 识别不出来时的**升档阶梯**：2x → 4x → 6x。
    /// 再往上就只剩数字裁切的噪点了，看不清反而更糟。
    static let zoomLadder: [CGFloat] = [2.0, 4.0, 6.0]
    /// 「完全没看到码」多久升一档（秒）—— 对应「拿着手机离标签比较远」。
    private static let zoomStepAfter: TimeInterval = 2.0
    /// 「看到码但读不出」升档的最小间隔（秒）—— 对应「找到了但太小/太糊」。
    /// 比上一个更短：此时已经确认画面里有码，可以果断放大。
    private static let undecodedBoostInterval: TimeInterval = 1.5
    /// 多久没扫到码就回落到起始档（秒）—— 防止用户放下手机后画面一直是糊的。
    private static let zoomResetAfter: TimeInterval = 12.0

    /// 当前档位下标（0 = 起始 2x）。
    private var zoomLevel = 0
    /// 上一次「看到码」（含看到但没解出）的时刻。
    private var lastCodeSeenAt = Date.distantPast
    /// 驱动「没看到码就升档 / 久无码就回落」的 1 秒心跳。
    private var zoomWatch: Timer?

    private let sessionQueue = DispatchQueue(label: "com.xiaoqi.expiry.scanner")
    private var isConfigured = false
    private var isHandling = false
    private var device: AVCaptureDevice?
    /// ★ 必须自己持有 input 引用，否则换摄像头时无法 removeInput。
    private var currentInput: AVCaptureDeviceInput?

    // MARK: 识别性能（★ 2026-10-17 用户第 5 条「扫码识别速度很慢」）

    /// 元数据回调**不能挂在主队列**上。
    ///
    /// ★ 原来 `setMetadataObjectsDelegate(self, queue: .main)`：主线程还要跑
    ///   SwiftUI 重绘（取景框里的扫描线是 `repeatForever` 动画），
    ///   每一帧的识别结果都派回主线程排队 → 体感就是「对准了要等一两秒」。
    ///   换成专用串行队列后，识别与 UI 互不阻塞。
    private let metadataQueue = DispatchQueue(label: "com.xiaoqi.expiry.scanner.metadata",
                                              qos: .userInitiated)
    /// 元数据输出 —— 设 `rectOfInterest` 要用它，所以自己留一份引用。
    private var metadataOutput: AVCaptureMetadataOutput?
    /// 当前设置过的识别区域（避免每次布局都重复设置）。
    private var interestRect: CGRect = .zero

    // MARK: 生命周期

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
            startZoomWatch()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureAndRun()
                        self.startZoomWatch()
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
        // ★ 回到起始变焦档（上一轮可能因为看不清升到了 4x/6x）。
        zoomLevel = 0
        lastCodeSeenAt = Date()
        start()
    }

    func stop() {
        // ★ 停识别就停变焦心跳（否则页面退出后还在悄悄改摄像头）。
        stopZoomWatch()
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
            // ★★★ 2026-10-17（用户第 5 条）：回调改到**专用队列**（原来挂 `.main`，
            //   会和 SwiftUI 重绘抢主线程 —— 见 `metadataQueue` 注释）。
            output.setMetadataObjectsDelegate(self, queue: metadataQueue)
            // ★★★ 2026-10-17（用户第 5 条）：**只识别二维码**。
            //   原来同时扫 7 种码型（qr / aztec / pdf417 / ean13 / ean8 /
            //   code128 / code39）—— 每帧都要跑 6 个用不上的检测器，
            //   这是「识别慢」最大的一项开销。本 App 只印二维码；
            //   扫到别的码也没有任何业务分支（最终都落到「无法识别」）。
            if output.availableMetadataObjectTypes.contains(.qr) {
                output.metadataObjectTypes = [.qr]
            }
            metadataOutput = output
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

    // MARK: 自动变焦心跳（★ 2026-10-17 用户第 2 条，仿微信扫码）

    /// 每秒一次的心跳：没看到码就升档；长时间没码就回落。
    ///
    /// ★ 为什么需要定时器：`AVCaptureMetadataOutput` 在**完全没检测到码**时
    ///   回调里的 `metadataObjects` 是空数组 —— 除了"没有码"我们拿不到任何信号。
    ///   「手机离标签比较远、码太小」就属于这种情况，只能靠心跳按时间推。
    private func startZoomWatch() {
        stopZoomWatch()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tickZoomWatch()
        }
        // `.common` —— 拖动 / 动画期间也要走（默认模式会被 RunLoop 挂起）。
        RunLoop.main.add(timer, forMode: .common)
        zoomWatch = timer
    }

    private func stopZoomWatch() {
        zoomWatch?.invalidate()
        zoomWatch = nil
    }

    /// ⚠️ 本函数与 `boostForUndecodedCode` 都**只在主线程**执行 ——
    ///   `zoomLevel` 是普通属性，跨线程读写会竞争。
    private func tickZoomWatch() {
        guard state.isRunning, !isHandling else { return }
        let idle = Date().timeIntervalSince(lastCodeSeenAt)

        // ① 12 秒完全扫不到 → 回落到起始档重新来（用户可能已经放下手机）。
        if idle > Self.zoomResetAfter, zoomLevel > 0 {
            zoomLevel = 0
            setZoom(Self.zoomLadder[0])
            lastCodeSeenAt = Date()
            return
        }
        // ② 持续 2 秒看不到码 → 升一档（等价于「再凑近一点」）。
        guard idle > Self.zoomStepAfter,
              zoomLevel < Self.zoomLadder.count - 1 else { return }
        zoomLevel += 1
        setZoom(Self.zoomLadder[zoomLevel])
        refocus()
        // 每升一档重新给 2 秒观察期（否则会一路飙到最高档）。
        lastCodeSeenAt = Date()
    }

    /// 「**看到了码但读不出**」的即时升档 —— 对应微信那种「找到就换长焦」。
    /// 由 `metadataOutput` 在 `stringValue == nil` 时派到主线程调用。
    private func boostForUndecodedCode() {
        guard state.isRunning, !isHandling else { return }
        guard Date().timeIntervalSince(lastCodeSeenAt) > Self.undecodedBoostInterval else { return }
        lastCodeSeenAt = Date()
        guard zoomLevel < Self.zoomLadder.count - 1 else { return }
        zoomLevel += 1
        setZoom(Self.zoomLadder[zoomLevel])
        refocus()
    }

    /// 只改变焦（复用 `applyTuning` 的夹取逻辑 —— 越界设 `videoZoomFactor`
    /// 会抛 ObjC 异常且 Swift 捕不到）。
    private func setZoom(_ factor: CGFloat) {
        guard let camera = device else { return }
        Self.applyTuning(camera, zoom: factor, preferNearFocus: camera.position == .back)
    }

    /// 强制重新对一次焦。
    ///
    /// ★ `continuousAutoFocus` 在低反差 / 近距离会「卡住」（画面一直糊、码永远读不出）。
    ///   主动切一次 `.autoFocus` 会让镜头重新走一遍对焦流程 —— 微信变焦之后
    ///   那一下「咔」的对焦就是这个动作。1.5 秒后恢复连续对焦。
    private func refocus() {
        guard let camera = device,
              camera.isFocusModeSupported(.autoFocus) else { return }
        do {
            try camera.lockForConfiguration()
            camera.focusMode = .autoFocus
            camera.unlockForConfiguration()
        } catch {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let cam = self?.device,
                  cam.isFocusModeSupported(.continuousAutoFocus) else { return }
            try? cam.lockForConfiguration()
            cam.focusMode = .continuousAutoFocus
            cam.unlockForConfiguration()
        }
    }

    // MARK: 识别区域（★ 2026-10-17 用户第 5 条）

    /// 把识别区域收窄到取景框（含 1.4 倍容错），只处理画面中间那一块。
    ///
    /// ★ 为什么能提速：`AVCaptureMetadataOutput` 默认扫**整帧 1080p**；
    ///   限定区域后系统只处理该矩形内的像素，解码更快、更稳，
    ///   也顺带抑制「画面边缘的别的码被误扫」。
    ///
    /// ⚠️ 参数必须是 `metadataOutputRectConverted(fromLayerRect:)` 的产物
    ///   （归一化 0~1 坐标）—— 手算屏幕坐标直接丢进来会**永远扫不到**。
    ///   换算在 `CameraHostView.layoutSubviews` 里做（它持有 previewLayer）。
    /// ⚠️ 1.4 倍放大的理由：用户手抖、标签没完全放进框里时也能扫到，
    ///   同时仍只处理画面中间一小块（比整帧快得多）。
    func setInterestRect(_ rect: CGRect) {
        guard rect.width > 0.02, rect.height > 0.02,
              rect.width <= 1, rect.height <= 1 else { return }
        guard rect != interestRect else { return }
        interestRect = rect
        sessionQueue.async { [weak self] in
            self?.metadataOutput?.rectOfInterest = rect
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
        // ⚠️ 本回调现在跑在 `metadataQueue` 上（不是主线程）。
        //    · `isHandling` 只在本队列读写 → 天然串行，不需要额外加锁；
        //    · `@Published lastCode` **必须回主线程写**，否则 SwiftUI 会
        //      在后台改状态（紫色运行期告警，严重时崩溃）。
        guard !isHandling else { return }

        // ★★★ 2026-10-17（用户第 2 条）：先识别「**看到了码但读不出**」——
        //   `stringValue == nil` 说明检测到了二维码、但解不出内容
        //   （离得远 / 太小 / 对不上焦）。这正是"该换长焦"的信号，
        //   派回主线程升档（`zoomLevel` 只在主线程读写）。
        var sawUndecoded = false
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject else { continue }
            let value = readable.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                isHandling = true
                DispatchQueue.main.async { [weak self] in
                    self?.lastCode = value
                }
                stop()
                return
            }
            sawUndecoded = true
        }
        if sawUndecoded {
            DispatchQueue.main.async { [weak self] in
                self?.boostForUndecodedCode()
            }
        }
    }
}

// MARK: - 相机预览

/// 相机预览层（标签预览页 `PreviewView` 已删除，本名字无冲突顾虑）。
struct ScannerCameraView: UIViewRepresentable {
    let session: AVCaptureSession
    /// 取景框边长（用来换算识别区域）。
    var interestSide: CGFloat = 250
    /// 换算好的识别区域（归一化坐标）回调。
    var onInterestRect: ((CGRect) -> Void)? = nil

    func makeUIView(context: Context) -> CameraHostView {
        let view = CameraHostView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.interestSide = interestSide
        view.onInterestRectChange = onInterestRect
        return view
    }

    func updateUIView(_ uiView: CameraHostView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.interestSide = interestSide
        uiView.onInterestRectChange = onInterestRect
    }
}

final class CameraHostView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass 已保证类型正确
        layer as! AVCaptureVideoPreviewLayer
    }

    /// 取景框边长（与 `ScanView.boxSide` 一致）。
    var interestSide: CGFloat = 250 {
        didSet { if oldValue != interestSide { setNeedsLayout() } }
    }
    /// 换算结果回调（SwiftUI 层接到后转给 `QRScannerModel.setInterestRect`）。
    var onInterestRectChange: ((CGRect) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        // ★★★ 2026-10-17（用户第 5 条）：把「屏幕上的取景框」换算成
        //   `AVCaptureMetadataOutput.rectOfInterest` 需要的归一化坐标。
        //
        //   这一步**必须**由持有 `previewLayer` 的 UIView 来做 —— SwiftUI 层
        //   拿不到 layer 坐标。必须用官方换算 API：
        //     `metadataOutputRectConverted(fromLayerRect:)`
        //   它会自动处理 `resizeAspectFill` 的填充比例与预览方向；
        //   手算屏幕坐标直接塞给 `rectOfInterest` 会**永远扫不到**。
        //
        //   ★ 放大 1.4 倍作容错：手抖、标签没完全放进框里也能扫到，
        //     同时仍然只处理画面中间那一块（比整帧快得多）。
        let side = min(interestSide * 1.4, min(bounds.width, bounds.height))
        let rect = CGRect(x: (bounds.width - side) / 2,
                          y: (bounds.height - side) / 2,
                          width: side,
                          height: side)
        let meta = previewLayer.metadataOutputRectConverted(fromLayerRect: rect)
        // 防御：session 还没挂上 / 预览尺寸为 0 时换算结果可能是 0 或越界，
        // 这种值设进去会让识别彻底失效 —— 直接丢弃。
        guard meta.width > 0.02, meta.height > 0.02,
              meta.width <= 1, meta.height <= 1 else { return }
        onInterestRectChange?(meta)
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

                // ★ 2026-10-17（用户第 5 条）：把取景框换算成识别区域传下去 ——
                //   只扫框内那一块，比整帧 1080p 快得多。
                ScannerCameraView(session: scanner.session,
                                  interestSide: boxSide,
                                  onInterestRect: { rect in
                                      scanner.setInterestRect(rect)
                                  })
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

            // ★ 2026-10-17：有了自动变焦 —— 文案同步说清楚
            //   （起始 2×，看不清会自动往 4×/6× 拉）。
            Text("2× 起步 · 看不清自动拉近")
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

    /// 相机页浮层按钮的 label（★ 2026-10-17 修「看不清」）。
    ///
    /// 用户反馈：「这个框内的文字肉眼看非常不清晰…比如字体改成白色？」
    /// 根因：`.liquidGlassButton()`（`.glass` 样式）的文字走 **tint（默认蓝）**，
    /// 叠在「透出浅色地板的玻璃」上对比度极低 —— 蓝字在灰白背景上几乎糊掉。
    /// ➜ 改成相机类 App 的标准做法：**深色半透明胶囊 + 白字**
    ///   （`.buttonStyle(.plain)` + `black.opacity(0.45)`，只有一层，不套娃）。
    ///   ⚠️ 别改回 `.glass`/`.bordered*` —— 那些的文字色跟着 tint 走，浅背景下又会看不清。
    private func scanControlLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.45), in: Capsule())
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                scanner.toggleTorch()
            } label: {
                scanControlLabel(scanner.torchOn ? "关闭手电筒" : "打开手电筒",
                                 icon: scanner.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
            }
            .buttonStyle(.plain)
            .disabled(!scanner.state.isRunning || !scanner.canUseTorch)
            .opacity(scanner.canUseTorch ? 1 : 0.45)

            if scanner.canSwitchCamera {
                Button {
                    scanner.switchCamera()
                } label: {
                    scanControlLabel("翻转", icon: "arrow.triangle.2.circlepath.camera")
                }
                .buttonStyle(.plain)
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
        if var first = LabelTemplate.parseKombuchaQr(code) {
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
            // ★ 2026-10-17（用户功能 2）：把**二维码原文**带上 ——
            //   二发页的「原材料是否用完」靠它在效期管理里定位这条一发记录
            //   （上面 add 用的就是同一个 `code`，所以 `qrText == sourceQR`）。
            first.sourceQR = code
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
        // ★ 2026-10-17（用户功能 2）：把二维码原文带上 —— 解冻页的
        //   「原材料是否用完」靠它在效期管理里定位这条冷冻记录
        //   （上面 add 用的就是同一个 `code`，所以 `qrText == sourceQR`）。
        var info = meat
        info.sourceQR = code
        path.append(ScanRoute.thaw(info))
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
