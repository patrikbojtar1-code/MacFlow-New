//
//  BiometricAuthenticationControllerTests.swift
//  NotchLandTests
//

import Testing
@testable import NotchLand

@MainActor
private final class AuthenticationStub: DeviceAuthenticating {
    let reportedCapability: DeviceAuthenticationCapability
    let result: Bool

    init(capability: DeviceAuthenticationCapability = .touchID, result: Bool) {
        reportedCapability = capability
        self.result = result
    }

    func capability() -> DeviceAuthenticationCapability { reportedCapability }
    func authenticate(reason: String) async throws -> Bool { result }
}

@MainActor
struct BiometricAuthenticationControllerTests {
    @Test func successfulAuthenticationRevealsContentUntilRelocked() async {
        let controller = BiometricAuthenticationController(
            authenticator: AuthenticationStub(result: true)
        )

        #expect(controller.capability == .touchID)
        #expect(await controller.authenticate())
        #expect(controller.isAuthenticated)

        controller.lock()
        #expect(!controller.isAuthenticated)
    }

    @Test func failedAuthenticationKeepsShieldLocked() async {
        let controller = BiometricAuthenticationController(
            authenticator: AuthenticationStub(result: false)
        )

        #expect(!(await controller.authenticate()))
        #expect(!controller.isAuthenticated)
        #expect(controller.errorMessage != nil)
    }

    @Test func sensitiveWidgetClassificationDoesNotBlockMediaControls() {
        #expect(NotchWidget.wallet.containsPrivateContent)
        #expect(NotchWidget.clipboard.containsPrivateContent)
        #expect(NotchWidget.timeline.containsPrivateContent)
        #expect(!NotchWidget.media.containsPrivateContent)
        #expect(!NotchWidget.timer.containsPrivateContent)
    }
}
