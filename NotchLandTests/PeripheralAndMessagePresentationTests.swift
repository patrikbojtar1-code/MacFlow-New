import Testing
@testable import NotchLand

struct PeripheralAndMessagePresentationTests {
    @Test func recognizesAirPodsModelsFromCoreAudioNames() {
        #expect(AudioAccessoryModel.detect(from: "Patrik’s AirPods Max") == .airPodsMax)
        #expect(AudioAccessoryModel.detect(from: "AirPods Pro") == .airPodsPro)
        #expect(AudioAccessoryModel.detect(from: "AirPods 3") == .airPods3)
        #expect(AudioAccessoryModel.detect(from: "AirPods") == .airPods2)
    }

    @Test func messageClassifierRejectsUnrelatedNotifications() {
        #expect(SystemMessageWindowClassifier.classify(textValues: ["Calendar", "Meeting in 10 minutes"]) == nil)
    }

    @Test func messageClassifierExtractsSenderAndBody() {
        let result = SystemMessageWindowClassifier.classify(
            textValues: ["Messages", "Saša", "Dorazím za pět minut"]
        )
        #expect(result?.sender == "Saša")
        #expect(result?.body == "Dorazím za pět minut")
    }

    @Test func messageFingerprintCanAppearAgainAfterBannerDisappears() {
        var gate = SystemMessageFingerprintGate(missingSnapshotLimit: 2)

        let firstAppearance = gate.shouldPublish("Saša|Dorazím")
        let duplicateAppearance = gate.shouldPublish("Saša|Dorazím")
        let firstMissingSnapshot = gate.shouldPublish(nil)
        let secondMissingSnapshot = gate.shouldPublish(nil)
        let repeatedAppearance = gate.shouldPublish("Saša|Dorazím")

        #expect(firstAppearance)
        #expect(!duplicateAppearance)
        #expect(!firstMissingSnapshot)
        #expect(!secondMissingSnapshot)
        #expect(repeatedAppearance)
    }

    @Test func accessibilityScannerUsesAdaptiveCadence() {
        #expect(SystemActivityScanCadence.interval(isAvailable: false, containsActivity: false) == 2.0)
        #expect(SystemActivityScanCadence.interval(isAvailable: true, containsActivity: false) == 0.8)
        #expect(SystemActivityScanCadence.interval(isAvailable: true, containsActivity: true) == 0.3)
    }
}
