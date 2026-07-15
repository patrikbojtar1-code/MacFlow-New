//
//  CallOverlayView.swift
//  NotchLand
//

import SwiftUI

enum CallOverlayMetrics {
    nonisolated static let incomingSize = CGSize(width: 430, height: 116)
    nonisolated static let activeSize = CGSize(width: 390, height: 76)
    nonisolated static let endedSize = CGSize(width: 330, height: 58)

    nonisolated static func size(for presentation: CallPresentation) -> CGSize {
        switch presentation.phase {
        case .incoming, .connecting: incomingSize
        case .active: activeSize
        case .ended, .missed: endedSize
        }
    }
}

struct CallOverlayView: View {
    let presentation: CallPresentation

    @EnvironmentObject private var calls: CallActivityController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var callMotion
    @State private var isRinging = false

    var body: some View {
        ZStack {
            switch presentation.phase {
            case .incoming:
                incomingContent
            case .connecting:
                connectingContent
            case .active:
                activeContent
            case let .ended(reason):
                resultContent(symbol: "phone.down.fill", title: reason, tint: .secondary)
            case .missed:
                resultContent(symbol: "phone.badge.xmark.fill", title: "Missed Call", tint: .red)
            }
        }
        .id(phaseIdentity)
        .transition(phaseTransition)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(callAnimation, value: phaseIdentity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(NotchAmbientMotion.ringing()) {
                isRinging = true
            }
        }
    }

    private var incomingContent: some View {
        HStack(spacing: 14) {
            avatar(size: 48, showsRingingPulse: true)
            callerIdentity(status: presentation.serviceName)
            Spacer(minLength: 8)

            if presentation.supportsCallControl {
                callButton(
                    symbol: "phone.down.fill",
                    title: "Decline",
                    color: .red,
                    action: calls.decline
                )
                callButton(
                    symbol: "video.fill",
                    title: "Answer",
                    color: .green,
                    action: calls.answer
                )
            } else {
                callButton(
                    symbol: "xmark",
                    title: "Dismiss",
                    color: .gray,
                    action: calls.dismiss
                )
                callButton(
                    symbol: "arrow.up.forward.app.fill",
                    title: "Open",
                    color: .blue,
                    action: calls.openCallingApp
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 32)
        .padding(.bottom, 9)
    }

    private var connectingContent: some View {
        HStack(spacing: 14) {
            avatar(size: 44, showsRingingPulse: false)
            callerIdentity(status: "Connecting…")
            Spacer()
            ProgressView()
                .controlSize(.small)
            callButton(
                symbol: "phone.down.fill",
                title: "End",
                color: .red,
                action: calls.end
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 31)
        .padding(.bottom, 8)
    }

    private var activeContent: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 12) {
                avatar(size: 34, showsRingingPulse: false)
                callerIdentity(status: activeDuration(at: context.date))
                Spacer()
                callButton(
                    symbol: presentation.isMuted ? "mic.slash.fill" : "mic.fill",
                    title: presentation.isMuted ? "Unmute" : "Mute",
                    color: presentation.isMuted ? .orange : .gray,
                    action: calls.toggleMute,
                    compact: true
                )
                callButton(
                    symbol: "phone.down.fill",
                    title: "End",
                    color: .red,
                    action: calls.end,
                    compact: true
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 6)
    }

    private func resultContent(symbol: String, title: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            avatar(size: 28, showsRingingPulse: false)
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(presentation.callerName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer()
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .padding(.bottom, 5)
    }

    private func avatar(size: CGFloat, showsRingingPulse: Bool) -> some View {
        ZStack {
            if showsRingingPulse {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .stroke(.green.opacity(0.34), lineWidth: 1.5)
                        .scaleEffect(isRinging ? 1.42 + CGFloat(index) * 0.16 : 0.92)
                        .opacity(isRinging ? 0 : 0.72)
                        .animation(
                            NotchAmbientMotion.ringing().delay(Double(index) * 0.32),
                            value: isRinging
                        )
                }
            }
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.cyan.opacity(0.95), .blue, .purple.opacity(0.86)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Text(presentation.initials)
                        .font(.system(size: size * 0.31, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .shadow(color: .blue.opacity(0.32), radius: 8, y: 3)
        }
        .frame(width: size, height: size)
        .matchedGeometryEffect(id: "call-avatar", in: callMotion)
    }

    private func callerIdentity(status: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(presentation.callerName)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text(status)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func callButton(
        symbol: String,
        title: String,
        color: Color,
        action: @escaping () -> Void,
        compact: Bool = false
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 11 : 13, weight: .bold))
                    .frame(width: compact ? 27 : 34, height: compact ? 27 : 34)
                    .background(color.gradient, in: Circle())
                    .foregroundStyle(.white)
                if !compact {
                    Text(title)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }

    private func activeDuration(at date: Date) -> String {
        guard let connectedAt = presentation.connectedAt else { return "Connected" }
        let elapsed = max(0, Int(date.timeIntervalSince(connectedAt)))
        return String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    private var callAnimation: Animation {
        NotchMotionGraph.animation(for: .contentEnter, reduceMotion: reduceMotion)
    }

    private var phaseIdentity: String {
        switch presentation.phase {
        case .incoming: "incoming"
        case .connecting: "connecting"
        case .active: "active"
        case .ended: "ended"
        case .missed: "missed"
        }
    }

    private var phaseTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.94, anchor: .top))
                .combined(with: .offset(y: -5)),
            removal: .opacity
                .combined(with: .scale(scale: 0.985, anchor: .top))
        )
    }
}
