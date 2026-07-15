//
//  NotchTimelineView.swift
//  NotchLand
//

import SwiftUI

struct NotchTimelineView: View {
    @EnvironmentObject private var events: NotchEventCenter

    var body: some View {
        VStack(spacing: 10) {
            header

            if let current = events.current {
                nowCard(current)
                    .transition(.notchSection)
            }

            if events.history.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(events.history) { event in
                            eventRow(event)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .onAppear { events.markAllRead() }
        .animation(NotchMotion.contentOpen, value: events.current?.id)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Timeline")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("Everything that appeared in your notch")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !events.pending.isEmpty {
                Label("\(events.pending.count) queued", systemImage: "square.stack.3d.up.fill")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
            }
            Button("Clear", action: events.clearHistory)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.46))
                .disabled(events.history.isEmpty)
        }
    }

    private func nowCard(_ event: NotchEvent) -> some View {
        HStack(spacing: 9) {
            Text("NOW")
                .font(.system(size: 7, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.black)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(accent(for: event.source), in: Capsule())
            Image(systemName: event.symbol)
                .foregroundStyle(accent(for: event.source))
            Text(event.title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer()
            Button("Skip", action: events.dismissCurrent)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.48))
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(accent(for: event.source).opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(accent(for: event.source).opacity(0.18), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
            Text("New payments, calls and live activities will stay here.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func eventRow(_ event: NotchEvent) -> some View {
        HStack(spacing: 11) {
            Image(systemName: event.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent(for: event.source))
                .frame(width: 30, height: 30)
                .background(accent(for: event.source).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if !event.isRead {
                        Circle().fill(accent(for: event.source)).frame(width: 5, height: 5)
                    }
                }
                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let progress = event.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(accent(for: event.source))
                        .frame(maxWidth: 150)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text(event.source.title.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(accent(for: event.source))
                Text(event.updatedAt, style: .relative)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 43)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { events.markRead(event) }
    }

    private func accent(for source: NotchEventSource) -> Color {
        switch source {
        case .wallet: .orange
        case .call: .green
        case .battery: .mint
        case .focus: .purple
        case .liveActivity: .blue
        case .calendar: .red
        case .files: .cyan
        case .system: .white
        case .integration: .pink
        }
    }
}
