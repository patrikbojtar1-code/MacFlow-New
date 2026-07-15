//
//  WidgetSettingsView.swift
//  NotchLand
//

import SwiftUI

struct WidgetSettingsView: View {
    @EnvironmentObject private var preferences: WidgetPreferencesController

    var body: some View {
        Form {
            Section("Dashboard Widgets") {
                ForEach(preferences.orderedWidgets) { widget in
                    widgetRow(widget)
                }
            }

            Section {
                Button("Restore Default Widgets") {
                    preferences.reset()
                }
            } footer: {
                Text("Pinned modules stay in the top rail. Automatic modules appear only when relevant. At least one module must remain available.")
            }
        }
        .formStyle(.grouped)
    }

    private func widgetRow(_ widget: NotchWidget) -> some View {
        HStack(spacing: 10) {
            Image(systemName: widget.symbol)
                .frame(width: 22)
                .foregroundStyle(preferences.mode(for: widget) == .hidden ? .secondary : .primary)

            Text(widget.title)

            Spacer()

            Picker(
                "Visibility",
                selection: Binding(
                    get: { preferences.mode(for: widget) },
                    set: { preferences.setMode($0, for: widget) }
                )
            ) {
                ForEach(WidgetVisibilityMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol)
                        .tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 126)

            Button {
                preferences.move(widget, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(preferences.orderedWidgets.first == widget)
            .accessibilityLabel("Move \(widget.title) earlier")

            Button {
                preferences.move(widget, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(preferences.orderedWidgets.last == widget)
            .accessibilityLabel("Move \(widget.title) later")
        }
    }
}

#if DEBUG
#Preview("Widget Settings") {
    NotchPreviewContainer {
        WidgetSettingsView()
            .frame(width: 510, height: 520)
    }
}
#endif
