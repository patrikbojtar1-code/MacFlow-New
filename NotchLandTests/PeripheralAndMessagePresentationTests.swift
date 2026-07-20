import CoreAudio
import Testing
@testable import NotchLand

@MainActor
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

    @Test func audioOutputControllerPublishesAndSwitchesTheDefaultRoute() async {
        let provider = FakeAudioOutputProvider()
        let settings = NotchSettings()
        let activities = LiveActivityController(settings: settings)
        let controller = AudioDeviceActivitySource(
            activities: activities,
            provider: provider
        )

        controller.refreshOutputs()
        #expect(controller.currentOutput?.id == 1)
        #expect(controller.outputs.count == 2)

        let succeeded = await controller.selectOutput(2)
        #expect(succeeded)
        #expect(provider.selectedDeviceID == 2)
        #expect(controller.currentOutput?.id == 2)
        #expect(controller.selectionState == .idle)
    }

    @Test func audioOutputControllerKeepsFailureVisibleForTheUI() async {
        let provider = FakeAudioOutputProvider()
        provider.selectionError = AudioOutputDeviceError.unavailable
        let controller = AudioDeviceActivitySource(
            activities: LiveActivityController(settings: NotchSettings()),
            provider: provider
        )
        controller.refreshOutputs()

        let succeeded = await controller.selectOutput(2)
        #expect(!succeeded)
        if case .failed = controller.selectionState {
            #expect(true)
        } else {
            Issue.record("A failed CoreAudio route change must be exposed to the output menu.")
        }
        controller.stop()
    }
}

@MainActor
private final class FakeAudioOutputProvider: AudioOutputDeviceProviding {
    var selectedDeviceID = AudioDeviceID(1)
    var selectionError: Error?

    func availableOutputs() -> [AudioOutputDevice] {
        [
            device(id: 1, name: "MacBook Air Speakers", model: .macBookAirM4),
            device(id: 2, name: "Patrik’s AirPods Pro", model: .airPodsPro, battery: 74),
        ]
    }

    func defaultOutputDeviceID() -> AudioDeviceID {
        selectedDeviceID
    }

    func selectOutput(_ deviceID: AudioDeviceID) throws {
        if let selectionError { throw selectionError }
        selectedDeviceID = deviceID
    }

    private func device(
        id: AudioDeviceID,
        name: String,
        model: AudioAccessoryModel,
        battery: Int? = nil
    ) -> AudioOutputDevice {
        AudioOutputDevice(
            id: id,
            uid: "test-\(id)",
            name: name,
            model: model,
            transport: model == .macBookAirM4 ? .builtIn : .bluetooth,
            batteryPercent: battery,
            isDefault: selectedDeviceID == id
        )
    }
}
