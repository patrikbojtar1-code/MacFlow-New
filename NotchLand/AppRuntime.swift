//
//  AppRuntime.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Process-level runtime checks used to keep Xcode previews from launching
//  menu-bar panels, system monitors, and update services.
//

import Foundation

nonisolated enum AppRuntime {
    static var shouldStartApplicationServices: Bool {
        !isXcodePreview && (!isUnitTest || isUITest)
    }

    static var isUITest: Bool {
        isEnabled(ProcessInfo.processInfo.environment["MACFLOW_UI_TESTING"])
    }

    static var wallpaperSceneRootOverride: URL? {
        guard isUITest else { return nil }
        if let path = ProcessInfo.processInfo.environment["MACFLOW_UI_TEST_SCENE_ROOT"],
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("MacFlow-UITests", isDirectory: true)
    }

    static var isXcodePreview: Bool {
        let environment = ProcessInfo.processInfo.environment

        if isEnabled(environment["XCODE_RUNNING_FOR_PREVIEWS"])
            || isEnabled(environment["XCODE_RUNNING_FOR_PLAYGROUNDS"]) {
            return true
        }

        if containsPreviewMarker(CommandLine.arguments.joined(separator: " ")) {
            return true
        }

        if let bundlePath = Bundle.main.bundleURL.path.removingPercentEncoding,
           containsPreviewMarker(bundlePath) {
            return true
        }

        return environment.contains { key, value in
            key.hasPrefix("XCODE_PREVIEW")
                || containsPreviewMarker(value)
        }
    }

    static var isUnitTest: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil {
            return true
        }

        if CommandLine.arguments.contains(where: {
            $0.localizedCaseInsensitiveContains("xctest")
                || $0.localizedCaseInsensitiveContains("XCTest")
        }) {
            return true
        }

        return NSClassFromString("XCTestCase") != nil
            || NSClassFromString("XCTest.XCTestCase") != nil
    }

    private static func isEnabled(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func containsPreviewMarker(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("__preview")
            || normalized.contains("/previews/")
            || normalized.contains("xcode previews")
            || normalized.contains("com.apple.dt.xcode.previews")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
