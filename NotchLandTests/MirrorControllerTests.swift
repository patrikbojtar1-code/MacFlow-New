//
//  MirrorControllerTests.swift
//  NotchLandTests
//

import AVFoundation
import Testing
@testable import NotchLand

struct MirrorControllerTests {
    @Test func deniedAndRestrictedPermissionsMapToDeniedState() {
        #expect(MirrorController.authorizationState(for: .denied) == .denied)
        #expect(MirrorController.authorizationState(for: .restricted) == .denied)
    }

    @Test func authorizedAndUndeterminedPermissionsStartIdle() {
        #expect(MirrorController.authorizationState(for: .authorized) == .idle)
        #expect(MirrorController.authorizationState(for: .notDetermined) == .idle)
    }

    @Test func digitalZoomClampsToSafeRange() {
        #expect(MirrorController.clampedZoom(0.25, maximum: 2.5) == 1)
        #expect(MirrorController.clampedZoom(1.75, maximum: 2.5) == 1.75)
        #expect(MirrorController.clampedZoom(8, maximum: 2.5) == 2.5)
    }

    @Test func invalidMaximumStillProducesUnityZoom() {
        #expect(MirrorController.clampedZoom(2, maximum: 0) == 1)
    }
}

