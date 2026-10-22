import SwiftUI
import AVFoundation
import UIKit

struct QRScannerView: UIViewControllerRepresentable {
    let completion: (Result<String, Error>) -> Void
    func makeUIViewController(context: Context) -> QRScannerController { QRScannerController(completion: completion) }
    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: QRScannerController, coordinator: ()) { uiViewController.stop() }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let capture = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "dev.nivqo.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var finished = false
    private var active = true
    private let completion: (Result<String, Error>) -> Void
    init(completion: @escaping (Result<String, Error>) -> Void) { self.completion = completion; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use the programmatic initializer") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in DispatchQueue.main.async {
                guard let self = self, self.active else { return }
                if allowed { self.configure() } else { self.finish(.failure(FlowError.invalid("Camera access is disabled. You can paste the pairing code instead."))) }
            } }
        default: finish(.failure(FlowError.invalid("Camera access is disabled. Enable it in iPhone Settings or paste a pairing code.")))
        }
    }
    private func configure() {
        do {
            guard active, let camera = AVCaptureDevice.default(for: .video) else { throw FlowError.invalid("No camera is available. Paste a pairing code instead.") }
            let input = try AVCaptureDeviceInput(device: camera)
            let output = AVCaptureMetadataOutput()
            guard capture.canAddInput(input), capture.canAddOutput(output) else { throw FlowError.invalid("The camera cannot scan QR codes on this device.") }
            capture.addInput(input); capture.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            guard output.availableMetadataObjectTypes.contains(.qr) else { throw FlowError.invalid("QR scanning is unavailable.") }
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: capture); layer.videoGravity = .resizeAspectFill; layer.frame = view.bounds
            preview = layer; view.layer.insertSublayer(layer, at: 0)
            let hint = UILabel(); hint.text = "Point at the NIVQO pairing QR on your computer"; hint.textColor = .white; hint.backgroundColor = UIColor.black.withAlphaComponent(0.7)
            hint.numberOfLines = 0; hint.textAlignment = .center; hint.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(hint)
            NSLayoutConstraint.activate([hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30), hint.heightAnchor.constraint(greaterThanOrEqualToConstant: 70)])
            captureQueue.async { [capture] in capture.startRunning() }
        } catch { finish(.failure(error)) }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        finish(.success(code))
    }
    private func finish(_ result: Result<String, Error>) { guard active, !finished else { return }; finished = true; stop(); completion(result) }
    func stop() { active = false; captureQueue.async { [capture] in if capture.isRunning { capture.stopRunning() } } }
}
