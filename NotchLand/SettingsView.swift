//
//  SettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Compatibility entry point for the unified MacFlow Hub.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        MacFlowHubView()
    }
}

#if DEBUG
#Preview("Settings") {
    NotchPreviewContainer {
        SettingsView()
            .frame(width: MacFlowMetrics.idealWindowWidth, height: MacFlowMetrics.idealWindowHeight)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
