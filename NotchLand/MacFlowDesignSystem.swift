//
//  MacFlowDesignSystem.swift
//  MacFlow
//
//  Semantic design tokens shared by every MacFlow module.
//

import AppKit
import SwiftUI

nonisolated enum MacFlowSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case notch
    case mouseFree
    case wallpaperEngine
    case preferences
    case about
    #if NOTCHLAND_ENABLE_DEBUG_UI
    case debug
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .notch: "Notch"
        case .mouseFree: "MouseFree"
        case .wallpaperEngine: "Wallpapers"
        case .preferences: "Preferences"
        case .about: "About MacFlow"
        #if NOTCHLAND_ENABLE_DEBUG_UI
        case .debug: "Developer"
        #endif
        }
    }

    var eyebrow: String {
        switch self {
        case .home: "MACFLOW"
        case .notch: "NOTCH WORKSPACE"
        case .mouseFree: "SCROLL TUNING"
        case .wallpaperEngine: "SCENE LIBRARY"
        case .preferences: "APPLICATION"
        case .about: "PRODUCT"
        #if NOTCHLAND_ENABLE_DEBUG_UI
        case .debug: "INTERNAL"
        #endif
        }
    }

    var detail: String {
        switch self {
        case .home: "Your Mac, coordinated from one place."
        case .notch: "Media, calls, files and live activities around the hardware notch."
        case .mouseFree: "Display-synchronised scrolling for an external mouse wheel."
        case .wallpaperEngine: "Browse, apply and tune native image and video scenes."
        case .preferences: "Shared defaults for the MacFlow application."
        case .about: "Version, updates, license and credits."
        #if NOTCHLAND_ENABLE_DEBUG_UI
        case .debug: "Diagnostics and internal feature controls."
        #endif
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .notch: "macbook"
        case .mouseFree: "computermouse.fill"
        case .wallpaperEngine: "photo.on.rectangle.angled"
        case .preferences: "gearshape.fill"
        case .about: "info.circle.fill"
        #if NOTCHLAND_ENABLE_DEBUG_UI
        case .debug: "hammer.fill"
        #endif
        }
    }

    @MainActor var accent: Color {
        switch self {
        case .home, .preferences, .about: MacFlowColor.accent
        case .notch: MacFlowColor.notch
        case .mouseFree: MacFlowColor.mouseFree
        case .wallpaperEngine: MacFlowColor.wallpaper
        #if NOTCHLAND_ENABLE_DEBUG_UI
        case .debug: .pink
        #endif
        }
    }
}

nonisolated enum MacFlowSpacing {
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space48: CGFloat = 48
}

nonisolated enum MacFlowRadius {
    static let control: CGFloat = 9
    static let compact: CGFloat = 11
    static let panel: CGFloat = 14
    static let preview: CGFloat = 18
    static let shell: CGFloat = 22
}

nonisolated enum MacFlowMetrics {
    // Tuned for a 13-inch MacBook Air while still allowing a dense pro layout.
    static let sidebarWidth: CGFloat = 188
    static let minimumWindowWidth: CGFloat = 820
    static let idealWindowWidth: CGFloat = 980
    static let minimumWindowHeight: CGFloat = 560
    static let idealWindowHeight: CGFloat = 640
    static let pageHeaderHeight: CGFloat = 64
    static let compactHeaderHeight: CGFloat = 58
    static let settingsRowHeight: CGFloat = 50
    static let readableContentMaxWidth: CGFloat = 1_120

    // Compatibility aliases while module views migrate to semantic tokens.
    static let shellInset: CGFloat = 0
    static let detailPadding = MacFlowSpacing.space24
    static let sectionSpacing = MacFlowSpacing.space24
    static let cardRadius = MacFlowRadius.panel
    static let largeRadius = MacFlowRadius.preview
    static let compactCardRadius = MacFlowRadius.compact
    static let cardPadding = MacFlowSpacing.space16
    static let sidebarHorizontalPadding = MacFlowSpacing.space12
    static let topBarHeight = pageHeaderHeight
}

enum MacFlowColor {
    static let accent = Color.accentColor
    static let notch = Color(red: 0.32, green: 0.62, blue: 1.00)
    static let mouseFree = Color(red: 0.96, green: 0.60, blue: 0.22)
    static let wallpaper = Color(red: 0.49, green: 0.47, blue: 0.91)

    static let appBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface1 = Color(nsColor: .controlBackgroundColor)
    static let surface2 = Color(nsColor: .textBackgroundColor)
    static let surface3 = Color.accentColor.opacity(0.12)
    static let opaqueSurface1 = Color(nsColor: .controlBackgroundColor)
    static let opaqueSurface2 = Color(nsColor: .textBackgroundColor)
    static let opaqueSurface3 = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let borderSubtle = Color(nsColor: .separatorColor)
    static let borderStrong = Color(nsColor: .gridColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
}

enum MacFlowTheme {
    // Compatibility names for views being migrated in later phases.
    static let brandCyan = MacFlowColor.notch
    static let brandIndigo = MacFlowColor.accent
    static let brandViolet = MacFlowColor.wallpaper
    static let notchCyan = MacFlowColor.notch
    static let mouseAmber = MacFlowColor.mouseFree
    static let wallpaperViolet = MacFlowColor.wallpaper
    static let sidebarSurface = MacFlowColor.sidebar
    static let canvasSurface = MacFlowColor.canvas
    static let cardSurface = MacFlowColor.surface1
    static let elevatedSurface = MacFlowColor.surface2
    static let subtleStroke = MacFlowColor.borderSubtle
    static let selectedStroke = MacFlowColor.borderStrong
    static let secondaryText = MacFlowColor.textSecondary
    static let ambientGlow = Color.clear
}

struct MacFlowSurfaceModifier: ViewModifier {
    let radius: CGFloat
    var elevated = false
    var accent: Color? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        content
            .background(
                surfaceColor,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(strokeColor, lineWidth: hasIncreasedContrast ? 1.25 : 1)
            }
    }

    private var surfaceColor: Color {
        if reduceTransparency {
            return elevated ? MacFlowColor.opaqueSurface2 : MacFlowColor.opaqueSurface1
        }
        return elevated ? MacFlowColor.surface2 : MacFlowColor.surface1
    }

    private var strokeColor: Color {
        accent?.opacity(hasIncreasedContrast ? 0.42 : 0.20)
            ?? (hasIncreasedContrast ? MacFlowColor.borderStrong : MacFlowColor.borderSubtle)
    }

    private var hasIncreasedContrast: Bool { colorSchemeContrast == .increased }
}

struct MacFlowInteractiveButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.84 : 1) : 0.46)
            .animation(AppMotion.interaction(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension View {
    func macFlowSurface(
        radius: CGFloat = MacFlowRadius.panel,
        elevated: Bool = false,
        accent: Color? = nil
    ) -> some View {
        modifier(MacFlowSurfaceModifier(radius: radius, elevated: elevated, accent: accent))
    }
}
