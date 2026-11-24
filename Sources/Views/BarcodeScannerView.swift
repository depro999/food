import SwiftUI
import AVFoundation

/// Pantalla completa de escaneo (códigos de barras y QR) con marco guía.
struct ScannerScreen: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BarcodeScannerView(onCode: onCode)
                .ignoresSafeArea()

            // Marco guía
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.9), lineWidth: 3)
                .frame(width: 280, height: 180)
                .shadow(radius: 8)

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 34))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding()
                }
                Spacer()
                Text("Apunta al código de barras o QR del producto")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 40)
            }
        }
    }
}

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let vc = ScannerController()
        vc.onCode = onCode
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var handled = false

    private let supported: [AVMetadataObject.ObjectType] = [
        .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14, .qr, .dataMatrix
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    guard granted else { return }
                    self.configure()
                    self.startIfNeeded()
                }
            }
        default:
            break
        }
    }

    private func configure() {
        guard session.inputs.isEmpty,
              let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = output.availableMetadataObjectTypes.filter { supported.contains($0) }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
    }

    private func startIfNeeded() {
        guard !session.inputs.isEmpty, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        handled = false
        startIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !handled,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        handled = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(value)
    }
}

/// Extrae un código de producto (8-14 dígitos) de un código de barras o del contenido de un QR
/// (por ejemplo, una URL de producto que incluya el EAN).
func extractProductCode(from payload: String) -> String? {
    let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
    if (8...14).contains(trimmed.count), trimmed.allSatisfy(\.isNumber) { return trimmed }
    guard let regex = try? NSRegularExpression(pattern: "\\d{8,14}") else { return nil }
    let range = NSRange(trimmed.startIndex..., in: trimmed)
    if let m = regex.firstMatch(in: trimmed, range: range), let r = Range(m.range, in: trimmed) {
        return String(trimmed[r])
    }
    return nil
}
