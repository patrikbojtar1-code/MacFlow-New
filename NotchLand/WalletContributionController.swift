//
//  WalletContributionController.swift
//  NotchLand
//
//  Read-only public-address monitoring. No seed phrase, private key, wallet
//  password, or Exodus sync payload ever enters this feature.
//

import Combine
import Foundation

nonisolated enum WalletNetwork: String, Codable, CaseIterable, Identifiable, Sendable {
    case bitcoin
    case litecoin
    case ethereum
    case solana

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bitcoin: "Bitcoin"
        case .litecoin: "Litecoin"
        case .ethereum: "Ethereum"
        case .solana: "Solana"
        }
    }

    var ticker: String {
        switch self {
        case .bitcoin: "BTC"
        case .litecoin: "LTC"
        case .ethereum: "ETH"
        case .solana: "SOL"
        }
    }

    var symbol: String {
        switch self {
        case .bitcoin: "bitcoinsign.circle.fill"
        case .litecoin: "l.circle.fill"
        case .ethereum: "diamond.fill"
        case .solana: "wave.3.right.circle.fill"
        }
    }

    var atomicScale: Decimal {
        switch self {
        case .bitcoin, .litecoin: Decimal(100_000_000)
        case .ethereum: 1_000_000_000_000_000_000
        case .solana: Decimal(1_000_000_000)
        }
    }

    var sampleContribution: Decimal {
        switch self {
        case .bitcoin: Decimal(25) / Decimal(100_000)
        case .litecoin: Decimal(1) / Decimal(100)
        case .ethereum: Decimal(5) / Decimal(1_000)
        case .solana: Decimal(25) / Decimal(100)
        }
    }

    var displayFractionDigits: Int {
        switch self {
        case .bitcoin, .litecoin: 8
        case .ethereum: 6
        case .solana: 5
        }
    }

    var coinGeckoID: String {
        switch self {
        case .bitcoin: "bitcoin"
        case .litecoin: "litecoin"
        case .ethereum: "ethereum"
        case .solana: "solana"
        }
    }
}

nonisolated enum WalletFiatCurrency: String, CaseIterable, Identifiable, Sendable {
    case usd = "USD"
    case eur = "EUR"

    var id: String { rawValue }
    var symbol: String { self == .usd ? "$" : "€" }
}

nonisolated struct WatchedWallet: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var label: String
    let address: String
    let network: WalletNetwork
}

nonisolated struct WalletContribution: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let transactionID: String
    let walletID: UUID
    let walletLabel: String
    let network: WalletNetwork
    let amount: Decimal
    let date: Date
    let isConfirmed: Bool

    private enum CodingKeys: String, CodingKey {
        case id, transactionID, walletID, walletLabel, network, amount, amountSats, date, isConfirmed
    }

    init(
        id: String,
        transactionID: String,
        walletID: UUID,
        walletLabel: String,
        network: WalletNetwork,
        amount: Decimal,
        date: Date,
        isConfirmed: Bool
    ) {
        self.id = id
        self.transactionID = transactionID
        self.walletID = walletID
        self.walletLabel = walletLabel
        self.network = network
        self.amount = amount
        self.date = date
        self.isConfirmed = isConfirmed
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        transactionID = try values.decode(String.self, forKey: .transactionID)
        walletID = try values.decode(UUID.self, forKey: .walletID)
        walletLabel = try values.decode(String.self, forKey: .walletLabel)
        network = try values.decode(WalletNetwork.self, forKey: .network)
        if let decodedAmount = try values.decodeIfPresent(Decimal.self, forKey: .amount) {
            amount = decodedAmount
        } else {
            let legacySats = try values.decode(Int64.self, forKey: .amountSats)
            amount = Decimal(legacySats) / WalletNetwork.bitcoin.atomicScale
        }
        date = try values.decode(Date.self, forKey: .date)
        isConfirmed = try values.decode(Bool.self, forKey: .isConfirmed)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(transactionID, forKey: .transactionID)
        try values.encode(walletID, forKey: .walletID)
        try values.encode(walletLabel, forKey: .walletLabel)
        try values.encode(network, forKey: .network)
        try values.encode(amount, forKey: .amount)
        try values.encode(date, forKey: .date)
        try values.encode(isConfirmed, forKey: .isConfirmed)
    }
}

