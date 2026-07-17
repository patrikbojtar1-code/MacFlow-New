//
//  FileShelfController.swift
//  NotchLand
//
//  Persistent, local-only file shelf. The controller stores bookmark data so
//  dropped files can be resolved again after NotchLand relaunches without
//  copying or uploading the user's content.
//

import AppKit
import Combine
import Foundation
import QuickLookUI

nonisolated struct FileShelfItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let dateAdded: Date
    let isDirectory: Bool
    let metadataDescription: String
    fileprivate let bookmarkData: Data?

    var displayName: String { url.lastPathComponent }

    init(
        id: UUID = UUID(),
        url: URL,
        dateAdded: Date = .now,
        isDirectory: Bool,
        metadataDescription: String,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.url = url
        self.dateAdded = dateAdded
        self.isDirectory = isDirectory
        self.metadataDescription = metadataDescription
        self.bookmarkData = bookmarkData
    }
}

nonisolated private struct StoredFileShelfItem: Codable, Sendable {
    let id: UUID
    let bookmarkData: Data?
    let fallbackPath: String
    let dateAdded: Date
    let isDirectory: Bool?
    let metadataDescription: String?
}

nonisolated private enum FileShelfIO {
    static func prepare(urls: [URL], maximumCount: Int) -> [FileShelfItem] {
        let unique = urls.reduce(into: [URL]()) { result, rawURL in
            let url = rawURL.standardizedFileURL
            guard !result.contains(where: { $0.path == url.path }) else { return }
            result.append(url)
        }

        return unique.prefix(maximumCount).compactMap {
            prepare(url: $0, id: UUID(), dateAdded: .now)
        }
    }

    static func restore(_ records: [StoredFileShelfItem]) -> [FileShelfItem] {
        records.compactMap { record in
            var isStale = false
            let resolved: URL?
            if let bookmarkData = record.bookmarkData {
                resolved = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withoutUI, .withoutMounting],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            } else {
                resolved = nil
            }
            let url = (resolved ?? URL(fileURLWithPath: record.fallbackPath)).standardizedFileURL
            return prepare(url: url, id: record.id, dateAdded: record.dateAdded)
        }
    }

    private static func prepare(url: URL, id: UUID, dateAdded: Date) -> FileShelfItem? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .contentTypeKey,
            .fileSizeKey,
        ])
        let isDirectory = values?.isDirectory ?? false
        let kind = values?.contentType?.localizedDescription ?? (isDirectory ? "Folder" : "File")
        let metadata: String
        if !isDirectory, let size = values?.fileSize {
            metadata = "\(kind) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
        } else {
            metadata = kind
        }
        let bookmark = try? url.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: [.isDirectoryKey, .contentTypeKey],
            relativeTo: nil
        )
        return FileShelfItem(
            id: id,
            url: url,
            dateAdded: dateAdded,
            isDirectory: isDirectory,
            metadataDescription: metadata,
            bookmarkData: bookmark
        )
    }
}

@MainActor
private final class FileShelfQuickLookController: NSObject, QLPreviewPanelDataSource {
    private var previewURLs: [NSURL] = []

    func present(items: [FileShelfItem], selectedID: UUID) {
        previewURLs = items.map { $0.url as NSURL }
        guard !previewURLs.isEmpty else { return }

        let selectedIndex = items.firstIndex { $0.id == selectedID } ?? 0
        let panel = QLPreviewPanel.shared()
        panel?.dataSource = self
        panel?.reloadData()
        panel?.currentPreviewItemIndex = selectedIndex
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index]
    }
}

@MainActor
final class FileShelfController: ObservableObject {
    @Published private(set) var items: [FileShelfItem] = []
    @Published private(set) var latestAddedItems: [FileShelfItem] = []
    @Published private(set) var isDropTargetVisible = false
    @Published private(set) var isHoveringDropZone = false
    @Published var isPresented = false

    private enum Constants {
        static let storageKey = "fileShelf.items.v1"
        static let maximumItemCount = 50
    }

