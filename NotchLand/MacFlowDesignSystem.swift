//
//  MacFlowDesignSystem.swift
//  MacFlow
//
//  Semantic design tokens shared by every MacFlow module.
//

import SwiftUI

nonisolated enum MacFlowSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case notch
    case mouseFree
    case wallpaperEngine
    case preferences
    case about
    #if DEBUG
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
        #if DEBUG
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
        #if DEBUG
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
        #if DEBUG
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
        #if DEBUG
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
        #if DEBUG
        case .debug: .pink
        #endif
        }
    }
}

nonisolated enum MacFlowSpacing {
    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space6: CGFloat = 6
    static let space8: CGFloat = 8
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
}

nonisolated enum MacFlowRadius {
    static let control: CGFloat = 9
    static let compact: CGFloat = 11
    static let panel: CGFloat = 14
    static let preview: CGFloat = 18
    static let shell: CGFloat = 22
}

nonisolated enum MacFlowMetrics {
    static let sidebarWidth: CGFloat = 224
    static let inspectorWidth: CGFloat = 304
    static let minimumWindowWidth: CGFloat = 1_080
    static let idealWindowWidth: CGFloat = 1_240
    static let minimumWindowHeight: CGFloat = 700
    static let idealWindowHeight: CGFloat = 780
    static let pageHeaderHeight: CGFloat = 76
    static let compactHeaderHeight: CGFloat = 68
    static let settingsRowHeight: CGFloat = 58

    // Compatibility aliases while module views migrate to semantic tokens.
    static let shellInset: CGFloat = 0
    static let detailPadding = MacFlowSpacing.space24
    static let sectionSpacing = MacFlowSpacing.space20
    static let cardRadius = MacFlowRadius.panel
    static let largeRadius = MacFlowRadius.preview
    static let compactCardRadius = MacFlowRadius.compact
    static let cardPadding = MacFlowSpacing.space16
    static let sidebarHorizontalPadding = MacFlowSpacing.space12
    static let topBarHeight = pageHeaderHeight
}

enum MacFlowColor {
    static let accent = Color(red: 0.30, green: 0.55, blue: 1.00)
    static let notch = Color(red: 0.32, green: 0.62, blue: 1.00)
    static let mouseFree = Color(red: 0.96, green: 0.60, blue: 0.22)
    static let wallpaper = Color(red: 0.49, green: 0.47, blue: 0.91)

    static let appBackground = Color(red: 0.047, green: 0.051, blue: 0.063)
    static let sidebar = Color(red: 0.067, green: 0.075, blue: 0.094)
    static let canvas = Color(red: 0.057, green: 0.064, blue: 0.078)
    static let surface1 = Color.white.opacity(0.035)
    static let surface2 = Color.white.opacity(0.055)
    static let surface3 = Color.white.opacity(0.075)
    static let opaqueSurface1 = Color(red: 0.078, green: 0.086, blue: 0.103)
    static let opaqueSurface2 = Color(red: 0.094, green: 0.102, blue: 0.120)
    static let opaqueSurface3 = Color(red: 0.112, green: 0.120, blue: 0.139)
    static let borderSubtle = Color.white.opacity(0.070)
    static let borderStrong = Color.white.opacity(0.120)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.42)
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

nonisolated enum MacFlowMotion {
    static func selection(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.10)
            : .spring(response: 0.30, dampingFraction: 0.92, blendDuration: 0)
    }

    static func content(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.36, dampingFraction: 0.94, blendDuration: 0)
    }

    static func hover(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.08 : 0.12)
    }
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
            .animation(MacFlowMotion.hover(reduceMotion: reduceMotion), value: configuration.isPressed)
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