nonisolated struct WalletTransactionSnapshot: Equatable, Sendable {
    let transactionID: String
    let receivedAmount: Decimal
    let date: Date
    let isConfirmed: Bool
}

nonisolated struct WalletSnapshot: Equatable, Sendable {
    let balance: Decimal
    let transactions: [WalletTransactionSnapshot]
}

nonisolated protocol WalletSnapshotProviding: Sendable {
    func snapshot(for wallet: WatchedWallet) async throws -> WalletSnapshot
}

nonisolated protocol WalletFiatPriceProviding: Sendable {
    func prices(
        for networks: Set<WalletNetwork>,
        currency: WalletFiatCurrency
    ) async throws -> [WalletNetwork: Decimal]
}

nonisolated enum WalletConfigurationError: LocalizedError, Equatable {
    case invalidAddress(WalletNetwork)
    case duplicateAddress

    var errorDescription: String? {
        switch self {
        case .invalidAddress(let network):
            "Enter a valid public \(network.title) receive address from Exodus."
        case .duplicateAddress:
            "This address is already being monitored for the selected network."
        }
    }
}

nonisolated enum WalletProviderError: LocalizedError {
    case malformedResponse
    case unsupportedNetwork

    var errorDescription: String? {
        switch self {
        case .malformedResponse: "The blockchain provider returned an invalid response."
        case .unsupportedNetwork: "This blockchain network is not supported."
        }
    }
}

nonisolated enum WalletAPIEndpoints {
    static let bitcoin = validated("https://blockstream.info/api")
    static let blockCypher = validated("https://api.blockcypher.com/v1")
    static let solana = validated("https://api.mainnet-beta.solana.com")
    static let fiatPrices = validated("https://api.coingecko.com/api/v3/simple/price")

    private static func validated(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid compile-time wallet endpoint: \(value)")
        }
        return url
    }
}

