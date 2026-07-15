//
//  MirrorView.swift
//  NotchLand
//

@preconcurrency import AVFoundation
import AppKit
import SwiftUI

private final class MirrorPreviewNSView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer
    private var zoom: Double = 1

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
        previewLayer.setAffineTransform(
            CGAffineTransform(scaleX: zoom, y: zoom)
        )
        if let connection = previewLayer.connection,
           connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        CATransaction.commit()
    }

    func updateZoom(_ value: Double) {
        zoom = value
        needsLayout = true
    }
}

private struct MirrorCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let zoom: Double

    func makeNSView(context: Context) -> MirrorPreviewNSView {
        let view = MirrorPreviewNSView(session: session)
        view.updateZoom(zoom)
        return view
    }

    func updateNSView(_ nsView: MirrorPreviewNSView, context: Context) {
        nsView.previewLayer.session = session
        nsView.updateZoom(zoom)
    }
}

struct MirrorView: View {
    @EnvironmentObject private var mirror: MirrorController

    var body: some View {
        Group {
            switch mirror.state {
            case .ready:
                cameraSurface
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            case .requesting:
                statusView(
                    symbol: "video.badge.ellipsis",
                    title: "Requesting Camera Access",
                    detail: "Approve the macOS permission to start Mirror"
                )
            case .denied:
                deniedView
            case .unavailable:
                statusView(
                    symbol: "video.slash.fill",
                    title: "Camera Unavailable",
                    detail: "Connect a camera and reopen Mirror"
                )
            case let .failed(message):
                statusView(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Mirror Couldn’t Start",
                    detail: message
                )
            case .idle:
                statusView(
                    symbol: "video.fill",
                    title: "Starting Mirror",
                    detail: "Preparing your camera securely"
                )
            }
        }
        .animation(NotchMotion.contentOpen, value: mirror.state)
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { mirror.start() }
        .onDisappear { mirror.stop() }
    }

    private var cameraSurface: some View {
        ZStack(alignment: .bottom) {
            MirrorCameraPreview(session: mirror.session, zoom: mirror.zoom)
                .animation(NotchMotion.selection, value: mirror.zoom)
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.42)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }

            HStack(spacing: 10) {
                Label("Mirror", systemImage: "video.fill")
                    .font(.system(size: 10, weight: .bold, design: .rounded))

                Spacer()

                if mirror.maximumZoom > 1.01 {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 9, weight: .semibold))
                    Slider(
                        value: Binding(
                            get: { mirror.zoom },
                            set: mirror.setZoom
                        ),
                        in: 1...mirror.maximumZoom
                    )
                    .controlSize(.mini)
                    .frame(width: 105)
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 12, y: 6)
    }

    private var deniedView: some View {
        VStack(spacing: 10) {
            statusView(
                symbol: "video.slash.fill",
                title: "Camera Access Is Off",
                detail: "Enable NotchLand in Privacy & Security → Camera"
            )
            Button("Open Camera Settings") {
                mirror.openCameraPrivacySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func statusView(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(.cyan)
                .symbolEffect(.pulse, options: .repeating, isActive: mirror.state == .requesting)
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(detail)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
