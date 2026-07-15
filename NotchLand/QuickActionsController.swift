//
//  QuickActionsController.swift
//  NotchLand
//
//  Persistent application and destination launcher for the expanded notch.
//

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum QuickActionDestination: Codable, Equatable {
    case application(path: String)
    case folder(path: String)
    case webURL(String)
}

struct QuickActionItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var symbol: String
    var destination: QuickActionDestination
    var isBuiltIn: Bool
    let dateAdded: Date
}

@MainActor
final class QuickActionsController: ObservableObject {
    @Published private(set) var items: [QuickActionItem] = []
    @Published private(set) var launchingID: UUID?

    private enum Constants {
        static let storageKey = "quickActions.items.v1"
        static let maximumItemCount = 16
    }

    private let defaults: UserDefaults
    private let workspace: NSWorkspace

    init(
        defaults: UserDefaults = .standard,
        workspace: NSWorkspace = .shared
    ) {
        self.defaults = defaults
        self.workspace = workspace
        restore()
    }

    func launch(_ item: QuickActionItem) {
        guard items.contains(where: { $0.id == item.id }), launchingID == nil else { return }
        launchingID = item.id

        switch item.destination {
        case let .application(path):
            let url = URL(fileURLWithPath: path)
            Task { [weak self] in
                do {
                    try await self?.workspace.openApplication(
                        at: url,
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                    self?.finishLaunch(succeeded: true)
                } catch {
                    self?.finishLaunch(succeeded: false)
                }
            }

        case let .folder(path):
            finishLaunch(succeeded: workspace.open(URL(fileURLWithPath: path, isDirectory: true)))

        case let .webURL(rawValue):
            guard let url = URL(string: rawValue) else {
                finishLaunch(succeeded: false)
                return
            }
            finishLaunch(succeeded: workspace.open(url))
        }
    }

    func chooseApplications() {
        let panel = NSOpenPanel()
        panel.title = "Add apps to Quick Actions"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else { return }
        let addedCount = addApplications(panel.urls)
        NotchHaptics.perform(addedCount > 0 ? .confirmation : .navigation)
    }

    @discardableResult
    func addApplications(_ urls: [URL], at date: Date = .now) -> Int {
        let existingPaths = Set(items.compactMap { item -> String? in
            guard case let .application(path) = item.destination else { return nil }
            return URL(fileURLWithPath: path).standardizedFileURL.path
        })

        var pendingPaths = Set<String>()
        let additions = urls.compactMap { rawURL -> QuickActionItem? in
            let url = rawURL.standardizedFileURL
            let path = url.path
            guard url.pathExtension.lowercased() == "app",
                  FileManager.default.fileExists(atPath: path),
                  !existingPaths.contains(path),
                  pendingPaths.insert(path).inserted else { return nil }

            return QuickActionItem(
                id: UUID(),
                title: url.deletingPathExtension().lastPathComponent,
                symbol: "app.fill",
                destination: .application(path: path),
                isBuiltIn: false,
                dateAdded: date
            )
        }

        guard !additions.isEmpty else { return 0 }
        items = Array((items + additions).prefix(Constants.maximumItemCount))
        persist()
        return additions.count
    }

    func remove(_ item: QuickActionItem) {
        guard !item.isBuiltIn else { return }
        items.removeAll { $0.id == item.id }
        persist()
        NotchHaptics.perform(.navigation)
    }

    func resetToDefaults() {
        items = Self.defaultItems()
        persist()
        NotchHaptics.perform(.navigation)
    }

    private func finishLaunch(succeeded: Bool) {
        launchingID = nil
        NotchHaptics.perform(succeeded ? .confirmation : .rejection)
    }

    private func restore() {
        if let data = defaults.data(forKey: Constants.storageKey),
           let decoded = try? JSONDecoder().decode([QuickActionItem].self, from: data),
           !decoded.isEmpty {
            items = Array(decoded.prefix(Constants.maximumItemCount))
        } else {
            items = Self.defaultItems()
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Constants.storageKey)
    }

    private static func defaultItems() -> [QuickActionItem] {
        let definitions: [(String, String, QuickActionDestination)] = [
            ("Finder", "face.smiling", .application(path: "/System/Library/CoreServices/Finder.app")),
            ("Downloads", "arrow.down.circle.fill", .folder(path: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "~/Downloads")),
            ("Screenshot", "camera.viewfinder", .application(path: "/System/Applications/Utilities/Screenshot.app")),
            ("Shortcuts", "square.2.layers.3d.fill", .application(path: "/System/Applications/Shortcuts.app")),
            ("Calculator", "plus.forwardslash.minus", .application(path: "/System/Applications/Calculator.app")),
            ("Settings", "gearshape.fill", .application(path: "/System/Applications/System Settings.app")),
        ]

        return definitions.enumerated().map { index, definition in
            QuickActionItem(
                id: UUID(),
                title: definition.0,
                symbol: definition.1,
                destination: definition.2,
                isBuiltIn: true,
                dateAdded: Date(timeIntervalSinceReferenceDate: Double(index))
            )
        }
    }
}

