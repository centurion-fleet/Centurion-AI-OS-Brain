import AVFoundation
import SwiftUI
import Vision

/// Full-screen camera preview that scans a Centurion remote pairing QR
/// (`token:…@host:port`) and auto-pairs on successful decode.
struct QRScannerView: View {
    var onCode: (String) -> Void
    var onCancel: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            QRScannerRepresentable(
                onCode: { code in
                    onCode(code)
                },
                onError: { message in
                    errorMessage = message
                }
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: 260, height: 260)
                    .padding(.bottom, 24)

                Text("Point camera at the QR code on your Centurion's screen")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .shadow(radius: 4)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(ColorTheme.warning())
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
                .foregroundStyle(.white)
                .padding(.bottom, 40)
            }
        }
        .background(Color.black)
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCode = onCode
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        uiViewController.onCode = onCode
        uiViewController.onError = onError
    }
}

final class QRScannerViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didEmit = false
    private let visionQueue = DispatchQueue(label: "com.centurion.ios.qr-scan")
    private var isRunning = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func configureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                        self?.startSession()
                    } else {
                        self?.onError?("Camera access is required to scan the pairing QR code.")
                    }
                }
            }
        default:
            onError?("Camera access is required to scan the pairing QR code. Enable it in Settings.")
        }
    }

    private func setupCamera() {
        guard previewLayer == nil else { return }
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onError?("Could not open the camera.")
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: visionQueue)
        guard session.canAddOutput(output) else {
            onError?("Could not start the camera scanner.")
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
    }

    private func startSession() {
        guard !isRunning, previewLayer != nil else { return }
        visionQueue.async { [weak self] in
            self?.session.startRunning()
            self?.isRunning = true
        }
    }

    private func stopSession() {
        guard isRunning else { return }
        visionQueue.async { [weak self] in
            self?.session.stopRunning()
            self?.isRunning = false
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !didEmit,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self, !self.didEmit else { return }
            if let error {
                DispatchQueue.main.async {
                    self.onError?("Scanner error: \(error.localizedDescription)")
                }
                return
            }
            let payloads = (request.results as? [VNBarcodeObservation])?
                .compactMap { $0.payloadStringValue } ?? []
            for payload in payloads {
                let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                if RemoteConnectionString.parse(trimmed) != nil {
                    self.didEmit = true
                    DispatchQueue.main.async {
                        self.onCode?(trimmed)
                    }
                    return
                }
            }
        }
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
    }
}
