//
//  FaceUnlockController.swift
//  NotchLand
//
//  Local, convenience-grade face unlock for NotchLand private widgets. RGB
//  camera matching is never treated as a macOS credential: enrollment starts
//  after LocalAuthentication, templates stay device-only in Keychain, and
//  sensitive/system operations retain Apple's authentication fallback.
//

@preconcurrency import AVFoundation
@preconcurrency import Vision
import AppKit
import Combine
import CoreImage
import Foundation
import Security

nonisolated enum FaceUnlockChallenge: String, Codable, Equatable, Sendable {
    case center
    case turnLeft
    case turnRight

    var instruction: String {
        switch self {
        case .center: "Look directly at the camera"
        case .turnLeft: "Slowly turn your head left"
        case .turnRight: "Slowly turn your head right"
        }
    }
}

nonisolated enum FaceUnlockState: Equatable, Sendable {
    case idle
    case requestingCamera
    case enrolling(step: Int, total: Int, challenge: FaceUnlockChallenge)
    case scanning(challenge: FaceUnlockChallenge)
    case success
    case failed(String)
    case denied

    var isCameraActive: Bool {
        switch self {
        case .requestingCamera, .enrolling, .scanning: true
        case .idle, .success, .failed, .denied: false
        }
    }
}

private nonisolated struct FaceFeatureSample: Sendable {
    let featureData: Data
    let yaw: Double
    let quality: Float
}

private final class FaceCaptureWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.rudrashah.NotchLand.face-unlock", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var configured = false
    private var frameCounter = 0
    private var handler: (@Sendable (FaceFeatureSample) -> Void)?

    func start(handler: @escaping @Sendable (FaceFeatureSample) -> Void) async throws {
        self.handler = handler
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if !configured { try configure() }
                    if !session.isRunning { session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        handler = nil
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if session.isRunning { session.stopRunning() }
                continuation.resume()
            }
        }
    }

    private func configure() throws {
        guard let camera = AVCaptureDevice.default(for: .video) else {
            throw FaceUnlockError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: camera)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .medium
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw FaceUnlockError.cameraUnavailable
        }
        session.addInput(input)
        session.addOutput(output)
        configured = true
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCounter &+= 1
        guard frameCounter.isMultiple(of: 6),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let sample = try? makeSample(pixelBuffer: pixelBuffer) else { return }
        handler?(sample)
    }

    private func makeSample(pixelBuffer: CVPixelBuffer) throws -> FaceFeatureSample {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .upMirrored)
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        try handler.perform([landmarksRequest])
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        qualityRequest.inputFaceObservations = landmarksRequest.results
        try handler.perform([qualityRequest])
        guard let face = qualityRequest.results?.max(by: {
            ($0.__faceCaptureQuality?.floatValue ?? 0) < ($1.__faceCaptureQuality?.floatValue ?? 0)
        }), let quality = face.__faceCaptureQuality?.floatValue else {
            throw FaceUnlockError.faceNotFound
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.upMirrored)
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        var rect = VNImageRectForNormalizedRect(face.boundingBox, width, height)
        rect = rect.insetBy(dx: -rect.width * 0.16, dy: -rect.height * 0.16)
            .intersection(image.extent)
        guard rect.width > 40, rect.height > 40,
              let cgImage = context.createCGImage(image.cropped(to: rect), from: rect) else {
            throw FaceUnlockError.faceNotFound
        }

        let featureRequest = VNGenerateImageFeaturePrintRequest()
        try VNImageRequestHandler(cgImage: cgImage).perform([featureRequest])
        guard let feature = featureRequest.results?.first else {
            throw FaceUnlockError.featureUnavailable
        }
        let data = try NSKeyedArchiver.archivedData(withRootObject: feature, requiringSecureCoding: true)
        return FaceFeatureSample(
            featureData: data,
            yaw: face.yaw?.doubleValue ?? 0,
            quality: quality
        )
    }
}

