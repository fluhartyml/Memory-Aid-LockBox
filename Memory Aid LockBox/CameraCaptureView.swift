//
//  CameraCaptureView.swift
//  Memory Aid LockBox
//
//  Rear/front camera photo capture via AVCaptureSession. Replaces the old
//  UIImagePickerController implementation, which on iOS 27 / 16-series hardware
//  presents the camera but never delivers the captured photo back to the app —
//  the same failure that forced SelfieCaptureView off UIImagePickerController.
//  Public API is unchanged, so every caller (journal header, note/receipt/contact
//  attachments) is fixed without edits.
//

#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit

struct CameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    var preferFrontCamera: Bool = false
    var onCapture: (Data) -> Void

    @State private var camera = CaptureCamera()
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        camera.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 34))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .padding()
                    }
                    Spacer()
                }

                Spacer()

                Text("Take a photo")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)

                Button {
                    guard !isCapturing else { return }
                    isCapturing = true
                    camera.capture { data in
                        if let data { onCapture(data) }
                        camera.stop()
                        dismiss()
                    }
                } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 84, height: 84)
                        Circle().fill(.white).frame(width: 70, height: 70)
                    }
                }
                .disabled(isCapturing)
                .padding(.bottom, 44)
            }
        }
        .task { await camera.start(front: preferFrontCamera) }
        .onDisappear { camera.stop() }
    }
}

/// Owns the AVCaptureSession. Session start/stop and capture run off the main
/// thread; results are delivered back on main.
@Observable
final class CaptureCamera {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.nightgard.lockbox.camera")
    private var configured = false
    private var delegate: CameraPhotoDelegate?

    func start(front: Bool) async {
        guard await ensureAuthorized() else { return }
        queue.async { [self] in
            configureIfNeeded(front: front)
            if !session.isRunning { session.startRunning() }
        }
    }

    private func ensureAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func configureIfNeeded(front: Bool) {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        let position: AVCaptureDevice.Position = front ? .front : .back
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = true
    }

    func capture(completion: @escaping (Data?) -> Void) {
        queue.async { [self] in
            guard session.isRunning else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let settings = AVCapturePhotoSettings()
            let handler = CameraPhotoDelegate { data in
                DispatchQueue.main.async { completion(data) }
            }
            delegate = handler   // retained until the callback fires
            output.capturePhoto(with: settings, delegate: handler)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

private final class CameraPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?) -> Void
    init(completion: @escaping (Data?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        // fileDataRepresentation() carries orientation EXIF, so UIImage(data:)
        // renders it upright. Re-encode to JPEG to match the app's other captures.
        let data = photo.fileDataRepresentation()
            .flatMap { UIImage(data: $0)?.jpegData(compressionQuality: 0.8) }
            ?? photo.fileDataRepresentation()
        completion(data)
    }
}

/// A UIView backed by AVCaptureVideoPreviewLayer showing the live camera feed.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
#endif
