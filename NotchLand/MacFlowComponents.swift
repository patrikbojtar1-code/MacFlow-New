//
//  MacFlowComponents.swift
//  MacFlow
//
//  Reusable product components for headers, panels, settings, and states.
//

import SwiftUI

enum MacFlowPanelKind: Equatable {
    case plain
    case grouped
    case elevated
    case inspector
}

struct MacFlowPanel<Content: View>: View {
    let kind: MacFlowPanelKind
    let content: Content

    init(
        _ kind: MacFlowPanelKind = .grouped,
        @ViewBuilder content: () -> Content
    ) {
        self.kind = kind
        self.content = content()
    }

    var body: some View {
        content
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if kind != .plain {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
                }
            }
    }

    private var background: Color {
        switch kind {
        case .plain: .clear
        case .grouped, .inspector: MacFlowColor.surface1
        case .elevated: MacFlowColor.surface2
        }
    }

    private var radius: CGFloat {
        switch kind {
        case .plain: 0
        case .grouped, .inspector: MacFlowRadius.panel
        case .elevated: MacFlowRadius.preview
        }
    }
}

struct MacFlowPageHeader<Actions: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    let actions: Actions

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: MacFlowSpacing.space20) {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(MacFlowColor.textTertiary)
                    .tracking(1.05)
                Text(title)
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.35)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(MacFlowColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: MacFlowSpacing.space16)
            actions
        }
        .padding(.horizontal, MacFlowSpacing.space24)
        .frame(minHeight: MacFlowMetrics.pageHeaderHeight)
    }
}

extension MacFlowPageHeader where Actions == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct MacFlowSectionHeader<Trailing: View>: View {
    let title: String
    let detail: String?
    let trailing: Trailing

    init(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MacFlowSpacing.space12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MacFlowColor.textSecondary)
                .tracking(0.85)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(MacFlowColor.textTertiary)
            }
            Spacer()
            trailing
        }
    }
}

extension MacFlowSectionHeader where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil) {
        self.init(title, detail: detail) { EmptyView() }
    }
}

struct MacFlowSettingsGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        MacFlowPanel(.grouped) {
            VStack(spacing: 0) { content }
        }
    }
}

struct MacFlowSettingsRow<Trailing: View>: View {
    let icon: String?
    let tint: Color
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(
        icon: String? = nil,
        tint: Color = MacFlowColor.accent,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: MacFlowSpacing.space12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 31, height: 31)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: MacFlowSpacing.space2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(MacFlowColor.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: MacFlowSpacing.space12)
            trailing
        }
        .padding(.horizontal, MacFlowSpacing.space16)
        .frame(minHeight: MacFlowMetrics.settingsRowHeight)
    }
}

struct MacFlowInsetDivider: View {
    var leading: CGFloat = 59

    var body: some View {
        Rectangle()
            .fill(MacFlowColor.borderSubtle)
            .frame(height: 1)
            .padding(.leading, leading)
    }
}

struct MacFlowStatusPill: View {
    let title: String
    let systemImage: String?
    let color: Color

    var body: some View {
        HStack(spacing: MacFlowSpacing.space6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            } else {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, MacFlowSpacing.space10)
        .padding(.vertical, MacFlowSpacing.space6)
        .background(color.opacity(0.10), in: Capsule())
    }
}

struct MacFlowEmptyState: View {
    let systemImage: String
    let title: String
    let detail: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        systemImage: String,
        title: String,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: MacFlowSpacing.space12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MacFlowColor.textTertiary)
            VStack(spacing: MacFlowSpacing.space4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(MacFlowColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(MacFlowColor.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MacFlowSpacing.space32)
    }
}

struct MacFlowInspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(MacFlowColor.textTertiary)
                .tracking(0.75)
            content
        }
        .padding(MacFlowSpacing.space16)
    }
}
