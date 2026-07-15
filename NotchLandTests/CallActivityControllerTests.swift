//
//  CallActivityControllerTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct CallActivityControllerTests {
    @Test func classifiesCzechIPhoneContinuityBannerFromScreenshot() {
        let result = SystemCallWindowClassifier.classify(
            textValues: ["Saša", "Z vašeho iPhonu"],
            buttonLabels: ["Přijmout", "Odmítnout", "Více"],
            ownerName: "NotificationCenter"
        )

        #expect(result?.callerName == "Saša")
        #expect(result?.serviceName == "iPhone Continuity")
        #expect(result?.answerButtonIndex == 0)
        #expect(result?.declineButtonIndex == 1)
    }

    @Test func ignoresUnrelatedSystemNotification() {
        let result = SystemCallWindowClassifier.classify(
            textValues: ["Calendar", "Stand-up starts in 10 minutes"],
            buttonLabels: ["Snooze", "Close"],
            ownerName: "NotificationCenter"
        )

        #expect(result == nil)
    }

    @Test func incomingCallNormalizesEmptyMetadata() {
        let calls = CallActivityController()

        calls.receiveIncoming(callerName: "  ", serviceName: "")

        #expect(calls.current?.callerName == "Unknown Caller")
        #expect(calls.current?.serviceName == "Incoming Call")
        #expect(calls.current?.phase == .incoming)
        #expect(calls.current?.supportsCallControl == false)
    }

    @Test func callerInitialsUseAtMostTwoNames() {
        let presentation = CallPresentation(
            id: UUID(),
            callerName: "Anna Marie Nováková",
            serviceName: "FaceTime",
            phase: .incoming,
            connectedAt: nil,
            isMuted: false,
            supportsCallControl: true
        )

        #expect(presentation.initials == "AM")
    }

    @Test func answerRunsProviderCallbackAndBecomesActive() async {
        let calls = CallActivityController()
        var didAnswer = false
        calls.receiveIncoming(
            callerName: "Anna",
            serviceName: "Provider",
            supportsCallControl: true,
            onAnswer: { didAnswer = true }
        )

        calls.answer()
        #expect(didAnswer)
        #expect(calls.current?.phase == .connecting)

        try? await Task.sleep(for: .milliseconds(700))

        #expect(calls.current?.phase == .active)
        #expect(calls.current?.connectedAt != nil)
    }

    @Test func uncontrolledCallCannotPretendToAnswer() {
        let calls = CallActivityController()
        calls.receiveIncoming(callerName: "Anna", serviceName: "FaceTime")

        calls.answer()

        #expect(calls.current?.phase == .incoming)
    }

    @Test func declineRunsCallbackAndShowsResult() {
        let calls = CallActivityController()
        var didDecline = false
        calls.receiveIncoming(
            callerName: "Anna",
            serviceName: "Provider",
            supportsCallControl: true,
            onDecline: { didDecline = true }
        )

        calls.decline()

        #expect(didDecline)
        #expect(calls.current?.phase == .ended(reason: "Declined"))
    }

    @Test func activeCallSupportsMuteAndEnd() async {
        let calls = CallActivityController()
        var didEnd = false
        calls.receiveIncoming(
            callerName: "Anna",
            serviceName: "Provider",
            supportsCallControl: true,
            onEnd: { didEnd = true }
        )
        calls.answer()
        try? await Task.sleep(for: .milliseconds(700))

        calls.toggleMute()
        #expect(calls.current?.isMuted == true)

        calls.end()
        #expect(didEnd)
        #expect(calls.current?.phase == .ended(reason: "Call Ended"))
    }
}
