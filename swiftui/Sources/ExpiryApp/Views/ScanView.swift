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

    /// 后置摄像头默认变焦倍数 = **2×**（起始档，用户定的）。
    ///
    /// ★ 用户反馈「经常无法对焦，比如使用 2 倍变焦镜头，对焦更快」。
    ///   2 倍有两个好处：
    ///     ① 二维码在画面里更大 → 每个模块占更多像素 → 解码更快更稳；
    ///     ② 走的是长焦/裁切，景深与反差更好，对焦判定更干脆。
    static let preferredZoom: CGFloat = 2.0

    // MARK: 长焦档（★ 2026-10-18 订正：**只有 2× → 4× 两档**，不做阶梯）

    /// 长焦档 = **4×**。
    ///
    /// ★★★ 用户三次纠正后的最终口径（2026-10-18）：
    ///   · 「摄像头只需要 2x 到 4x，**不要乱增加倍数**，只是让你换摄像头而已」
    ///   · 「切换摄像头太生硬，应该 **2x 线性拉到 4x**，是放大到长焦镜头」
    ///   · 「**只需要你在看到二维码但读不出再拉长焦，没看到不用换档！**」
    ///   ➜ 只有两档：2×（起始）/ 4×（长焦），**没有 6×、没有阶梯**。
    ///   ➜ **唯一触发条件**：`metadataOutput` 里有二维码对象但
    ///     `stringValue == nil`（= 看到码、解不出）。**画面里没码时什么都不做**。
    ///   ➜ 换档必须走 `rampZoom`（线性渐变），不许直接设 `videoZoomFactor = 4`
    ///     —— 那是瞬间跳变（用户嫌「生硬」）。
    static let teleZoom: CGFloat = 4.0

    /// 当前是否处于长焦档（4×）—— UI 用它显示当前倍率。
    ///
    /// ★★ 2026-10-18（用户第 3 条）：「对准标签并且在看不清的情况下并没有放大，
    ///   **删除这个功能吧，手动双击放大就好了**」
    ///   ➜ 自动放大的整套逻辑（Vision 检测 + ramp 触发）**已全部删除**；
    ///     现在**只有双击**能切 2× / 4×，由 `toggleTeleZoom` 改这个状态。
    @Published private(set) var isTeleZoom = false

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
        // ★ 回到起始档（2×）—— 上一轮可能双击拉到了长焦。
        //   （真正把 `videoZoomFactor` 设回 2× 的是 `configureAndRun` 里的 `applyTuning`。）
        isTeleZoom = false
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

    // MARK: 长焦切换（★ 2026-10-18：只有双击，2× ⇄ 4×）

    /// **双击预览**：在 2× 与 4×（长焦）之间切换 —— 这是**唯一**的切换方式。
    ///
    /// ★ 用户原话：「对准标签并且在看不清的情况下并没有放大，
    ///   **删除这个功能吧，手动双击放大就好了**」
    ///   ➜ 自动放大（Vision 检测 + 自动 ramp）**已整段删除**，只留双击。
    func toggleTeleZoom() {
        guard state.isRunning, !isHandling else { return }
        isTeleZoom.toggle()
        rampZoom(to: isTeleZoom ? Self.teleZoom : Self.preferredZoom)
    }

    /// **线性**变焦到目标倍数 —— 绝不直接设 `videoZoomFactor`。
    ///
    /// ★ 用户两次的原话：
    ///   · 「切换摄像头太生硬，应该 **2x 线性拉到 4x**，是放大到长焦镜头」
    ///   · 「**切换动作可以更快速一些，现在太慢了**」
    ///   ➜ `ramp(toVideoZoomFactor:withRate:)` 匀速推过去；
    ///     虚拟多摄设备越过临界倍率时由系统**自动切到物理长焦镜头**。
    ///   ➜ rate 从 3.0 **提到 8.0**：2 → 4 约 **0.25 秒**走完（原来 0.67 秒，用户嫌慢）。
    private func rampZoom(to target: CGFloat) {
        guard let camera = device else { return }
        do {
            try camera.lockForConfiguration()
            // 越界设 videoZoomFactor 会抛 ObjC 异常（Swift 捕不到）→ 必须夹取。
            let maxZoom = min(camera.activeFormat.videoMaxZoomFactor, 10)
            let clamped = min(max(target, 1.0), max(1.0, maxZoom))
            camera.ramp(toVideoZoomFactor: clamped, withRate: 8.0)
            camera.unlockForConfiguration()
        } catch {
            // 拿不到锁就放弃这次变焦 —— 不影响扫码本身。
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
        // ⚠️ 本回调跑在 `metadataQueue` 上（不是主线程）。
        //    · `isHandling` 只在本队列读写 → 天然串行，不需要额外加锁；
        //    · `@Published lastCode` **必须回主线程写**，否则 SwiftUI 会
        //      在后台改状态（紫色运行期告警，严重时崩溃）。
        // ★ 2026-10-18：自动放大功能已按用户要求删除 —— 这里只负责"解码成功就出结果"，
        //   不再做任何变焦判断（变焦只由双击 `toggleTeleZoom` 触发）。
        guard !isHandling else { return }
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  let value = readable.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            isHandling = true
            DispatchQueue.main.async { [weak self] in
                self?.lastCode = value
            }
            stop()
            return
        }
    }
}

