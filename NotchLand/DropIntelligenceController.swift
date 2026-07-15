//
//  DropIntelligenceController.swift
//  NotchLand
//
//  Pure classification and recommendation layer. It works only with metadata
//  already prepared by FileShelfIO, so analysis never touches the filesystem.
//

import Combine
import Foundation
import UniformTypeIdentifiers

nonisolated enum DropContentKind: String, Equatable, Sendable {
    case folder
    case image
    case pdf
    case video
    case audio
    case archive
    case code
    case text
    case file
    case multiple

    var title: String {
        switch self {
        case .folder: "Folder detected"
        case .image: "Image detected"
        case .pdf: "PDF detected"
        case .video: "Video detected"
        case .audio: "Audio detected"
        case .archive: "Archive detected"
        case .code: "Code detected"
        case .text: "Text detected"
        case .file: "File ready"
        case .multiple: "Multiple items ready"
        }
    }

    var symbol: String {
        switch self {
        case .folder: "folder.fill"
        case .image: "photo.fill"
        case .pdf: "doc.richtext.fill"
        case .video: "film.fill"
        case .audio: "waveform"
        case .archive: "archivebox.fill"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .text: "doc.text.fill"
        case .file: "doc.fill"
        case .multiple: "square.stack.3d.up.fill"
        }
    }
}

nonisolated enum DropSuggestedAction: String, Equatable, Identifiable, Sendable {
    case quickLook
    case airDrop
    case reveal
    case copyPaths
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickLook: "Preview"
        case .airDrop: "AirDrop"
        case .reveal: "Reveal"
        case .copyPaths: "Copy Path"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .quickLook: "eye.fill"
        case .airDrop: "paperplane.fill"
        case .reveal: "folder.fill"
        case .copyPaths: "doc.on.doc.fill"
        case .shortcuts: "square.stack.3d.up.fill"
        }
    }
}

nonisolated struct DropAnalysis: Equatable, Sendable {
    let kind: DropContentKind
    let items: [FileShelfItem]
    let suggestions: [DropSuggestedAction]

    var urls: [URL] { items.map(\.url) }
    var detail: String {
        if items.count > 1 { return "\(items.count) items" }
        return items.first?.displayName ?? "Ready"
    }
}

nonisolated enum DropContentClassifier {
    private static let codeExtensions: Set<String> = [
        "c", "cc", "cpp", "css", "go", "h", "hpp", "html", "java", "js",
        "json", "kt", "m", "mm", "php", "py", "rb", "rs", "sh", "sql",
        "swift", "ts", "tsx", "vue", "xml", "yaml", "yml",
    ]

    static func classify(_ items: [FileShelfItem]) -> DropContentKind? {
        guard let item = items.first else { return nil }
        guard items.count == 1 else { return .multiple }
        if item.isDirectory { return .folder }

        let pathExtension = item.url.pathExtension.lowercased()
        if codeExtensions.contains(pathExtension) { return .code }
        guard let type = UTType(filenameExtension: pathExtension) else { return .file }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) || type.conforms(to: .zip) { return .archive }
        if type.conforms(to: .plainText) || type.conforms(to: .text) { return .text }
        return .file
    }
}

nonisolated enum DropSuggestionEngine {
    static func suggestions(for kind: DropContentKind) -> [DropSuggestedAction] {
        switch kind {
        case .folder:
            [.reveal, .copyPaths, .shortcuts]
        case .multiple:
            [.airDrop, .copyPaths, .shortcuts]
        case .image, .pdf, .video, .audio:
            [.quickLook, .airDrop, .shortcuts]
        case .archive:
            [.quickLook, .reveal, .shortcuts]
        case .code, .text:
            [.quickLook, .copyPaths, .shortcuts]
        case .file:
            [.quickLook, .reveal, .shortcuts]
        }
    }
}

@MainActor
final class DropIntelligenceController: ObservableObject {
    @Published private(set) var current: DropAnalysis?

    func analyze(_ items: [FileShelfItem]) {
        guard let kind = DropContentClassifier.classify(items) else {
            current = nil
            return
        }
        current = DropAnalysis(
            kind: kind,
            items: items,
            suggestions: DropSuggestionEngine.suggestions(for: kind)
        )
    }

    func dismiss() {
        current = nil
    }
}
