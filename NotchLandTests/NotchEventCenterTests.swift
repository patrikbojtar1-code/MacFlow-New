//
//  NotchEventCenterTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

@MainActor
struct NotchEventCenterTests {
    private func makeCenter(limit: Int = 100) -> (NotchEventCenter, UserDefaults) {
        let defaults = UserDefaults(suiteName: "NotchEventCenterTests.\(UUID().uuidString)")!
        return (NotchEventCenter(defaults: defaults, historyLimit: limit), defaults)
    }

    private func event(
        _ correlationID: String,
        priority: NotchEventPriority,
        title: String? = nil
    ) -> NotchEvent {
        NotchEvent(
            correlationID: correlationID,
            source: .integration,
            title: title ?? correlationID,
            symbol: "sparkles",
            priority: priority
        )
    }

    @Test func firstEventBecomesCurrent() {
        let (center, _) = makeCenter()

        center.submit(event("first", priority: .normal))

        #expect(center.current?.correlationID == "first")
        #expect(center.pending.isEmpty)
        #expect(center.history.count == 1)
    }

    @Test func criticalEventInterruptsAndResolutionRestoresPreviousEvent() {
        let (center, _) = makeCenter()
        center.submit(event("download", priority: .normal))

        center.submit(event("call", priority: .critical))

        #expect(center.current?.correlationID == "call")
        #expect(center.pending.map(\.correlationID) == ["download"])

        center.resolve(correlationID: "call")

        #expect(center.current?.correlationID == "download")
    }

    @Test func lowerPriorityEventWaitsWithoutInterrupting() {
        let (center, _) = makeCenter()
        center.submit(event("payment", priority: .important))

        center.submit(event("focus", priority: .passive))

        #expect(center.current?.correlationID == "payment")
        #expect(center.pending.map(\.correlationID) == ["focus"])
    }

    @Test func sameCorrelationUpdatesInPlaceAndDoesNotDuplicateHistory() {
        let (center, _) = makeCenter()
        center.submit(event("download", priority: .normal, title: "10%"))

        center.submit(event("download", priority: .normal, title: "90%"))

        #expect(center.current?.title == "90%")
        #expect(center.history.count == 1)
        #expect(center.history.first?.title == "90%")
    }

    @Test func pendingQueueSortsByPriorityThenAge() {
        let (center, _) = makeCenter()
        center.submit(event("call", priority: .critical))
        center.submit(event("passive", priority: .passive))
        center.submit(event("important", priority: .important))
        center.submit(event("normal", priority: .normal))

        #expect(center.pending.map(\.correlationID) == ["important", "normal", "passive"])
    }

    @Test func historyPersistsAndHonorsLimit() {
        let (center, defaults) = makeCenter(limit: 2)
        center.submit(event("one", priority: .normal))
        center.submit(event("two", priority: .important))
        center.submit(event("three", priority: .critical))

        let restored = NotchEventCenter(defaults: defaults, historyLimit: 2)

        #expect(restored.history.count == 2)
        #expect(restored.history.map(\.correlationID) == ["three", "two"])
    }

    @Test func readStateAndClearArePersisted() {
        let (center, defaults) = makeCenter()
        center.submit(event("one", priority: .normal))
        #expect(center.unreadCount == 1)

        center.markAllRead()
        #expect(center.unreadCount == 0)

        center.clearHistory()
        let restored = NotchEventCenter(defaults: defaults)
        #expect(restored.history.isEmpty)
    }

    @Test func historyOnlyEventDoesNotTakePresentationAuthority() {
        let (center, _) = makeCenter()

        center.submit(event("hidden-wallet", priority: .important), presents: false)

        #expect(center.current == nil)
        #expect(center.history.map(\.correlationID) == ["hidden-wallet"])
    }

    @Test func presentationPolicyPreservesExpandedInteractionForAmbientEvents() {
        let wallet = NotchEvent(
            correlationID: "wallet:1",
            source: .wallet,
            title: "Payment",
            symbol: "bitcoinsign.circle",
            priority: .important
        )
        let call = NotchEvent(
            correlationID: "call:1",
            source: .call,
            title: "Call",
            symbol: "phone",
            priority: .critical
        )

        #expect(NotchEventPresentationPolicy.route(for: wallet, isExpanded: true, isWalletVisible: true) == nil)
        #expect(NotchEventPresentationPolicy.route(for: wallet, isExpanded: false, isWalletVisible: true) == .wallet)
        #expect(NotchEventPresentationPolicy.route(for: wallet, isExpanded: false, isWalletVisible: false) == nil)
        #expect(NotchEventPresentationPolicy.route(for: call, isExpanded: true, isWalletVisible: true) == .call)
    }
}
