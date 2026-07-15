//
//  FileShelfView.swift
//  NotchLand
//

import AppKit
import SwiftUI

enum FileShelfMetrics {
    nonisolated static let dropSize = CGSize(width: 300, height: 138)
    nonisolated static let expandedSize = CGSize(width: 560, height: 242)
    nonisolated static let cardSize = CGSize(width: 118, height: 146)
}

struct FileShelfDropZoneView: View {
    @EnvironmentObject private var shelf: FileShelfController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private let tint = Color(red: 0.28, green: 0.64, blue: 1)

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if !shelf.isHoveringDropZone {
                    Circle()
                        .stroke(tint.opacity(0.45), lineWidth: 1.4)
                        .frame(width: 36, height: 36)
                        .scaleEffect(isPulsing ? 1.65 : 1)
                        .opacity(isPulsing ? 0 : 0.7)
                }

                Image(systemName: shelf.isHoveringDropZone ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(shelf.isHoveringDropZone ? tint : .white)
                    .symbolEffect(.bounce, value: shelf.isHoveringDropZone)
            }
            .frame(width: 46, height: 46)

            Text(shelf.isHoveringDropZone ? "Release to add" : "Drop files into Shelf")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(shelf.isHoveringDropZone ? tint : .white.opacity(0.88))

            Text("Files stay on this Mac")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.46))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tint.opacity(shelf.isHoveringDropZone ? 0.18 : 0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    shelf.isHoveringDropZone ? tint.opacity(0.9) : .white.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 7])
                )
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .animation(NotchMotion.dropTarget, value: shelf.isHoveringDropZone)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(NotchAmbientMotion.shimmer()) {
                isPulsing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("File Shelf drop zone")
        .accessibilityHint("Drop files to keep them in NotchLand")
    }
}

struct FileShelfView: View {
    @EnvironmentObject private var shelf: FileShelfController
    @EnvironmentObject private var airDrop: AirDropController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var intelligence: DropIntelligenceController
    @EnvironmentObject private var shortcuts: ShortcutsBridgeController
    @EnvironmentObject private var preferences: WidgetPreferencesController
    @AppStorage("notch.selectedWidget") private var selectedWidgetRaw = NotchWidget.files.rawValue

    var body: some View {
        VStack(spacing: 8) {
            header

            if let analysis = intelligence.current {
                intelligenceBanner(analysis)
                    .transition(.notchSection)
            }

            if shelf.items.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            FileShelfCard(item: item)
                                .environmentObject(shelf)
                                .environmentObject(airDrop)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchMotion.contentOpen, value: intelligence.current)
    }

    private func intelligenceBanner(_ analysis: DropAnalysis) -> some View {
        HStack(spacing: 9) {
            Image(systemName: analysis.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
                .background(.blue.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(analysis.kind.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Text(analysis.detail)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            ForEach(analysis.suggestions) { suggestion in
                Button {
                    perform(suggestion, analysis: analysis)
                } label: {
                    Label(suggestion.title, systemImage: suggestion.symbol)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .labelStyle(.iconOnly)
                        .frame(width: 27, height: 24)
                        .background(.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(suggestion.title)
            }

            Button(action: intelligence.dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .frame(height: 38)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.blue.opacity(0.16), lineWidth: 1)
        }
    }

    private func perform(_ suggestion: DropSuggestedAction, analysis: DropAnalysis) {
        switch suggestion {
        case .quickLook:
            guard let first = analysis.items.first else { return }
            shelf.quickLook(first)
        case .airDrop:
            airDrop.shareViaAirDrop(analysis.urls)
        case .reveal:
            guard let first = analysis.items.first else { return }
            shelf.revealInFinder(first)
        case .copyPaths:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                analysis.urls.map(\.path).joined(separator: "\n"),
                forType: .string
            )
            NotchHaptics.perform(.confirmation)
        case .shortcuts:
            shortcuts.prepareInput(analysis.urls)
            preferences.setMode(.pinned, for: .shortcuts)
            shelf.isPresented = false
            selectedWidgetRaw = NotchWidget.shortcuts.rawValue
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full.fill")
                .foregroundStyle(.blue)
            Text("File Shelf")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text("\(shelf.items.count)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.white.opacity(0.08), in: Capsule())

            Spacer()

            if !shelf.items.isEmpty {
                Button("Clear", role: .destructive) { shelf.removeAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Button {
                shelf.dismiss()
                appState.collapse()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close File Shelf")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Drop files onto the notch")
                .font(.system(size: 12, weight: .semibold))
            Text("They will remain here after relaunch.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FileShelfCard: View {
    let item: FileShelfItem
    @EnvironmentObject private var shelf: FileShelfController
    @EnvironmentObject private var airDrop: AirDropController
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(item.isDirectory ? .blue : .white.opacity(0.72))
                .frame(width: 62, height: 58)
                .background(
                    LinearGradient(
                        colors: item.isDirectory
                            ? [.blue.opacity(0.18), .cyan.opacity(0.06)]
                            : [.white.opacity(0.1), .white.opacity(0.035)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .shadow(color: .black.opacity(0.28), radius: 6, y: 3)

            Text(item.displayName)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(item.metadataDescription)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                cardButton("eye.fill", label: "Quick Look") {
                    shelf.quickLook(item)
                }
                cardButton("paperplane.fill", label: "AirDrop") {
                    airDrop.shareViaAirDrop([item.url])
                }
                cardButton("folder.fill", label: "Reveal in Finder") {
                    shelf.revealInFinder(item)
                }
                cardButton("xmark", label: "Remove", role: .destructive) {
                    shelf.remove(item)
                }
            }
            .opacity(isHovering ? 1 : 0.55)
        }
        .padding(10)
        .frame(width: FileShelfMetrics.cardSize.width, height: FileShelfMetrics.cardSize.height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.12 : 0.065))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(isHovering ? 0.18 : 0.08), lineWidth: 1)
        }
        .scaleEffect(isHovering ? 1.025 : 1)
        .animation(NotchMotion.hover, value: isHovering)
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { shelf.quickLook(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .focusable()
        .onKeyPress(.space) {
            shelf.quickLook(item)
            return .handled
        }
        .contextMenu {
            Button("Quick Look") { shelf.quickLook(item) }
            Button("AirDrop") { airDrop.shareViaAirDrop([item.url]) }
            Button("Reveal in Finder") { shelf.revealInFinder(item) }
            Divider()
            Button("Remove", role: .destructive) { shelf.remove(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.displayName)
        .accessibilityHint("Drag to another app or open the context menu for actions")
    }

    private func cardButton(
        _ systemName: String,
        label: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 15, height: 15)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
