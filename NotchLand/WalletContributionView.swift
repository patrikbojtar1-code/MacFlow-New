//
//  WalletContributionView.swift
//  NotchLand
//

import SwiftUI

struct WalletContributionView: View {
    @EnvironmentObject private var wallet: WalletContributionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header

            if wallet.wallets.isEmpty {
                emptyState
            } else if let contribution = wallet.currentContribution {
                contributionHero(contribution)
                    .transition(reduceMotion ? .opacity : .notchSuccess)
            } else {
                dashboard
                    .transition(reduceMotion ? .opacity : .notchSection)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .animation(
            NotchMotionGraph.animation(for: .success, reduceMotion: reduceMotion),
            value: wallet.currentContribution
        )
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                Image(systemName: "wallet.bifold.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .frame(width: 27, height: 27)

            VStack(alignment: .leading, spacing: 1) {
                Text("Exodus Multi-chain Wallet")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("Read-only public address monitor")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Spacer()

            if wallet.isSyncing {
                WalletSyncIndicator()
            } else {
                Button {
                    Task { await wallet.sync() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Sync wallet")
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

            VStack(alignment: .leading, spacing: 5) {
                Text("Connect a public receive address")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("Open Settings › Wallet and add one or more BTC, LTC, ETH, or SOL receive addresses. Never enter a seed phrase or private key.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var dashboard: some View {
        HStack(spacing: 12) {
            balanceCard
            historyCard
        }
        .frame(maxHeight: .infinity)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ASSET BALANCES")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.36))

            ForEach(configuredNetworks.prefix(4)) { network in
                HStack(spacing: 6) {
                    Image(systemName: network.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(network.accentColor)
                        .frame(width: 13)
                    Text(formatAmount(wallet.balance(for: network), network: network))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Spacer(minLength: 2)
                    Text(network.ticker)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }

            Spacer(minLength: 2)
            Label("\(wallet.wallets.count) monitored", systemImage: "eye.fill")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(15)
        .frame(width: 188, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.purple.opacity(0.10), .white.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Recent contributions")
                .font(.system(size: 11, weight: .semibold, design: .rounded))

            if wallet.contributions.isEmpty {
                Spacer()
                Text("Waiting for the first contribution")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.38))
                Spacer()
            } else {
                ForEach(wallet.contributions.prefix(3)) { contribution in
                    contributionRow(contribution)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.065), lineWidth: 1)
        }
    }

    private func contributionRow(_ contribution: WalletContribution) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(contribution.isConfirmed ? Color.green : Color.orange)
                .frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(contribution.walletLabel)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                Text(contribution.date, style: .relative)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))
            }
            Spacer()
            Text("+\(formatAmount(contribution.amount, network: contribution.network)) \(contribution.network.ticker)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(contribution.network.accentColor)
                .monospacedDigit()
        }
    }

    private func contributionHero(_ contribution: WalletContribution) -> some View {
        let accent = contribution.network.accentColor

        return ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.22), accent.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            WalletCelebrationParticles(isActive: !reduceMotion)

            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 54, height: 54)
                    Image(systemName: contribution.network.symbol)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.black.opacity(0.82))
                }
                .shadow(color: accent.opacity(0.28), radius: 14)

                VStack(alignment: .leading, spacing: 4) {
                    Text("New contribution")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("+\(formatAmount(contribution.amount, network: contribution.network)) \(contribution.network.ticker)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Label(
                        contribution.isConfirmed ? "Confirmed" : "Waiting for confirmation",
                        systemImage: contribution.isConfirmed ? "checkmark.seal.fill" : "clock.fill"
                    )
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(contribution.isConfirmed ? .green : accent)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        }
    }

    private var configuredNetworks: [WalletNetwork] {
        WalletNetwork.allCases.filter { network in
            wallet.wallets.contains { $0.network == network }
        }
    }

    private func formatAmount(_ amount: Decimal, network: WalletNetwork) -> String {
        amount.formatted(.number.precision(.fractionLength(0...network.displayFractionDigits)))
    }
}

private struct WalletSyncIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotates = false

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.orange)
            .rotationEffect(.degrees(rotates ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(NotchAmbientMotion.spinner()) { rotates = true }
            }
            .frame(width: 28, height: 28)
    }
}

private struct WalletCelebrationParticles: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private let particles: [(x: CGFloat, y: CGFloat, color: Color)] = [
        (-190, -48, .orange), (-150, 46, .yellow), (-82, -57, .white),
        (78, 52, .orange), (145, -43, .yellow), (200, 34, .white)
    ]

    var body: some View {
        ZStack {
            ForEach(Array(particles.enumerated()), id: \.offset) { index, particle in
                Circle()
                    .fill(particle.color.opacity(0.75))
                    .frame(width: index.isMultiple(of: 2) ? 5 : 3, height: index.isMultiple(of: 2) ? 5 : 3)
                    .offset(
                        x: expanded ? particle.x : particle.x * 0.35,
                        y: expanded ? particle.y : 0
                    )
                    .opacity(expanded ? 0.18 : 0.9)
            }
        }
        .onAppear {
            guard isActive, !reduceMotion else { return }
            withAnimation(NotchAmbientMotion.celebration()) {
                expanded = true
            }
        }
    }
}

enum WalletContributionChipMetrics {
    nonisolated static let width: CGFloat = 372
    nonisolated static let height: CGFloat = 42
}

struct WalletContributionChipView: View {
    let contribution: WalletContribution
    @EnvironmentObject private var settings: NotchSettings
    @EnvironmentObject private var wallet: WalletContributionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var notchGap: CGFloat { CGFloat(settings.collapsedWidth) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(contribution.network.accentColor.opacity(0.2))
                    Image(systemName: contribution.network.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(contribution.network.accentColor)
                }
                .frame(width: 26, height: 26)
                .scaleEffect(appeared ? 1 : 0.72)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Exodus")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                    Text(contribution.network.ticker)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(contribution.network.accentColor)
                }
            }
            .padding(.leading, 13)
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: notchGap)

            VStack(alignment: .trailing, spacing: 0) {
                Text(formattedFiat ?? "+\(formattedAmount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                HStack(spacing: 3) {
                    Circle()
                        .fill(contribution.isConfirmed ? Color.green : contribution.network.accentColor)
                        .frame(width: 4, height: 4)
                    Text(contribution.isConfirmed ? "Received" : "Pending")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .padding(.trailing, 13)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [contribution.network.accentColor.opacity(0.11), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .onAppear {
            withAnimation(NotchMotionGraph.animation(for: .success, reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Payment received, \(formattedAmount) \(contribution.network.ticker)")
    }

    private var formattedAmount: String {
        contribution.amount.formatted(
            .number.precision(.fractionLength(0...contribution.network.displayFractionDigits))
        )
    }

    private var formattedFiat: String? {
        guard let value = wallet.fiatValue(for: contribution) else { return nil }
        return "+" + value.formatted(
            .currency(code: wallet.fiatCurrency.rawValue)
                .precision(.fractionLength(2))
        )
    }
}

extension WalletNetwork {
    var accentColor: Color {
        switch self {
        case .bitcoin: .orange
        case .litecoin: Color(red: 0.37, green: 0.50, blue: 0.82)
        case .ethereum: Color(red: 0.55, green: 0.58, blue: 0.95)
        case .solana: Color(red: 0.26, green: 0.94, blue: 0.70)
        }
    }
}
