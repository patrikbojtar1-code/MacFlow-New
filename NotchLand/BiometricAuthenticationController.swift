//
//  BiometricAuthenticationController.swift
//  NotchLand
//
//  Privacy Shield uses only Apple's LocalAuthentication result. NotchLand
//  never receives, stores or processes biometric templates.
//

import Combine
import Foundation
import LocalAuthentication

nonisolated enum DeviceAuthenticationCapability: Equatable, Sendable {
    case touchID
    case systemAuthentication
    case unavailable

    var title: String {
        switch self {
        case .touchID: "Touch ID"
        case .systemAuthentication: "Mac Authentication"
        case .unavailable: "Unavailable"
        }
    }

    var symbol: String {
        switch self {
        case .touchID: "touchid"
        case .systemAuthentication: "lock.shield.fill"
        case .unavailable: "lock.slash"
        }
    }
}

@MainActor
protocol DeviceAuthenticating {
    func capability() -> DeviceAuthenticationCapability
    func authenticate(reason: String) async throws -> Bool
}

@MainActor
struct LocalAuthenticationService: DeviceAuthenticating {
    func capability() -> DeviceAuthenticationCapability {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .touchID: return .touchID
            case .faceID, .opticID, .none: break
            @unknown default: break
            }
        }

        error = nil
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            ? .systemAuthentication
            : .unavailable
    }

    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Password"

        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

@MainActor
final class BiometricAuthenticationController: ObservableObject {
    @Published private(set) var capability: DeviceAuthenticationCapability
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var errorMessage: String?

    private let authenticator: any DeviceAuthenticating

    convenience init() {
        self.init(authenticator: LocalAuthenticationService())
    }

    init(authenticator: any DeviceAuthenticating) {
        self.authenticator = authenticator
        capability = authenticator.capability()
    }

    var isAvailable: Bool { capability != .unavailable }

    func refreshCapability() {
        capability = authenticator.capability()
    }

    @discardableResult
    func authenticate() async -> Bool {
        guard !isAuthenticating, isAvailable else { return false }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let success = try await authenticator.authenticate(
                reason: "Unlock private NotchLand widgets"
            )
            isAuthenticated = success
            if !success { errorMessage = "Authentication was not completed." }
            return success
        } catch let error as LAError {
            if error.code != .userCancel && error.code != .appCancel && error.code != .systemCancel {
                errorMessage = error.localizedDescription
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func lock() {
        isAuthenticated = false
        isAuthenticating = false
        errorMessage = nil
    }

}