private nonisolated enum FaceUnlockError: LocalizedError {
    case cameraUnavailable
    case faceNotFound
    case featureUnavailable
    case templateUnavailable
    case matchFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: "Camera is unavailable."
        case .faceNotFound: "Keep one well-lit face inside the frame."
        case .featureUnavailable: "A face template could not be generated."
        case .templateUnavailable: "Enroll your face before using Face Unlock."
        case .matchFailed: "Face did not match the enrolled profile."
        }
    }
}

private nonisolated struct StoredFaceProfile: Codable, Sendable {
    let templates: [Data]
    let threshold: Float
}

private nonisolated enum FaceProfileStore {
    static let service = "com.rudrashah.NotchLand.face-unlock"
    static let account = "primary-profile-v1"

    static func save(_ profile: StoredFaceProfile) throws {
        let data = try PropertyListEncoder().encode(profile)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            attributes.forEach { insertion[$0.key] = $0.value }
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
                throw FaceUnlockError.templateUnavailable
            }
        } else if status != errSecSuccess {
            throw FaceUnlockError.templateUnavailable
        }
    }

    static func load() -> StoredFaceProfile? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? PropertyListDecoder().decode(StoredFaceProfile.self, from: data)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class FaceUnlockController: ObservableObject {
    private enum Mode {
        case enrollment
        case unlock(challenge: FaceUnlockChallenge, matched: Bool)
    }

    @Published private(set) var state: FaceUnlockState = .idle
    @Published private(set) var isEnrolled = FaceProfileStore.load() != nil
    @Published private(set) var failedAttempts = 0

    let session: AVCaptureSession

    private static let minimumQuality: Float = 0.34
    private static let yawThreshold = 0.13
    private static let maximumAttempts = 3
    private let worker: FaceCaptureWorker
    private let biometrics: BiometricAuthenticationController
    private var mode: Mode?
    private var enrollmentTemplates: [Data] = []
    private var enrollmentStep = 0
    private var sessionMismatchSamples = 0
    private let enrollmentChallenges: [FaceUnlockChallenge] = [
        .center, .turnLeft, .turnRight, .center, .center,
    ]

    init(biometrics: BiometricAuthenticationController) {
        self.biometrics = biometrics
        let worker = FaceCaptureWorker()
        self.worker = worker
        session = worker.session
    }

    func beginEnrollment() async {
        guard await biometrics.authenticate() else {
            state = .failed("System authentication is required before enrollment.")
            return
        }
        enrollmentTemplates = []
        enrollmentStep = 0
        mode = .enrollment
        await startCamera(state: .enrolling(step: 1, total: enrollmentChallenges.count, challenge: .center))
    }

    func beginUnlock() async {
        guard failedAttempts < Self.maximumAttempts else {
            state = .failed("Too many attempts. Use system authentication.")
            return
        }
        guard FaceProfileStore.load() != nil else {
            state = .failed(FaceUnlockError.templateUnavailable.localizedDescription)
            return
        }
        let challenge: FaceUnlockChallenge = Bool.random() ? .turnLeft : .turnRight
        sessionMismatchSamples = 0
        mode = .unlock(challenge: challenge, matched: false)
        await startCamera(state: .scanning(challenge: .center))
    }

    func cancel() {
        mode = nil
        state = .idle
        Task { await worker.stop() }
    }

    func deleteEnrollment() {
        cancel()
        FaceProfileStore.delete()
        enrollmentTemplates = []
        isEnrolled = false
        failedAttempts = 0
    }

    func resetAfterSystemAuthentication() {
        failedAttempts = 0
        state = .idle
    }

    private func startCamera(state nextState: FaceUnlockState) async {
        state = .requestingCamera
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        if authorization == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        } else {
            granted = authorization == .authorized
        }
        guard granted else {
            state = .denied
            return
        }

        do {
            try await worker.start { [weak self] sample in
                Task { @MainActor [weak self] in self?.consume(sample) }
            }
            state = nextState
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func consume(_ sample: FaceFeatureSample) {
        guard sample.quality >= Self.minimumQuality else { return }
        switch mode {
        case .enrollment:
            consumeEnrollment(sample)
        case let .unlock(challenge, matched):
            consumeUnlock(sample, challenge: challenge, matched: matched)
        case nil:
            break
        }
    }

    private func consumeEnrollment(_ sample: FaceFeatureSample) {
        let challenge = enrollmentChallenges[enrollmentStep]
        guard satisfies(challenge, yaw: sample.yaw) else { return }
        if challenge == .center { enrollmentTemplates.append(sample.featureData) }
        enrollmentStep += 1

        guard enrollmentStep < enrollmentChallenges.count else {
            finishEnrollment()
            return
        }
        state = .enrolling(
            step: enrollmentStep + 1,
            total: enrollmentChallenges.count,
            challenge: enrollmentChallenges[enrollmentStep]
        )
    }

    private func finishEnrollment() {
        guard enrollmentTemplates.count >= 3 else {
            fail(FaceUnlockError.featureUnavailable)
            return
        }
        do {
            let threshold = try calibratedThreshold(for: enrollmentTemplates)
            try FaceProfileStore.save(StoredFaceProfile(templates: enrollmentTemplates, threshold: threshold))
            isEnrolled = true
            failedAttempts = 0
            state = .success
            mode = nil
            Task { await worker.stop() }
            NotchHaptics.perform(.confirmation)
        } catch {
            fail(error)
        }
    }

    private func consumeUnlock(
        _ sample: FaceFeatureSample,
        challenge: FaceUnlockChallenge,
        matched: Bool
    ) {
        if !matched {
            guard satisfies(.center, yaw: sample.yaw), matchesProfile(sample.featureData) else { return }
            mode = .unlock(challenge: challenge, matched: true)
            state = .scanning(challenge: challenge)
            return
        }

        guard satisfies(challenge, yaw: sample.yaw) else { return }
        biometrics.acceptFaceUnlock()
        failedAttempts = 0
        state = .success
        mode = nil
        Task { await worker.stop() }
        NotchHaptics.perform(.confirmation)
    }

    private func matchesProfile(_ candidate: Data) -> Bool {
        guard let profile = FaceProfileStore.load(),
              let observation = decode(candidate) else { return false }
        let distances = profile.templates.compactMap { data -> Float? in
            guard let template = decode(data) else { return nil }
            var distance: Float = 1
            try? observation.computeDistance(&distance, to: template)
            return distance
        }
        guard let minimum = distances.min(), minimum <= profile.threshold else {
            sessionMismatchSamples += 1
            if sessionMismatchSamples >= 5 {
                sessionMismatchSamples = 0
                failedAttempts += 1
                fail(FaceUnlockError.matchFailed)
            }
            return false
        }
        sessionMismatchSamples = 0
        return true
    }

    private func calibratedThreshold(for templates: [Data]) throws -> Float {
        let observations = templates.compactMap(decode)
        guard observations.count == templates.count else { throw FaceUnlockError.featureUnavailable }
        var distances: [Float] = []
        for left in observations.indices {
            for right in observations.indices where right > left {
                var distance: Float = 1
                try observations[left].computeDistance(&distance, to: observations[right])
                distances.append(distance)
            }
        }
        let intraProfileMaximum = distances.max() ?? 0.12
        return min(max(intraProfileMaximum * 1.8, 0.18), 0.34)
    }

    private func decode(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    private func satisfies(_ challenge: FaceUnlockChallenge, yaw: Double) -> Bool {
        switch challenge {
        case .center: abs(yaw) < Self.yawThreshold
        case .turnLeft: yaw > Self.yawThreshold
        case .turnRight: yaw < -Self.yawThreshold
        }
    }

    private func fail(_ error: Error) {
        mode = nil
        state = .failed(error.localizedDescription)
        Task { await worker.stop() }
        NotchHaptics.perform(.rejection)
    }
}
