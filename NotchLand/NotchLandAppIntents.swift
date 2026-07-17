//
//  NotchLandAppIntents.swift
//  NotchLand
//
//  Public App Intents expose NotchLand actions to Siri, Spotlight and Apple
//  Shortcuts. Siri owns speech and system UI; results surface in the notch.
//

import AppIntents
import Foundation

@MainActor
final class NotchIntentRuntime {
    static let shared = NotchIntentRuntime()

    weak var appState: AppState?
    weak var timer: NotchTimerController?
    weak var notes: QuickNotesController?
    weak var biometrics: BiometricAuthenticationController?

    private init() {}

    func configure(
        appState: AppState,
        timer: NotchTimerController,
        notes: QuickNotesController,
        biometrics: BiometricAuthenticationController
    ) {
        self.appState = appState
        self.timer = timer
        self.notes = notes
        self.biometrics = biometrics
    }
}

nonisolated enum SiriNotchModule: String, AppEnum {
    case media
    case calendar
    case files
    case wallet
    case timeline
    case shortcuts
    case timer
    case notes
    case tasks
    case clipboard
    case actions
    case mirror

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Notch Module")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .media: "Media",
        .calendar: "Calendar",
        .files: "Files",
        .wallet: "Wallet",
        .timeline: "Timeline",
        .shortcuts: "Shortcuts",
        .timer: "Timer",
        .notes: "Notes",
        .tasks: "Tasks",
        .clipboard: "Clipboard",
        .actions: "Actions",
        .mirror: "Mirror",
    ]
}

struct OpenNotchModuleIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Notch Module"
    static let description = IntentDescription("Opens a selected module inside MacFlow.")
    static let openAppWhenRun = true

    @Parameter(title: "Module")
    var module: SiriNotchModule

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let appState = NotchIntentRuntime.shared.appState else {
            return .result(dialog: "MacFlow is still starting. Please try again.")
        }
        appState.requestOpenWidget(rawValue: module.rawValue)
        return .result(dialog: "Opening \(module.rawValue) in MacFlow.")
    }
}

struct StartNotchTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Notch Timer"
    static let description = IntentDescription("Starts a timer that remains visible in the notch.")
    static let openAppWhenRun = true

    @Parameter(title: "Minutes", default: 5, inclusiveRange: (1, 180))
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let timer = NotchIntentRuntime.shared.timer else {
            return .result(dialog: "MacFlow is still starting. Please try again.")
        }
        let safeMinutes = min(max(minutes, 1), 180)
        timer.start(minutes: safeMinutes)
        return .result(dialog: "Started a \(safeMinutes)-minute MacFlow timer.")
    }
}

struct CreateNotchNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Notch Note"
    static let description = IntentDescription("Creates a local note in MacFlow.")
    static let openAppWhenRun = true

    @Parameter(title: "Text")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let notes = NotchIntentRuntime.shared.notes else {
            return .result(dialog: "MacFlow is still starting. Please try again.")
        }
        let note = notes.createNote()
        notes.updateContent(id: note.id, content: text)
        NotchIntentRuntime.shared.appState?.requestOpenWidget(rawValue: NotchWidget.notes.rawValue)
        return .result(dialog: "Your note was saved locally in MacFlow.")
    }
}

struct LockNotchPrivacyIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Private Notch Widgets"
    static let description = IntentDescription("Immediately locks all private MacFlow modules.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotchIntentRuntime.shared.biometrics?.lock()
        return .result(dialog: "Private MacFlow widgets are locked.")
    }
}

struct NotchLandAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenNotchModuleIntent(),
            phrases: [
                "Open \(\.$module) in \(.applicationName)",
                "Show \(\.$module) in \(.applicationName)",
                "Otevři \(\.$module) v \(.applicationName)",
                "Ukaž \(\.$module) v \(.applicationName)",
            ],
            shortTitle: "Open Notch Module",
            systemImageName: "macbook.and.iphone"
        )
        AppShortcut(
            intent: StartNotchTimerIntent(),
            phrases: [
                "Start a timer in \(.applicationName)",
                "Spusť časovač v \(.applicationName)",
            ],
            shortTitle: "Start Notch Timer",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: CreateNotchNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "Vytvoř poznámku v \(.applicationName)",
            ],
            shortTitle: "Create Notch Note",
            systemImageName: "note.text"
        )
        AppShortcut(
            intent: LockNotchPrivacyIntent(),
            phrases: [
                "Lock \(.applicationName)",
                "Zamkni \(.applicationName)",
            ],
            shortTitle: "Lock Private Widgets",
            systemImageName: "lock.shield.fill"
        )
    }
}
