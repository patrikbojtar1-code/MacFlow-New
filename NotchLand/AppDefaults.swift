//
//  AppDefaults.swift
//  MacFlow
//
//  A single preferences store for production and isolated UI-test runs.
//

import Foundation

nonisolated enum AppDefaults {
    static let store: UserDefaults = {
        guard AppRuntime.isUITest else { return .standard }

        let suiteName = "com.rudrashah.MacFlow.UITests"
        guard let store = UserDefaults(suiteName: suiteName) else {
            return .standard
        }
        store.removePersistentDomain(forName: suiteName)
        return store
    }()
}