    private let settings: NotchSettings
    private let defaults: UserDefaults
    private let quickLookController = FileShelfQuickLookController()
    private var restorationTask: Task<Void, Never>?

    init(settings: NotchSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        restoreCachedItems()
    }

    func dragApproached() {
        guard settings.fileShelfEnabled else { return }
        isDropTargetVisible = true
    }

    func dragEnded() {
        isDropTargetVisible = false
        isHoveringDropZone = false
    }

    func setHoveringDropZone(_ isHovering: Bool) {
        guard isDropTargetVisible else { return }
        isHoveringDropZone = isHovering
    }

    @discardableResult
    func add(_ urls: [URL]) async -> Int {
        await waitForRestoration()
        let existingPaths = Set(items.map { $0.url.standardizedFileURL.path })
        let candidates = urls
            .map { $0.standardizedFileURL }
            .filter { !existingPaths.contains($0.path) }
        let maximumItemCount = Constants.maximumItemCount
        let incoming = await Task.detached(priority: .userInitiated) {
            FileShelfIO.prepare(urls: candidates, maximumCount: maximumItemCount)
        }.value

        guard !incoming.isEmpty else {
            latestAddedItems = []
            NotchHaptics.perform(.rejection)
            dragEnded()
            return 0
        }

        // `add` is actor-reentrant while metadata is prepared. Re-read the
        // current shelf after the await so two rapid drops cannot insert the
        // same item or overwrite one another's result.
        let currentPaths = Set(items.map { $0.url.standardizedFileURL.path })
        let additions = incoming.reduce(into: [FileShelfItem]()) { result, item in
            let path = item.url.standardizedFileURL.path
            guard !currentPaths.contains(path),
                  !result.contains(where: { $0.url.standardizedFileURL.path == path }) else { return }
            result.append(item)
        }

        guard !additions.isEmpty else {
            NotchHaptics.perform(.navigation)
            isPresented = true
            dragEnded()
            return 0
        }

        items = Array((additions + items).prefix(Constants.maximumItemCount))
        latestAddedItems = additions
        persist()
        isPresented = true
        dragEnded()
        NotchHaptics.perform(.confirmation)
        return additions.count
    }

    func remove(_ item: FileShelfItem) {
        items.removeAll { $0.id == item.id }
        persist()
        NotchHaptics.perform(.navigation)
    }

    func removeAll() {
        restorationTask?.cancel()
        restorationTask = nil
        items.removeAll()
        latestAddedItems = []
        persist()
        isPresented = false
    }

    func revealInFinder(_ item: FileShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func quickLook(_ item: FileShelfItem) {
        guard items.contains(where: { $0.id == item.id }) else { return }
        quickLookController.present(items: items, selectedID: item.id)
    }

    func dismiss() {
        isPresented = false
    }

    func waitForRestoration() async {
        await restorationTask?.value
    }

    private func restoreCachedItems() {
        guard let data = defaults.data(forKey: Constants.storageKey),
              let stored = try? JSONDecoder().decode([StoredFileShelfItem].self, from: data) else {
            return
        }

        // Render cached, I/O-free descriptors immediately. Bookmark resolution,
        // existence checks and metadata refresh happen away from the UI actor.
        items = stored.map { record in
            FileShelfItem(
                id: record.id,
                url: URL(fileURLWithPath: record.fallbackPath),
                dateAdded: record.dateAdded,
                isDirectory: record.isDirectory ?? false,
                metadataDescription: record.metadataDescription ?? "File",
                bookmarkData: record.bookmarkData
            )
        }
        restorationTask = Task { [weak self] in
            let restored = await Task.detached(priority: .utility) {
                FileShelfIO.restore(stored)
            }.value
            guard !Task.isCancelled, let self else { return }
            items = restored
            persist()
        }
    }

    private func persist() {
        let stored = items.map { item in
            StoredFileShelfItem(
                id: item.id,
                bookmarkData: item.bookmarkData,
                fallbackPath: item.url.path,
                dateAdded: item.dateAdded,
                isDirectory: item.isDirectory,
                metadataDescription: item.metadataDescription
            )
        }

        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Constants.storageKey)
    }
}
