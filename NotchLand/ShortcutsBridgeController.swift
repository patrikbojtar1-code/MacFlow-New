//
//  ShortcutsBridgeController.swift
//  NotchLand
//
//  Async, protocol-driven bridge to the public macOS `shortcuts` command.
//  No shell is involved: shortcut names are passed as Process arguments, so
//  user-controlled text cannot be interpreted as executable shell syntax.
//

import Combine
import Foundation

struct NotchShortcut: Identifiable, Equatable, Sendable {
    let name: String
    var id: String { name }
}

enum ShortcutsBridgeError: LocalizedError, Equatable {
    case unavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Shortcuts is not available on this Mac."
        case .commandFailed(let message):
            message.isEmpty ? "The shortcut could not be completed." : message
        }
    }
}

@MainActor
protocol ShortcutsCommandRunning {
    func listShortcutNames() async throws -> [String]
    func runShortcut(named name: String, inputURLs: [URL]) async throws -> String
}

@MainActor
final class MacShortcutsCommandRunner: ShortcutsCommandRunning {
    private let executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")

    func listShortcutNames() async throws -> [String] {
        let output = try await execute(arguments: ["list"])
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func runShortcut(named name: String, inputURLs: [URL]) async throws -> String {
        let inputArguments = inputURLs.flatMap { ["--input-path", $0.standardizedFileURL.path] }
        return try await execute(arguments: ["run", name] + inputArguments)
    }

    private func execute(arguments: [String]) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ShortcutsBridgeError.unavailable
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { completedProcess in
                let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let outputText = String(decoding: output, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let errorText = String(decoding: error, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if completedProcess.terminationStatus == 0 {
                    continuation.resume(returning: outputText)
                } else {
                    continuation.resume(
                        throwing: ShortcutsBridgeError.commandFailed(errorText)
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

@MainActor
final class ShortcutsBridgeController: ObservableObject {
    @Published private(set) var shortcuts: [NotchShortcut] = []
    @Published private(set) var favoriteNames: Set<String>
    @Published private(set) var isLoading = false
    @Published private(set) var runningShortcutName: String?
    @Published private(set) var runningInputCount = 0
    @Published private(set) var preparedInputURLs: [URL] = []
    @Published private(set) var lastResult: String?
    @Published private(set) var errorMessage: String?

    private enum Keys {
        static let favorites = "shortcuts.favorites.v1"
    }

    private let runner: any ShortcutsCommandRunning
    private let events: NotchEventCenter
    private let defaults: UserDefaults
    private var eventResolutionTask: Task<Void, Never>?

    init(
        runner: (any ShortcutsCommandRunning)? = nil,
        events: NotchEventCenter,
        defaults: UserDefaults = .standard
    ) {
        self.runner = runner ?? MacShortcutsCommandRunner()
        self.events = events
        self.defaults = defaults
        favoriteNames = Set(defaults.stringArray(forKey: Keys.favorites) ?? [])
    }

    var orderedShortcuts: [NotchShortcut] {
        shortcuts.sorted {
            let lhsFavorite = favoriteNames.contains($0.name)
            let rhsFavorite = favoriteNames.contains($1.name)
            if lhsFavorite != rhsFavorite { return lhsFavorite }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let names = try await runner.listShortcutNames()
            let normalizedNames = names
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let uniqueNames = normalizedNames.reduce(into: [String]()) { result, name in
                guard !result.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
                result.append(name)
            }
            shortcuts = uniqueNames.map(NotchShortcut.init(name:))
            favoriteNames.formIntersection(Set(uniqueNames))
            persistFavorites()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func run(_ shortcut: NotchShortcut, inputURLs: [URL] = []) async {
        guard runningShortcutName == nil else {
            NotchHaptics.perform(.rejection)
            return
        }

        let correlationID = "shortcut:\(UUID().uuidString)"
        runningShortcutName = shortcut.name
        runningInputCount = inputURLs.count
        lastResult = nil
        errorMessage = nil
        eventResolutionTask?.cancel()

        events.submit(NotchEvent(
            correlationID: correlationID,
            source: .integration,
            title: "Running \(shortcut.name)",
            detail: inputURLs.isEmpty ? "Apple Shortcuts" : "\(inputURLs.count) Shelf item\(inputURLs.count == 1 ? "" : "s")",
            symbol: "play.circle.fill",
            priority: .normal
        ))

        do {
            let output = try await runner.runShortcut(named: shortcut.name, inputURLs: inputURLs)
            let detail = output.isEmpty ? "Completed successfully" : output
            lastResult = detail
            events.submit(NotchEvent(
                correlationID: correlationID,
                source: .integration,
                title: "\(shortcut.name) finished",
                detail: detail,
                symbol: "checkmark.circle.fill",
                priority: .normal
            ))
            NotchHaptics.perform(.confirmation)
            scheduleResolution(correlationID: correlationID, delay: .seconds(2))
        } catch {
            errorMessage = error.localizedDescription
            events.submit(NotchEvent(
                correlationID: correlationID,
                source: .integration,
                title: "\(shortcut.name) failed",
                detail: error.localizedDescription,
                symbol: "exclamationmark.triangle.fill",
                priority: .important
            ))
            NotchHaptics.perform(.rejection)
            scheduleResolution(correlationID: correlationID, delay: .seconds(4))
        }

        runningShortcutName = nil
        runningInputCount = 0
    }

    func toggleFavorite(_ shortcut: NotchShortcut) {
        if favoriteNames.contains(shortcut.name) {
            favoriteNames.remove(shortcut.name)
        } else {
            favoriteNames.insert(shortcut.name)
        }
        persistFavorites()
        NotchHaptics.perform(.navigation)
    }

    func prepareInput(_ urls: [URL]) {
        preparedInputURLs = urls.map { $0.standardizedFileURL }
        NotchHaptics.perform(.navigation)
    }

    func clearPreparedInput() {
        preparedInputURLs = []
    }

    private func scheduleResolution(correlationID: String, delay: Duration) {
        eventResolutionTask?.cancel()
        eventResolutionTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.events.resolve(correlationID: correlationID)
        }
    }

    private func persistFavorites() {
        defaults.set(favoriteNames.sorted(), forKey: Keys.favorites)
    }
}
