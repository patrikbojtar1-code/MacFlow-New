//
//  MirrorController.swift
//  NotchLand
//
//  Camera lifecycle and permissions for the Mirror widget. All blocking
//  AVCaptureSession work is kept off the main actor.
//

@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation

enum MirrorAuthorizationState: Equatable {
    case idle
    case requesting
    case ready
    case denied
    case unavailable
    case failed(String)
}

private enum MirrorSessionError: Error {
    case cameraUnavailable
    case inputUnavailable
}

private final class MirrorSessionWorker: @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(
        label: "com.rudrashah.NotchLand.camera-session",
        qos: .userInitiated
    )
    private var isConfigured = false

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if !isConfigured {
                        try configure()
                    }
                    if !session.isRunning {
                        session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    private func configure() throws {
        guard let camera = AVCaptureDevice.default(for: .video) else {
            throw MirrorSessionError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard session.canAddInput(input) else {
            throw MirrorSessionError.inputUnavailable
        }
        session.addInput(input)
        isConfigured = true
    }
}

@MainActor
final class MirrorController: ObservableObject {
    @Published private(set) var state: MirrorAuthorizationState
    @Published private(set) var zoom: Double = 1
    @Published private(set) var maximumZoom: Double = 2.5

    private let worker: MirrorSessionWorker
    private var lifecycleTask: Task<Void, Never>?

    var session: AVCaptureSession { worker.session }

    init() {
        self.worker = MirrorSessionWorker()
        state = Self.authorizationState(for: AVCaptureDevice.authorizationStatus(for: .video))
    }

    func start() {
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            guard let self else { return }

            let authorization = AVCaptureDevice.authorizationStatus(for: .video)
            if authorization == .notDetermined {
                state = .requesting
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard !Task.isCancelled else { return }
                if !granted {
                    state = .denied
                    return
                }
            } else if authorization == .denied || authorization == .restricted {
                state = .denied
                return
            }

            do {
                try await worker.start()
                guard !Task.isCancelled else {
                    await worker.stop()
                    return
                }
                state = .ready
            } catch MirrorSessionError.cameraUnavailable {
                state = .unavailable
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func stop() {
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            await worker.stop()
            if state == .ready { state = .idle }
        }
    }

    func setZoom(_ value: Double) {
        let requested = Self.clampedZoom(value, maximum: maximumZoom)
        zoom = requested
    }

    func openCameraPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    nonisolated static func authorizationState(
        for status: AVAuthorizationStatus
    ) -> MirrorAuthorizationState {
        switch status {
        case .authorized: .idle
        case .notDetermined: .idle
        case .denied, .restricted: .denied
        @unknown default: .unavailable
        }
    }

    nonisolated static func clampedZoom(_ value: Double, maximum: Double) -> Double {
        min(max(value, 1), max(maximum, 1))
    }
}
