//
//  QuickActionsView.swift
//  NotchLand
//

import AppKit
import SwiftUI

struct QuickActionsView: View {
    @EnvironmentObject private var actions: QuickActionsController

    private let rows = [
        GridItem(.fixed(64), spacing: 8),
        GridItem(.fixed(64), spacing: 8),
    ]

    var body: some View {
        VStack(spacing: 10) {
            header
            actionGrid
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.purple)
            Text("Quick Actions")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("\(actions.items.count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .frame(height: 19)
                .background(.white.opacity(0.07), in: Capsule())

            Spacer()

            Button {
                actions.chooseApplications()
            } label: {
                Label("Add App", systemImage: "plus")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var actionGrid: some View {
        ScrollView(.horizontal) {
            LazyHGrid(rows: rows, spacing: 8) {
                ForEach(actions.items) { item in
                    actionButton(item)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    private func actionButton(_ item: QuickActionItem) -> some View {
        Button {
            actions.launch(item)
        } label: {
            HStack(spacing: 9) {
                actionIcon(item)
                    .frame(width: 29, height: 29)

                Text(item.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: 126, height: 64)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .opacity(actions.launchingID == item.id ? 0.55 : 1)
            .scaleEffect(actions.launchingID == item.id ? 0.94 : 1)
        }
        .buttonStyle(.plain)
        .animation(NotchMotion.selection, value: actions.launchingID)
        .contextMenu {
            Button("Open") { actions.launch(item) }
            if !item.isBuiltIn {
                Divider()
                Button("Remove", role: .destructive) { actions.remove(item) }
            }
        }
        .accessibilityHint("Launches \(item.title)")
    }

    @ViewBuilder
    private func actionIcon(_ item: QuickActionItem) -> some View {
        if case let .application(path) = item.destination,
           FileManager.default.fileExists(atPath: path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: item.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.purple.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

