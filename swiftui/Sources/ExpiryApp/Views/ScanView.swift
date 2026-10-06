//
//  ScanView.swift
//  扫码 —— AVFoundation 实时二维码识别。
//
//  用途：扫「康普茶一发」标签上的二维码，取回制备/完成/最佳使用时间，
//  直接进入「二发」填写页（只需再填水果），避免手抄日期。
//
//  ★ 二维码内容就是标签页面文字顺序拼接的结果，解析规则在
//    `LabelTemplate.parseKombuchaQr`，与安卓/Flutter 版完全一致。
//

import AVFoundation
import SwiftUI
import UIKit

/// 扫码 Tab 的二级页路由。
enum ScanRoute: Hashable {
    case secondFermentation(KombuchaFirstLabel)
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

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.xiaoqi.expiry.scanner")
    private var isConfigured = false
    private var isHandling = false
    private var device: AVCaptureDevice?

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
            DispatchQueue.main.async {
                if self.state != .running { self.state = .running }
            }
        }
    }

    private func configure() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            DispatchQueue.main.async { self.state = .failed("无法访问摄像头，请确认设备有可用相机") }
            return
        }

        device = camera

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
        guard let device, device.hasTorch, device.torchMode == .on else { return }
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

/// 注意：名字不要叫 `PreviewView` —— 那个名字已被标签预览页占用。
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
    @State private var invalidText = ""
    @State private var invalidRaw = ""

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
            .alert("这不是康普茶一发标签", isPresented: $showInvalidAlert) {
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

            Text("将一发标签上的二维码放入框内")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 18)

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
        HStack(spacing: 14) {
            Button {
                scanner.toggleTorch()
            } label: {
                Label(scanner.torchOn ? "关闭手电筒" : "打开手电筒",
                      systemImage: scanner.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .liquidGlassButton()
            .disabled(!scanner.state.isRunning)

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

        if let first = LabelTemplate.parseKombuchaQr(code) {
            path.append(ScanRoute.secondFermentation(first))
            return
        }

        invalidRaw = code
        invalidText = "识别到的内容：\n\(code.prefix(160))\n\n请扫描「康普茶」模板生成的标签二维码。"
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
