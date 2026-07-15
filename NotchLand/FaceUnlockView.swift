//
//  FaceUnlockView.swift
//  NotchLand
//

@preconcurrency import AVFoundation
import AppKit
import SwiftUI

final class FaceCameraPreviewNSView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        if let connection = previewLayer.connection,
           connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        CATransaction.commit()
    }
}

struct FaceCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> FaceCameraPreviewNSView {
        FaceCameraPreviewNSView(session: session)
    }

    func updateNSView(_ nsView: FaceCameraPreviewNSView, context: Context) {
        nsView.previewLayer.session = session
    }
}

struct FaceEnrollmentView: View {
    @EnvironmentObject private var faceUnlock: FaceUnlockController
    @EnvironmentObject private var settings: NotchSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                FaceCameraPreview(session: faceUnlock.session)
                    .frame(width: 250, height: 250)
                    .clipShape(Circle())
                Circle()
                    .strokeBorder(borderColor, lineWidth: 3)
                    .frame(width: 250, height: 250)
                faceGuide
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)
            }

            HStack(spacing: 10) {
                Button("Cancel") {
                    faceUnlock.cancel()
                    dismiss()
                }
                .buttonStyle(.bordered)

                if faceUnlock.state == .success {
                    Button("Done") {
                        settings.faceUnlockEnabled = true
                        faceUnlock.cancel()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else if case .failed = faceUnlock.state {
                    Button("Try Again") {
                        Task { await faceUnlock.beginEnrollment() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(28)
        .frame(width: 430, height: 410)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var faceGuide: some View {
        if !faceUnlock.state.isCameraActive {
            Image(systemName: faceUnlock.state == .success ? "checkmark" : "faceid")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(faceUnlock.state == .success ? .green : .white.opacity(0.75))
        }
    }

    private var borderColor: Color {
        faceUnlock.state == .success ? .green : .white.opacity(0.3)
    }

    private var title: String {
        switch faceUnlock.state {
        case .idle: "Face Unlock"
        case .requestingCamera: "Preparing Camera"
        case let .enrolling(step, total, _): "Enrollment \(step) of \(total)"
        case .scanning: "Checking Liveness"
        case .success: "Face Enrolled"
        case .failed: "Enrollment Failed"
        case .denied: "Camera Access Required"
        }
    }

    private var detail: String {
        switch faceUnlock.state {
        case .idle: "System authentication will be required before enrollment."
        case .requestingCamera: "Camera frames stay in memory and are never uploaded."
        case let .enrolling(_, _, challenge), let .scanning(challenge): challenge.instruction
        case .success: "Only encrypted mathematical templates were stored in this Mac's device-only Keychain."
        case let .failed(message): message
        case .denied: "Enable NotchLand in Privacy & Security → Camera."
        }
    }
}
