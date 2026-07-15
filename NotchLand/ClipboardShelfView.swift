//
//  ClipboardShelfView.swift
//  NotchLand
//

import SwiftUI

struct ClipboardShelfView: View {
    @EnvironmentObject private var clipboard: ClipboardController

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        VStack(spacing: 12) {
            header

            if clipboard.items.isEmpty {
                emptyState
            } else {
                clipboardCards
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundStyle(.cyan)
            Text("Clipboard")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("\(clipboard.items.count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .frame(height: 19)
                .background(.white.opacity(0.07), in: Capsule())

            Spacer()

            if clipboard.items.contains(where: { !$0.isPinned }) {
                Button("Clear") {
                    withAnimation(NotchMotion.selection) { clipboard.clearUnpinned() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            }

            Button {
                clipboard.setMonitoringEnabled(!clipboard.isMonitoring)
            } label: {
                Label(
                    clipboard.isMonitoring ? "Live" : "Paused",
                    systemImage: clipboard.isMonitoring ? "record.circle.fill" : "pause.circle.fill"
                )
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(clipboard.isMonitoring ? .green : .orange)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(clipboard.isMonitoring ? "Pause clipboard history" : "Resume clipboard history")
        }
    }

    private var clipboardCards: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 9) {
                ForEach(clipboard.items) { item in
                    card(for: item)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    private func card(for item: ClipboardItem) -> some View {
        Button {
            clipboard.copy(item)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: item.isPinned ? "pin.fill" : "text.alignleft")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(item.isPinned ? .yellow : .cyan)
                    Spacer()
                    Text(relativeDate(item.copiedAt))
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                Text(item.text)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Spacer(minLength: 0)

                HStack {
                    Text(item.lineCount == 1 ? "Text" : "\(item.lineCount) lines")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(11)
            .frame(width: 158, height: 132, alignment: .topLeading)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy") { clipboard.copy(item) }
            Button(item.isPinned ? "Unpin" : "Pin") { clipboard.togglePinned(item) }
            Divider()
            Button("Delete", role: .destructive) { clipboard.delete(item) }
        }
        .accessibilityHint("Copies this item to the clipboard")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: clipboard.isMonitoring ? "doc.on.clipboard" : "pause.circle")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(.secondary)
            Text(clipboard.isMonitoring ? "Copy text to see it here" : "Clipboard history is paused")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("Stored locally on this Mac")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func relativeDate(_ date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: .now)
    }
}