// MARK: - 相机预览

/// 相机预览层（标签预览页 `PreviewView` 已删除，本名字无冲突顾虑）。
struct ScannerCameraView: UIViewRepresentable {
    let session: AVCaptureSession
    /// 取景框边长（用来换算识别区域）。
    var interestSide: CGFloat = 215
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
    var interestSide: CGFloat = 215 {
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

    private let boxSide: CGFloat = 215
    /// 呼吸动画开关（`onAppear` 置 true，让 `.animation` 开始循环）。
    @State private var breathing = false

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
                    // ★★★ 2026-10-18（用户）：**双击预览在 2× ⇄ 4×（长焦）之间切换**。
                    //   只挂 count:2，不动单击 —— 上下方的按钮点击不受影响。
                    .onTapGesture(count: 2) {
                        scanner.toggleTeleZoom()
                    }

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

            // ★ 2026-10-18：显示当前倍率，并告诉用户「双击」这个手动切换方式。
            //   （4× 是长焦档；读不出时会自动切过去，也可以双击自己切。）
            Text(scanner.isTeleZoom ? "4× 长焦 · 双击切回 2×" : "2× · 双击切长焦")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 4)

            Spacer()

            controls
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }

    /// 取景框。
    ///
    /// ★★★ 2026-10-19（用户）：「apple 有个扫码器 app，扫码界面的这个方形要和它一致，
    ///   他的是**会呼吸的**，可以直接调用吗？」
    ///   ➜ **不能直接调用** —— 系统没有公开"扫码框"组件，扫码器 App 的框是它自己画的。
    ///   ➜ 但可以 100% 用第一方做出来：**SF Symbols 的 `viewfinder`**（系统的取景框图形）
    ///     + **`.symbolEffect(.pulse, options: .repeating)`**（系统的符号脉动动画，就是"呼吸"）。
    ///   ➜ 原来的 `CornerBrackets`（自绘 Path 四角）+ `ScanLine`（自绘扫描线）已停用 ——
    ///     扫码器的框**没有扫描线**，呼吸感来自框本身的脉动。
    /// 取景框 —— **苹果「扫码器」同款：四个 L 形角 + 呼吸**。
    ///
    /// ★★★ 2026-10-19（用户：「我要一模一样」）：
    ///   系统没有公开"扫码框"组件（`viewfinder` 符号是完整方框，形状不对），
    ///   所以形状必须自己画四个 L 形角（`CornerBrackets`）；
    ///   但**呼吸动画本身用系统动画 API**：
    ///     `.scaleEffect` + `.animation(.easeInOut.repeatForever(autoreverses:))`
    ///   —— 不是 Timer 手搓，也不是第三方库。
    ///   ➜ 表现：框整体缓慢放大到 1.05 并变实（0.72 → 1.0），再回到原位，无限循环。
    private var viewfinder: some View {
        CornerBrackets(side: boxSide)
            .frame(width: boxSide, height: boxSide)
            // ★ 2026-10-19（用户）：「增加呼吸幅度和速度」
            //   幅度 1.05→**1.10**、透明度 0.72→**0.55**、单程 1.7s→**1.1s**。
            .scaleEffect(breathing ? 1.10 : 1.0)
            .opacity(breathing ? 1.0 : 0.55)
            // ★ 2026-10-19（用户二次）：呼吸**还是慢** → 单程 1.1s 再压到 **0.65s**
            //   （往返 1.3 秒，接近系统"呼吸"类动效的节奏）。
            //   还嫌慢就继续压到 0.5s（再快会像闪烁、不像呼吸）。
            .animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true),
                       value: breathing)
            .onAppear { breathing = true }
    }

    /// 扫码页底部两个浮层按钮。
    ///
    /// ★★★ 2026-10-18 **最终铁律（第四次被纠正后定的，别再动）**：
    ///   按钮**只能用苹果第一方的 `.liquidGlassButton()`**（= `.buttonStyle(.glass)`）。
    ///   ❌ 绝不用 `.buttonStyle(.plain)` + `.background(...)` 自己拼一个胶囊 ——
    ///     哪怕底是 `.regularMaterial` 这种系统材质也不行
    ///     （用户原话：「按钮怎么又变成你自己写的了？不是要苹果第一方吗？怎么反反复复的」）。
    ///   ✅ **能调的只有文字/图标的颜色**：
    ///     · 常态 → `Color.primary`（浅色模式黑 / 深色模式白，与 TabBar 的图标色一致）；
    ///     · 开手电筒 → `Theme.brand`（#007AFF，与 TabBar 选中色同一个系统蓝）。
    ///   ⚠️ 玻璃的**底色**由系统渲染（会透出背后的画面），这是第一方的行为，改不了也不该改。
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                scanner.toggleTorch()
            } label: {
                Label(scanner.torchOn ? "关闭手电筒" : "打开手电筒",
                      systemImage: scanner.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    // ★ 只改文字颜色：常态跟明暗（= TabBar 图标色）；开手电筒 = TabBar 选中蓝。
                    .foregroundStyle(scanner.torchOn ? Theme.brand : Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    // ★★★ 2026-10-18（用户第 4 条）：**两个按钮左右对称（等宽）**。
                    //   `maxWidth: .infinity` 让 label 撑满 HStack 分到的一半，
                    //   系统玻璃胶囊随之拉成同宽（"打开手电筒"5 字 vs "翻转"2 字不再一长一短）。
                    .frame(maxWidth: .infinity)
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
                        .fontWeight(.medium)
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
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
    /// ★★★ 2026-10-19（用户二次纠正）：
    ///   「弧度太小了，我不是让你仿照**苹果屏幕的大 R 角**来设计吗？
    ///    我说的是**硬件屏幕的 R 角**，不是 App 里磁贴的 R 角」
    ///   ➜ iPhone 硬件屏幕 R 角 ≈ **55pt**，屏幕宽 393pt → 比例 **14%**。
    ///     取景框 250pt 按同一比例 → 圆弧半径 **35pt**。
    ///   ➜ 半径 35 必须小于角长，所以角长从 30 加长到 **52**（弧占 67%、直线段 17），
    ///     视觉上就是"整个角大部分是圆弧"—— 和屏幕边角一个感觉。
    ///   ⚠️ 三个参数一起调才有意义：`cornerRadius` 不能 ≥ `length`。
    private let length: CGFloat = 46
    private let thickness: CGFloat = 6
    private let cornerRadius: CGFloat = 38

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
            // ★ 圆弧拐角：竖边 → 圆弧（控制点=直角顶点）→ 横边
            let r = min(cornerRadius, length * 0.85)
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addQuadCurve(to: CGPoint(x: r, y: 0),
                              control: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: length, y: 0))
        }
        // ★ 2026-10-19：扫码器的四个角是**纯白**（原来是品牌浅蓝）。
        .stroke(.white, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
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