actor MultiChainWalletAPI: WalletSnapshotProviding {
    private let session: URLSession
    private let bitcoinBaseURL: URL
    private let blockCypherBaseURL: URL
    private let solanaRPCURL: URL

    init(
        session: URLSession = .shared,
        bitcoinBaseURL: URL = WalletAPIEndpoints.bitcoin,
        blockCypherBaseURL: URL = WalletAPIEndpoints.blockCypher,
        solanaRPCURL: URL = WalletAPIEndpoints.solana
    ) {
        self.session = session
        self.bitcoinBaseURL = bitcoinBaseURL
        self.blockCypherBaseURL = blockCypherBaseURL
        self.solanaRPCURL = solanaRPCURL
    }

    func snapshot(for wallet: WatchedWallet) async throws -> WalletSnapshot {
        switch wallet.network {
        case .bitcoin:
            try await bitcoinSnapshot(for: wallet)
        case .litecoin:
            try await blockCypherSnapshot(for: wallet, chain: "ltc")
        case .ethereum:
            try await blockCypherSnapshot(for: wallet, chain: "eth")
        case .solana:
            try await solanaSnapshot(for: wallet)
        }
    }

    private func bitcoinSnapshot(for wallet: WatchedWallet) async throws -> WalletSnapshot {
        let encodedAddress = encoded(wallet.address)
        let addressURL = bitcoinBaseURL.appending(path: "address/\(encodedAddress)")
        async let address: BitcoinAddressResponse = request(addressURL)
        async let transactions: [BitcoinTransactionResponse] = request(addressURL.appending(path: "txs"))
        let (addressResponse, transactionList) = try await (address, transactions)

        let atomicBalance = addressResponse.chainStats.fundedSum - addressResponse.chainStats.spentSum
            + addressResponse.mempoolStats.fundedSum - addressResponse.mempoolStats.spentSum
        return WalletSnapshot(
            balance: Decimal(atomicBalance) / wallet.network.atomicScale,
            transactions: transactionList.compactMap { transaction in
                let atomicAmount = transaction.outputs
                    .filter { $0.address == wallet.address }
                    .reduce(Int64.zero) { $0 + $1.value }
                guard atomicAmount > 0 else { return nil }
                return WalletTransactionSnapshot(
                    transactionID: transaction.id,
                    receivedAmount: Decimal(atomicAmount) / wallet.network.atomicScale,
                    date: transaction.status.blockTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? .now,
                    isConfirmed: transaction.status.confirmed
                )
            }
        )
    }

    private func blockCypherSnapshot(for wallet: WatchedWallet, chain: String) async throws -> WalletSnapshot {
        var components = URLComponents(
            url: blockCypherBaseURL.appending(path: "\(chain)/main/addrs/\(encoded(wallet.address))/full"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "limit", value: "25")]
        guard let url = components?.url else { throw URLError(.badURL) }
        let response: BlockCypherAddressResponse = try await request(url)

        return WalletSnapshot(
            balance: response.finalBalance / wallet.network.atomicScale,
            transactions: response.transactions.compactMap { transaction in
                let atomicAmount = transaction.outputs
                    .filter { output in
                        output.addresses.contains { $0.caseInsensitiveCompare(wallet.address) == .orderedSame }
                    }
                    .reduce(Decimal.zero) { $0 + $1.value }
                guard atomicAmount > 0 else { return nil }
                return WalletTransactionSnapshot(
                    transactionID: transaction.hash,
                    receivedAmount: atomicAmount / wallet.network.atomicScale,
                    date: Self.parseISO8601(transaction.confirmed ?? transaction.received) ?? .now,
                    isConfirmed: (transaction.confirmations ?? 0) > 0
                )
            }
        )
    }

    private func solanaSnapshot(for wallet: WatchedWallet) async throws -> WalletSnapshot {
        let balanceResponse = try await solanaRPC(method: "getBalance", params: [
            wallet.address,
            ["commitment": "confirmed"]
        ])
        guard let balanceResult = balanceResponse["result"] as? [String: Any],
              let lamports = Self.decimal(balanceResult["value"]) else {
            throw WalletProviderError.malformedResponse
        }

        let signaturesResponse = try await solanaRPC(method: "getSignaturesForAddress", params: [
            wallet.address,
            ["limit": 12, "commitment": "confirmed"]
        ])
        let signatures = signaturesResponse["result"] as? [[String: Any]] ?? []
        var transactions: [WalletTransactionSnapshot] = []

        for signatureInfo in signatures where signatureInfo["err"] is NSNull || signatureInfo["err"] == nil {
            guard let signature = signatureInfo["signature"] as? String else { continue }
            let transactionResponse = try await solanaRPC(method: "getTransaction", params: [
                signature,
                [
                    "encoding": "jsonParsed",
                    "commitment": "confirmed",
                    "maxSupportedTransactionVersion": 0
                ]
            ])
            guard let transaction = transactionResponse["result"] as? [String: Any],
                  let meta = transaction["meta"] as? [String: Any],
                  let envelope = transaction["transaction"] as? [String: Any],
                  let message = envelope["message"] as? [String: Any],
                  let keys = message["accountKeys"] as? [Any],
                  let index = Self.accountIndex(of: wallet.address, in: keys),
                  let preBalances = meta["preBalances"] as? [Any],
                  let postBalances = meta["postBalances"] as? [Any],
                  preBalances.indices.contains(index), postBalances.indices.contains(index),
                  let pre = Self.decimal(preBalances[index]),
                  let post = Self.decimal(postBalances[index]),
                  post > pre else { continue }

            let blockTime = Self.decimal(transaction["blockTime"])
                .map { Date(timeIntervalSince1970: NSDecimalNumber(decimal: $0).doubleValue) } ?? .now
            let status = signatureInfo["confirmationStatus"] as? String
            transactions.append(
                WalletTransactionSnapshot(
                    transactionID: signature,
                    receivedAmount: (post - pre) / wallet.network.atomicScale,
                    date: blockTime,
                    isConfirmed: status == "confirmed" || status == "finalized"
                )
            )
        }

        return WalletSnapshot(
            balance: lamports / wallet.network.atomicScale,
            transactions: transactions
        )
    }

    private func request<Value: Decodable>(_ url: URL) async throws -> Value {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("NotchLand/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func solanaRPC(method: String, params: [Any]) async throws -> [String: Any] {
        var request = URLRequest(url: solanaRPCURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": params
        ])
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["error"] == nil else { throw WalletProviderError.malformedResponse }
        return object
    }

    private func encoded(_ address: String) -> String {
        address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? address
    }

    nonisolated private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }

    nonisolated private static func decimal(_ value: Any?) -> Decimal? {
        if let number = value as? NSNumber { return number.decimalValue }
        if let string = value as? String { return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) }
        return nil
    }

    nonisolated private static func accountIndex(of address: String, in values: [Any]) -> Int? {
        values.firstIndex { value in
            if let string = value as? String { return string == address }
            if let object = value as? [String: Any] { return object["pubkey"] as? String == address }
            return false
        }
    }

    nonisolated private static func parseISO8601(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}

