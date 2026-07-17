//
//  MacFlowSidebarView.swift
//  MacFlow
//
//  System sidebar navigation with native selection, focus, and keyboard behavior.
//

import AppKit
import OpenDirectory
import SwiftUI

struct MacFlowSidebarView: View {
    @Binding var selection: MacFlowSection
    let showsDebug: Bool
    let isCollapsed: Bool
    let onToggleSidebar: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isCollapsed {
                collapsedRail
                    .transition(.opacity)
            } else {
                expandedSidebar
                    .transition(.opacity)
            }
        }
        .background(MacFlowColor.sidebar)
        .clipped()
    }

    private var selectionBinding: Binding<MacFlowSection?> {
        Binding(
            get: { selection },
            set: { newSelection in
                guard let newSelection, newSelection != selection else { return }
                NotchHaptics.perform(.navigation)
                withAnimation(AppMotion.interaction(reduceMotion: reduceMotion)) {
                    selection = newSelection
                }
            }
        )
    }

    private var brand: some View {
        HStack(spacing: MacFlowSpacing.space8) {
            sidebarToggle
            Text("MacFlow")
                .font(.title3.weight(.semibold))
            Spacer(minLength: 0)
        }
    }

    private var expandedSidebar: some View {
        VStack(spacing: 0) {
            brand
                .padding(.horizontal, MacFlowSpacing.space16)
                .padding(.vertical, MacFlowSpacing.space16)

            List(selection: selectionBinding) {
                Section("Workspace") {
                    rows([.home, .notch, .mouseFree, .wallpaperEngine])
                }

                Section("MacFlow") {
                    rows(utilitySections)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .padding(.horizontal, MacFlowSpacing.space12)

            MacFlowProfileControl()
                .padding(MacFlowSpacing.space12)
        }
    }

    private var collapsedRail: some View {
        VStack(spacing: 0) {
            sidebarToggle
                .padding(.top, MacFlowSpacing.space16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebarToggle: some View {
        Button(action: onToggleSidebar) {
            Image(systemName: isCollapsed ? "sidebar.right" : "sidebar.left")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(isCollapsed ? "Show Sidebar" : "Hide Sidebar")
        .accessibilityLabel(isCollapsed ? "Show Sidebar" : "Hide Sidebar")
        .accessibilityIdentifier("sidebar.toggle")
    }

    @ViewBuilder
    private func rows(_ sections: [MacFlowSection]) -> some View {
        ForEach(sections) { section in
            Label(section.title, systemImage: section.systemImage)
                .symbolRenderingMode(.hierarchical)
                .tag(section)
                .help(section.detail)
                .accessibilityHint(section.detail)
                .accessibilityIdentifier("sidebar.\(section.rawValue)")
        }
    }

    private var utilitySections: [MacFlowSection] {
        var sections: [MacFlowSection] = [.preferences, .about]
        #if NOTCHLAND_ENABLE_DEBUG_UI
        if showsDebug { sections.append(.debug) }
        #endif
        return sections
    }
}

private struct MacFlowProfileControl: View {
    @AppStorage("macflow.profile.isSignedIn", store: AppDefaults.store)
    private var isSignedIn = false
    @AppStorage("macflow.profile.displayName", store: AppDefaults.store)
    private var displayName = ""
    @AppStorage("macflow.profile.email", store: AppDefaults.store)
    private var email = ""

    @State private var showsProfile = false
    @State private var draftName = ""
    @State private var draftEmail = ""
    @State private var accountImage: NSImage?

    var body: some View {
        Button {
            draftName = displayName.isEmpty ? suggestedName : displayName
            draftEmail = email
            showsProfile.toggle()
        } label: {
            HStack(spacing: MacFlowSpacing.space8) {
                avatar

                VStack(alignment: .leading, spacing: 1) {
                    Text(isSignedIn ? resolvedName : "Local profile")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(isSignedIn ? "Signed in on this Mac" : "Sign in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: MacFlowSpacing.space4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(MacFlowSpacing.space8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MacFlowColor.surface1, in: RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
        }
        .popover(isPresented: $showsProfile, arrowEdge: .trailing) {
            profilePopover
        }
        .task { accountImage = MacAccountAvatarLoader.load() }
        .accessibilityLabel(isSignedIn ? "Profile, \(resolvedName)" : "Sign in to local profile")
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(MacFlowColor.accent.opacity(0.14))
            if let accountImage {
                Image(nsImage: accountImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else if isSignedIn {
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MacFlowColor.accent)
            } else {
                Image(systemName: "person.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MacFlowColor.textSecondary)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    private var profilePopover: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space16) {
            if isSignedIn {
                HStack(spacing: MacFlowSpacing.space12) {
                    avatar.frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(resolvedName).font(.headline)
                        if !email.isEmpty {
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Text("Profile data is stored only on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Sign Out", role: .destructive) {
                    isSignedIn = false
                    showsProfile = false
                }
            } else {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                    Text("Local profile").font(.headline)
                    Text("Personalizes MacFlow without an online account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("Name", text: $draftName)
                TextField("Email (optional)", text: $draftEmail)

                HStack {
                    Spacer()
                    Button("Cancel") { showsProfile = false }
                    Button("Sign In") { saveProfile() }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(MacFlowSpacing.space16)
        .frame(width: 280)
    }

    private var suggestedName: String {
        let name = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Mac user" : name
    }

    private var resolvedName: String { displayName.isEmpty ? suggestedName : displayName }

    private var initials: String {
        resolvedName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private func saveProfile() {
        displayName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        email = draftEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        isSignedIn = true
        showsProfile = false
        NotchHaptics.perform(.confirmation)
    }
}

private enum MacAccountAvatarLoader {
    static func load() -> NSImage? {
        guard let node = try? ODNode(session: .default(), type: UInt32(kODNodeTypeLocalNodes)),
              let query = try? ODQuery(
                node: node,
                forRecordTypes: kODRecordTypeUsers,
                attribute: kODAttributeTypeRecordName,
                matchType: ODMatchType(kODMatchEqualTo),
                queryValues: NSUserName(),
                returnAttributes: kODAttributeTypeJPEGPhoto,
                maximumResults: 1
              ),
              let record = (try? query.resultsAllowingPartial(false))?.first as? ODRecord,
              let values = try? record.values(forAttribute: kODAttributeTypeJPEGPhoto),
              let data = values.first as? Data else {
            return nil
        }
        return NSImage(data: data)
    }
}
