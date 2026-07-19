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
        VStack(spacing: 0) {
            brandHeader
                .padding(.horizontal, isCollapsed ? 0 : MacFlowSpacing.space16)
                .padding(.vertical, MacFlowSpacing.space16)

            VStack(alignment: .leading, spacing: MacFlowSpacing.space16) {
                sidebarGroup(title: "Workspace", sections: [.home, .notch, .mouseFree, .wallpaperEngine])
                sidebarGroup(title: "MacFlow", sections: utilitySections)
            }
            .padding(.vertical, MacFlowSpacing.space8)

            Spacer()

            Divider()
                .padding(.horizontal, isCollapsed ? MacFlowSpacing.space4 : MacFlowSpacing.space12)

            MacFlowProfileControl(isCollapsed: isCollapsed)
                .padding(isCollapsed ? 0 : MacFlowSpacing.space12)
                .padding(.vertical, isCollapsed ? MacFlowSpacing.space12 : 0)
        }
        .background(MacFlowColor.sidebar)
        .clipped()
        .animation(AppMotion.stateChange(reduceMotion: reduceMotion), value: isCollapsed)
    }

    private var brandHeader: some View {
        HStack(spacing: 0) {
            if isCollapsed {
                Spacer(minLength: 0)
                sidebarToggle
                Spacer(minLength: 0)
            } else {
                sidebarToggle
                Text("MacFlow")
                    .font(.title3.weight(.semibold))
                    .padding(.leading, MacFlowSpacing.space8)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func sidebarGroup(title: String, sections: [MacFlowSection]) -> some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
            if !isCollapsed {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(MacFlowColor.textTertiary)
                    .tracking(0.85)
                    .padding(.horizontal, MacFlowSpacing.space16)
                    .padding(.bottom, MacFlowSpacing.space4)
                    .transition(.opacity)
            }

            ForEach(sections) { section in
                sidebarRow(for: section)
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(for section: MacFlowSection) -> some View {
        let isSelected = selection == section
        Button {
            NotchHaptics.perform(.navigation)
            withAnimation(AppMotion.interaction(reduceMotion: reduceMotion)) {
                selection = section
            }
        } label: {
            HStack(spacing: 0) {
                if !isCollapsed {
                    Rectangle()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .frame(width: 1.5, height: 16)
                        .cornerRadius(0.75)
                        .padding(.trailing, 8)
                }

                HStack(spacing: isCollapsed ? 0 : MacFlowSpacing.space8) {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : MacFlowColor.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            isSelected ? MacFlowColor.surface3 : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .frame(maxWidth: isCollapsed ? .infinity : nil)

                    if !isCollapsed {
                        Text(section.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isSelected ? .primary : MacFlowColor.textSecondary)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                .padding(.leading, isCollapsed ? 0 : 8)

                if !isCollapsed {
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowButtonStyle(isSelected: isSelected, isCollapsed: isCollapsed))
        .help(section.detail)
        .accessibilityLabel(section.title)
        .accessibilityHint(section.detail)
        .accessibilityIdentifier("sidebar.\(section.rawValue)")
    }

    private var sidebarToggle: some View {
        Button(action: onToggleSidebar) {
            Image(systemName: isCollapsed ? "sidebar.right" : "sidebar.left")
                .frame(width: 24, height: 24)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(isCollapsed ? "Show Sidebar" : "Hide Sidebar")
        .accessibilityLabel(isCollapsed ? "Show Sidebar" : "Hide Sidebar")
        .accessibilityIdentifier("sidebar.toggle")
    }

    private var utilitySections: [MacFlowSection] {
        var sections: [MacFlowSection] = [.preferences, .about]
        #if NOTCHLAND_ENABLE_DEBUG_UI
        if showsDebug { sections.append(.debug) }
        #endif
        return sections
    }
}

struct SidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isCollapsed: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let backgroundColor: Color = {
            if isSelected {
                return Color.clear
            } else if configuration.isPressed {
                return Color.secondary.opacity(0.12)
            } else if isHovered {
                return Color.secondary.opacity(0.06)
            } else {
                return Color.clear
            }
        }()

        return configuration.label
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .padding(.horizontal, isCollapsed ? 4 : 8)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

private struct MacFlowProfileControl: View {
    let isCollapsed: Bool

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
            HStack(spacing: isCollapsed ? 0 : MacFlowSpacing.space8) {
                if isCollapsed {
                    Spacer(minLength: 0)
                    avatar
                    Spacer(minLength: 0)
                } else {
                    avatar

                    VStack(alignment: .leading, spacing: 1) {
                        Text(isSignedIn ? resolvedName : "Local profile")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(isSignedIn ? "Signed in on this Mac" : "Sign in")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .transition(.opacity)

                    Spacer(minLength: MacFlowSpacing.space4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
            .padding(isCollapsed ? 0 : MacFlowSpacing.space8)
            .frame(height: isCollapsed ? 36 : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isCollapsed ? Color.clear : MacFlowColor.surface1,
            in: RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
        )
        .overlay {
            if !isCollapsed {
                RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                    .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
            }
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
