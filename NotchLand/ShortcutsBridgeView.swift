//
//  ShortcutsBridgeView.swift
//  NotchLand
//

import AppKit
import SwiftUI

struct ShortcutsBridgeView: View {
    @EnvironmentObject private var bridge: ShortcutsBridgeController
    @EnvironmentObject private var shelf: FileShelfController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            header

            Group {
                if bridge.isLoading && bridge.shortcuts.isEmpty {
                    skeleton
                } else if bridge.shortcuts.isEmpty {
                    emptyState
                } else {
                    shortcutList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusFooter
        }
        .padding(.horizontal, 24)
        .padding(.top, 11)
        .padding(.bottom, 7)
        .task {
            if bridge.shortcuts.isEmpty {
                await bridge.refresh()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcuts Bridge")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("Run your Apple Shortcuts without leaving the notch")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !bridge.preparedInputURLs.isEmpty {
                Button {
                    bridge.clearPreparedInput()
                } label: {
                    Label("\(bridge.preparedInputURLs.count) ready", systemImage: "xmark.circle.fill")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Clear prepared Shelf input")
            }
            if !bridge.shortcuts.isEmpty {
                Text("\(bridge.shortcuts.count)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(.purple.opacity(0.12), in: Capsule())
            }
            Button {
                Task { await bridge.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(bridge.isLoading && !reduceMotion ? 360 : 0))
                    .animation(
                        bridge.isLoading && !reduceMotion
                            ? NotchAmbientMotion.spinner()
                            : NotchMotionGraph.reduced.animation,
                        value: bridge.isLoading
                    )
            }
            .buttonStyle(.plain)
            .disabled(bridge.isLoading)
            .help("Refresh Shortcuts")
        }
    }

    private var shortcutList: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 7
            ) {
                ForEach(bridge.orderedShortcuts) { shortcut in
                    shortcutCard(shortcut)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func shortcutCard(_ shortcut: NotchShortcut) -> some View {
        let isRunning = bridge.runningShortcutName == shortcut.name
        let isFavorite = bridge.favoriteNames.contains(shortcut.name)

        return HStack(spacing: 9) {
            Button {
                Task { await bridge.run(shortcut) }
            } label: {
                Image(systemName: isRunning ? "ellipsis" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 27, height: 27)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .symbolEffect(.pulse, isActive: isRunning && !reduceMotion)
            }
            .buttonStyle(.plain)
            .disabled(bridge.runningShortcutName != nil)

            Text(shortcut.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 2)
            Button {
                bridge.toggleFavorite(shortcut)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isFavorite ? .yellow : .white.opacity(0.26))
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")

            if !effectiveInputURLs.isEmpty {
                Button {
                    Task { await bridge.run(shortcut, inputURLs: effectiveInputURLs) }
                } label: {
                    Image(systemName: "tray.and.arrow.up.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(bridge.runningShortcutName != nil)
                .help("Run with \(effectiveInputURLs.count) item\(effectiveInputURLs.count == 1 ? "" : "s")")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 39)
        .background(
            isRunning ? Color.purple.opacity(0.13) : Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isRunning ? .purple.opacity(0.28) : .white.opacity(0.05), lineWidth: 1)
        }
        .animation(NotchMotion.selection, value: isRunning)
    }

    private var effectiveInputURLs: [URL] {
        bridge.preparedInputURLs.isEmpty ? shelf.items.map(\.url) : bridge.preparedInputURLs
    }

    private var skeleton: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 9) {
                    Circle().frame(width: 27, height: 27)
                    RoundedRectangle(cornerRadius: 4).frame(width: 78, height: 9)
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.08))
                .padding(.horizontal, 9)
                .frame(height: 39)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .opacity(0.75)
        .accessibilityLabel("Loading Shortcuts")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.purple.opacity(0.7))
            Text(bridge.errorMessage ?? "No shortcuts found")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button("Open Shortcuts") {
                if let url = URL(string: "shortcuts://") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .buttonStyle(.plain)
            .foregroundStyle(.purple)
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        if let running = bridge.runningShortcutName {
            Label(
                bridge.runningInputCount > 0
                    ? "Running \(running) with \(bridge.runningInputCount) item\(bridge.runningInputCount == 1 ? "" : "s")…"
                    : "Running \(running)…",
                systemImage: "bolt.horizontal.circle.fill"
            )
                .foregroundStyle(.purple)
        } else if let error = bridge.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if let result = bridge.lastResult {
            Label(result, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}