actor CoinGeckoWalletPriceAPI: WalletFiatPriceProviding {
    private let session: URLSession
    private let baseURL: URL

    init(
        session: URLSession = .shared,
        baseURL: URL = WalletAPIEndpoints.fiatPrices
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func prices(
        for networks: Set<WalletNetwork>,
        currency: WalletFiatCurrency
    ) async throws -> [WalletNetwork: Decimal] {
        guard !networks.isEmpty else { return [:] }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "ids", value: networks.map(\.coinGeckoID).sorted().joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: currency.rawValue.lowercased()),
            URLQueryItem(name: "precision", value: "full")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("NotchLand/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode([String: [String: Decimal]].self, from: data)
        return Dictionary(uniqueKeysWithValues: networks.compactMap { network in
            decoded[network.coinGeckoID]?[currency.rawValue.lowercased()].map { (network, $0) }
        })
    }
}

nonisolated private struct BitcoinAddressResponse: Decodable {
    let chainStats: BitcoinAddressStats
    let mempoolStats: BitcoinAddressStats

    enum CodingKeys: String, CodingKey {
        case chainStats = "chain_stats"
        case mempoolStats = "mempool_stats"
    }
}

nonisolated private struct BitcoinAddressStats: Decodable {
    let fundedSum: Int64
    let spentSum: Int64

    enum CodingKeys: String, CodingKey {
        case fundedSum = "funded_txo_sum"
        case spentSum = "spent_txo_sum"
    }
}

nonisolated private struct BitcoinTransactionResponse: Decodable {
    let id: String
    let status: BitcoinTransactionStatus
    let outputs: [BitcoinTransactionOutput]

    enum CodingKeys: String, CodingKey {
        case id = "txid"
        case status
        case outputs = "vout"
    }
}

nonisolated private struct BitcoinTransactionStatus: Decodable {
    let confirmed: Bool
    let blockTime: Int64?

    enum CodingKeys: String, CodingKey {
        case confirmed
        case blockTime = "block_time"
    }
}

nonisolated private struct BitcoinTransactionOutput: Decodable {
    let address: String?
    let value: Int64

    enum CodingKeys: String, CodingKey {
        case address = "scriptpubkey_address"
        case value
    }
}

nonisolated private struct BlockCypherAddressResponse: Decodable {
    let finalBalance: Decimal
    let transactions: [BlockCypherTransaction]

    enum CodingKeys: String, CodingKey {
        case finalBalance = "final_balance"
        case transactions = "txs"
    }
}

nonisolated private struct BlockCypherTransaction: Decodable {
    let hash: String
    let confirmed: String?
    let received: String?
    let confirmations: Int?
    let outputs: [BlockCypherOutput]
}

nonisolated private struct BlockCypherOutput: Decodable {
    let addresses: [String]
    let value: Decimal
}

@MainActor
final class WalletContributionController: ObservableObject {
    @Published private(set) var wallets: [WatchedWallet] = []
    @Published private(set) var contributions: [WalletContribution] = []
    @Published private(set) var balances: [UUID: Decimal] = [:]
    @Published private(set) var fiatRates: [WalletNetwork: Decimal] = [:]
    @Published private(set) var fiatCurrency: WalletFiatCurrency
    @Published private(set) var currentContribution: WalletContribution?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var errorMessage: String?

    private enum Keys {
        static let wallets = "wallet.watchedAddresses.v1"
        static let contributions = "wallet.contributions.v1"
        static let knownTransactions = "wallet.knownTransactions.v1"
        static let baselinedWallets = "wallet.baselinedWallets.v1"
        static let fiatCurrency = "wallet.fiatCurrency.v1"
    }

    private let defaults: UserDefaults
    private let provider: any WalletSnapshotProviding
    private let priceProvider: any WalletFiatPriceProviding
    private let pollInterval: Duration
    private var knownTransactionIDs: Set<String> = []
    private var baselinedWalletIDs: Set<UUID> = []
    private var monitoringTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        provider: any WalletSnapshotProviding = MultiChainWalletAPI(),
        priceProvider: any WalletFiatPriceProviding = CoinGeckoWalletPriceAPI(),
        pollInterval: Duration = .seconds(20)
    ) {
        self.defaults = defaults
        self.provider = provider
        self.priceProvider = priceProvider
        self.pollInterval = pollInterval
        fiatCurrency = WalletFiatCurrency(
            rawValue: defaults.string(forKey: Keys.fiatCurrency) ?? ""
        ) ?? .usd
        restore()
    }

    func balance(for network: WalletNetwork) -> Decimal {
        wallets
            .filter { $0.network == network }
            .compactMap { balances[$0.id] }
            .reduce(.zero, +)
    }

    func fiatValue(for contribution: WalletContribution) -> Decimal? {
        fiatRates[contribution.network].map { $0 * contribution.amount }
    }

    func setFiatCurrency(_ currency: WalletFiatCurrency) {
        guard fiatCurrency != currency else { return }
        fiatCurrency = currency
        defaults.set(currency.rawValue, forKey: Keys.fiatCurrency)
        Task { await refreshFiatRates() }
    }

    func start() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.sync()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        presentationTask?.cancel()
        presentationTask = nil
    }

    @discardableResult
    func addWallet(label: String, address: String, network: WalletNetwork) throws -> WatchedWallet {
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidAddress(normalizedAddress, for: network) else {
            throw WalletConfigurationError.invalidAddress(network)
        }
        guard !wallets.contains(where: {
            $0.network == network && $0.address.caseInsensitiveCompare(normalizedAddress) == .orderedSame
        }) else { throw WalletConfigurationError.duplicateAddress }

        let wallet = WatchedWallet(
            id: UUID(),
            label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Exodus \(network.ticker)" : label,
            address: normalizedAddress,
            network: network
        )
        wallets.append(wallet)
        persist()
        Task { await sync() }
        return wallet
    }

    @discardableResult
    func addBitcoinWallet(label: String, address: String) throws -> WatchedWallet {
        try addWallet(label: label, address: address, network: .bitcoin)
    }

    func removeWallet(_ wallet: WatchedWallet) {
        wallets.removeAll { $0.id == wallet.id }
        balances[wallet.id] = nil
        baselinedWalletIDs.remove(wallet.id)
        contributions.removeAll { $0.walletID == wallet.id }
        persist()
    }

    func sync() async {
        guard !wallets.isEmpty, !isSyncing else { return }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        for wallet in wallets {
            do {
                apply(try await provider.snapshot(for: wallet), to: wallet)
            } catch {
                errorMessage = "\(wallet.network.ticker) sync failed: \(error.localizedDescription)"
            }
        }
        await refreshFiatRates()
        lastSyncDate = .now
        persist()
    }

    func showTestContribution(for network: WalletNetwork? = nil) {
        let selectedWallet = network.flatMap { target in wallets.first { $0.network == target } } ?? wallets.first
        guard let wallet = selectedWallet else { return }
        let contribution = WalletContribution(
                id: "test-\(UUID().uuidString)",
                transactionID: "preview",
                walletID: wallet.id,
                walletLabel: wallet.label,
                network: wallet.network,
                amount: wallet.network.sampleContribution,
                date: .now,
                isConfirmed: true
            )
        Task {
            await refreshFiatRates()
            present(contribution)
        }
    }

    nonisolated static func isValidAddress(_ address: String, for network: WalletNetwork) -> Bool {
        switch network {
        case .bitcoin:
            if address.lowercased().hasPrefix("bc1") {
                return (14...74).contains(address.count) && isAlphaNumeric(address.dropFirst(3))
            }
            return (26...35).contains(address.count)
                && (address.first == "1" || address.first == "3")
                && isBase58(address)
        case .litecoin:
            if address.lowercased().hasPrefix("ltc1") {
                return (14...74).contains(address.count) && isAlphaNumeric(address.dropFirst(4))
            }
            return (26...35).contains(address.count)
                && (address.first == "L" || address.first == "M" || address.first == "3")
                && isBase58(address)
        case .ethereum:
            guard address.count == 42, address.hasPrefix("0x") else { return false }
            return address.dropFirst(2).allSatisfy { $0.isHexDigit }
        case .solana:
            return (32...44).contains(address.count) && isBase58(address)
        }
    }

    nonisolated static func isValidBitcoinAddress(_ address: String) -> Bool {
        isValidAddress(address, for: .bitcoin)
    }

    private func apply(_ snapshot: WalletSnapshot, to wallet: WatchedWallet) {
        balances[wallet.id] = snapshot.balance
        let isBaseline = !baselinedWalletIDs.contains(wallet.id)

        for transaction in snapshot.transactions {
            let id = transactionKey(walletID: wallet.id, transactionID: transaction.transactionID)
            guard let index = contributions.firstIndex(where: { $0.id == id }),
                  contributions[index].isConfirmed != transaction.isConfirmed else { continue }
            let existing = contributions[index]
            contributions[index] = WalletContribution(
                id: existing.id,
                transactionID: existing.transactionID,
                walletID: existing.walletID,
                walletLabel: existing.walletLabel,
                network: existing.network,
                amount: transaction.receivedAmount,
                date: transaction.date,
                isConfirmed: transaction.isConfirmed
            )
        }

        let newTransactions = snapshot.transactions.filter {
            !knownTransactionIDs.contains(transactionKey(walletID: wallet.id, transactionID: $0.transactionID))
        }
        for transaction in newTransactions {
            let contribution = WalletContribution(
                id: transactionKey(walletID: wallet.id, transactionID: transaction.transactionID),
                transactionID: transaction.transactionID,
                walletID: wallet.id,
                walletLabel: wallet.label,
                network: wallet.network,
                amount: transaction.receivedAmount,
                date: transaction.date,
                isConfirmed: transaction.isConfirmed
            )
            contributions.removeAll { $0.id == contribution.id }
            contributions.append(contribution)
            if !isBaseline { present(contribution) }
            knownTransactionIDs.insert(contribution.id)
        }

        baselinedWalletIDs.insert(wallet.id)
        contributions.sort { $0.date > $1.date }
        contributions = Array(contributions.prefix(80))
    }

    private func present(_ contribution: WalletContribution) {
        presentationTask?.cancel()
        currentContribution = contribution
        NotchHaptics.perform(.confirmation)
        presentationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.currentContribution = nil
        }
    }

    private func refreshFiatRates() async {
        let networks = Set(wallets.map(\.network))
        guard !networks.isEmpty else { return }
        do {
            fiatRates = try await priceProvider.prices(for: networks, currency: fiatCurrency)
        } catch {
            // Fiat is an enhancement; native crypto amounts remain available
            // when the public quote service is offline or rate-limited.
        }
    }

    private func transactionKey(walletID: UUID, transactionID: String) -> String {
        "\(walletID.uuidString):\(transactionID)"
    }

    private func restore() {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Keys.wallets),
           let value = try? decoder.decode([WatchedWallet].self, from: data) { wallets = value }
        if let data = defaults.data(forKey: Keys.contributions),
           let value = try? decoder.decode([WalletContribution].self, from: data) { contributions = value }
        knownTransactionIDs = Set(defaults.stringArray(forKey: Keys.knownTransactions) ?? [])
        baselinedWalletIDs = Set(
            (defaults.stringArray(forKey: Keys.baselinedWallets) ?? []).compactMap(UUID.init(uuidString:))
        )
    }

    private func persist() {
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(wallets), forKey: Keys.wallets)
        defaults.set(try? encoder.encode(contributions), forKey: Keys.contributions)
        defaults.set(Array(knownTransactionIDs), forKey: Keys.knownTransactions)
        defaults.set(baselinedWalletIDs.map(\.uuidString), forKey: Keys.baselinedWallets)
    }

    nonisolated private static func isBase58<S: StringProtocol>(_ value: S) -> Bool {
        let alphabet = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        return value.allSatisfy(alphabet.contains)
    }

    nonisolated private static func isAlphaNumeric<S: StringProtocol>(_ value: S) -> Bool {
        value.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
