import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}
}

class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var scanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showError()
            return
        }

        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        // Overlay — scan area indicator
        let overlay = UIView(frame: CGRect(x: 0, y: 0, width: 250, height: 250))
        overlay.center = view.center
        overlay.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
        overlay.layer.borderWidth = 2
        overlay.layer.cornerRadius = 16
        overlay.backgroundColor = .clear
        view.addSubview(overlay)

        // Label
        let label = UILabel()
        label.text = "Naskenuj QR kód z Mac obrazovky"
        label.textColor = .white.withAlphaComponent(0.7)
        label.font = .systemFont(ofSize: 14, weight: .light)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60)
        ])

        // Close button
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = .white.withAlphaComponent(0.7)
        close.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            close.widthAnchor.constraint(equalToConstant: 36),
            close.heightAnchor.constraint(equalToConstant: 36)
        ])

        captureSession = session
        DispatchQueue.global(qos: .background).async {
            session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !scanned,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        scanned = true
        captureSession?.stopRunning()
        // Haptic
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        dismiss(animated: true) {
            self.onScan?(value)
        }
    }

    @objc private func dismissSelf() {
        captureSession?.stopRunning()
        dismiss(animated: true)
    }

    private func showError() {
        let label = UILabel()
        label.text = "Kamera není dostupná"
        label.textColor = .white
        label.textAlignment = .center
        label.frame = view.bounds
        view.addSubview(label)
    }
}
