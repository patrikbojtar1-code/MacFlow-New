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
}
