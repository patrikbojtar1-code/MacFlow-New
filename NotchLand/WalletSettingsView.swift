//
//  WalletSettingsView.swift
//  NotchLand
//

import AppKit
import SwiftUI

struct WalletSettingsView: View {
    @EnvironmentObject private var wallet: WalletContributionController
    @State private var label = "Exodus"
    @State private var address = ""
    @State private var selectedNetwork: WalletNetwork = .bitcoin
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Cryptocurrency", selection: $selectedNetwork) {
                    ForEach(WalletNetwork.allCases) { network in
                        Label("\(network.title) (\(network.ticker))", systemImage: network.symbol)
                            .tag(network)
                    }
                }

                TextField("Wallet label", text: $label)
                TextField("\(selectedNetwork.title) receive address", text: $address)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Add Address") {
                        addWallet()
                    }
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Paste") {
                        address = NSPasteboard.general.string(forType: .string) ?? ""
                    }

                    Spacer()

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Public Address Monitoring")
            } footer: {
                Text("Paste only public receive addresses from Exodus. They are queried read-only through network-specific blockchain providers. NotchLand never asks for a seed phrase, private key, password, or sync QR code.")
            }

            Section("Monitored Wallets") {
                if wallet.wallets.isEmpty {
                    Text("No public addresses configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(wallet.wallets) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.network.symbol)
                                .foregroundStyle(item.network.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label)
                                Text(item.network.ticker)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(item.network.accentColor)
                                Text(abbreviate(item.address))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                wallet.removeWallet(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("Diagnostics") {
                Picker(
                    "Payment display currency",
                    selection: Binding(
                        get: { wallet.fiatCurrency },
                        set: { wallet.setFiatCurrency($0) }
                    )
                ) {
                    ForEach(WalletFiatCurrency.allCases) { currency in
                        Text("\(currency.symbol)  \(currency.rawValue)")
                            .tag(currency)
                    }
                }

                HStack {
                    Button("Sync Now") {
                        Task { await wallet.sync() }
                    }
                    .disabled(wallet.wallets.isEmpty || wallet.isSyncing)

                    Menu("Preview Contribution") {
                        ForEach(configuredNetworks) { network in
                            Button("\(network.title) (\(network.ticker))") {
                                wallet.showTestContribution(for: network)
                            }
                        }
                    }
                    .disabled(wallet.wallets.isEmpty)

                    Spacer()

                    if let date = wallet.lastSyncDate {
                        Text("Last sync \(date, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = wallet.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addWallet() {
        do {
            try wallet.addWallet(label: label, address: address, network: selectedNetwork)
            address = ""
            validationMessage = nil
        } catch {
            validationMessage = error.localizedDescription
            NotchHaptics.perform(.rejection)
        }
    }

    private var configuredNetworks: [WalletNetwork] {
        WalletNetwork.allCases.filter { network in
            wallet.wallets.contains { $0.network == network }
        }
    }

    private func abbreviate(_ value: String) -> String {
        guard value.count > 18 else { return value }
        return "\(value.prefix(9))…\(value.suffix(7))"
    }
}

#if DEBUG
#Preview("Wallet Settings") {
    NotchPreviewContainer {
        WalletSettingsView()
            .frame(width: 510, height: 520)
    }
}
#endif
