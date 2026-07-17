//
//  WalletContributionControllerTests.swift
//  NotchLandTests
//

import Foundation
import Testing
@testable import NotchLand

private actor WalletProviderStub: WalletSnapshotProviding {
    private var snapshots: [WalletSnapshot]

    init(snapshots: [WalletSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot(for wallet: WatchedWallet) async throws -> WalletSnapshot {
        guard !snapshots.isEmpty else {
            return WalletSnapshot(balance: 0, transactions: [])
        }
        return snapshots.removeFirst()
    }
}

private actor WalletFiatPriceStub: WalletFiatPriceProviding {
    let rates: [WalletNetwork: Decimal]

    init(rates: [WalletNetwork: Decimal] = [:]) {
        self.rates = rates
    }

    func prices(
        for networks: Set<WalletNetwork>,
        currency: WalletFiatCurrency
    ) async throws -> [WalletNetwork: Decimal] {
        rates.filter { networks.contains($0.key) }
    }
}

@MainActor
struct WalletContributionControllerTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "WalletContributionControllerTests.\(UUID().uuidString)")!
    }

    @Test func validatesCommonBitcoinReceiveAddressFormats() {
        #expect(WalletContributionController.isValidBitcoinAddress("1BoatSLRHtKNngkdXEeobR76b53LETtpyT"))
        #expect(WalletContributionController.isValidBitcoinAddress("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"))
        #expect(WalletContributionController.isValidBitcoinAddress("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080"))
        #expect(!WalletContributionController.isValidBitcoinAddress("seed phrase"))
        #expect(!WalletContributionController.isValidBitcoinAddress("0x1234"))
    }

    @Test func compileTimeWalletEndpointsRemainSecureAndAbsolute() {
        let endpoints = [
            WalletAPIEndpoints.bitcoin,
            WalletAPIEndpoints.blockCypher,
            WalletAPIEndpoints.solana,
            WalletAPIEndpoints.fiatPrices
        ]

        #expect(endpoints.allSatisfy { $0.scheme == "https" && $0.host != nil })
        #expect(WalletNetwork.ethereum.atomicScale == 1_000_000_000_000_000_000)
    }

    @Test func validatesLitecoinEthereumAndSolanaFormats() {
        #expect(WalletContributionController.isValidAddress("ltc1qg82nt0x3x74l7m4n0xqv3wcl6v4q34x0k7p6sk", for: .litecoin))
        #expect(WalletContributionController.isValidAddress("0x52908400098527886E0F7030069857D2E4169EE7", for: .ethereum))
        #expect(WalletContributionController.isValidAddress("GdnSyH3YtwcxFvQrVVJMm1JhTS4QVX7MFsX56uJLUfiZ", for: .solana))
        #expect(!WalletContributionController.isValidAddress("0x1234", for: .ethereum))
        #expect(!WalletContributionController.isValidAddress("solana", for: .solana))
    }

    @Test func duplicatePublicAddressIsRejected() throws {
        let controller = WalletContributionController(
            defaults: makeDefaults(),
            provider: WalletProviderStub(snapshots: []),
            priceProvider: WalletFiatPriceStub()
        )
        let address = "1BoatSLRHtKNngkdXEeobR76b53LETtpyT"
        try controller.addBitcoinWallet(label: "Exodus", address: address)

        #expect(throws: WalletConfigurationError.duplicateAddress) {
            try controller.addBitcoinWallet(label: "Duplicate", address: address)
        }
    }

    @Test func multipleNetworksAndAddressesCanCoexist() throws {
        let controller = WalletContributionController(
            defaults: makeDefaults(),
            provider: WalletProviderStub(snapshots: []),
            priceProvider: WalletFiatPriceStub()
        )

        try controller.addWallet(
            label: "Exodus BTC",
            address: "1BoatSLRHtKNngkdXEeobR76b53LETtpyT",
            network: .bitcoin
        )
        try controller.addWallet(
            label: "Exodus ETH",
            address: "0x52908400098527886E0F7030069857D2E4169EE7",
            network: .ethereum
        )
        try controller.addWallet(
            label: "Exodus SOL",
            address: "GdnSyH3YtwcxFvQrVVJMm1JhTS4QVX7MFsX56uJLUfiZ",
            network: .solana
        )

        #expect(controller.wallets.count == 3)
        #expect(Set(controller.wallets.map(\.network)) == [.bitcoin, .ethereum, .solana])
    }

    @Test func baselineDoesNotAlertButNewTransactionDoes() async throws {
        let defaults = makeDefaults()
        let wallet = WatchedWallet(
            id: UUID(),
            label: "Exodus",
            address: "1BoatSLRHtKNngkdXEeobR76b53LETtpyT",
            network: .bitcoin
        )
        defaults.set(try JSONEncoder().encode([wallet]), forKey: "wallet.watchedAddresses.v1")

        let oldTransaction = WalletTransactionSnapshot(
            transactionID: "old",
            receivedAmount: Decimal(string: "0.0001")!,
            date: .now.addingTimeInterval(-60),
            isConfirmed: true
        )
        let newTransaction = WalletTransactionSnapshot(
            transactionID: "new",
            receivedAmount: Decimal(string: "0.00025")!,
            date: .now,
            isConfirmed: false
        )
        let provider = WalletProviderStub(snapshots: [
            WalletSnapshot(balance: Decimal(string: "0.0001")!, transactions: [oldTransaction]),
            WalletSnapshot(balance: Decimal(string: "0.00035")!, transactions: [newTransaction, oldTransaction])
        ])
        let controller = WalletContributionController(
            defaults: defaults,
            provider: provider,
            priceProvider: WalletFiatPriceStub(rates: [.bitcoin: Decimal(60_000)])
        )

        await controller.sync()
        #expect(controller.currentContribution == nil)
        #expect(controller.contributions.count == 1)

        await controller.sync()
        #expect(controller.currentContribution?.transactionID == "new")
        #expect(controller.currentContribution?.amount == Decimal(string: "0.00025")!)
        #expect(controller.contributions.count == 2)
        #expect(controller.fiatValue(for: controller.currentContribution!) == Decimal(15))
    }
}
