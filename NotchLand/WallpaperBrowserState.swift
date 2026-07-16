//
//  WallpaperBrowserState.swift
//  MacFlow
//
//  Presentation-only search, filtering, sorting, layout, and selection state.
//

import Combine
import Foundation

nonisolated enum WallpaperBrowserScope: Hashable, Sendable {
    case all
    case video
    case still
    case favorites
    case collection(UUID)

    var title: String {
        switch self {
        case .all: "All"
        case .video: "Live"
        case .still: "Still"
        case .favorites: "Favorites"
        case .collection: "Collection"
        }
    }
}

nonisolated enum WallpaperBrowserSort: String, CaseIterable, Identifiable, Sendable {
    case recent
    case title
    case kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .title: "Name"
        case .kind: "Type"
        }
    }
}

nonisolated enum WallpaperBrowserLayout: String, CaseIterable, Identifiable, Sendable {
    case grid
    case list

    var id: String { rawValue }
}

@MainActor
final class WallpaperBrowserState: ObservableObject {
    @Published var query = ""
    @Published var scope: WallpaperBrowserScope = .all
    @Published var sort: WallpaperBrowserSort = .recent
    @Published var layout: WallpaperBrowserLayout = .grid
    @Published var selectedSceneID: UUID?

    func visibleScenes(in library: WallpaperSceneLibrary) -> [WallpaperScene] {
        let favoriteIDs = Set(library.favorites.sceneIDs)
        let collectionIDs: Set<UUID>
        if case .collection(let collectionID) = scope,
           let collection = library.collections.first(where: { $0.id == collectionID }) {
            collectionIDs = Set(collection.sceneIDs)
        } else {
            collectionIDs = []
        }
        return Self.filteredScenes(
            library.scenes,
            query: query,
            scope: scope,
            sort: sort,
            favoriteIDs: favoriteIDs,
            collectionIDs: collectionIDs
        )
    }

    func ensureSelection(in scenes: [WallpaperScene], preferredID: UUID?) {
        if let selectedSceneID, scenes.contains(where: { $0.id == selectedSceneID }) {
            return
        }
        if let preferredID, scenes.contains(where: { $0.id == preferredID }) {
            selectedSceneID = preferredID
        } else {
            selectedSceneID = scenes.first?.id
        }
    }

    nonisolated static func filteredScenes(
        _ scenes: [WallpaperScene],
        query: String,
        scope: WallpaperBrowserScope,
        sort: WallpaperBrowserSort,
        favoriteIDs: Set<UUID> = [],
        collectionIDs: Set<UUID> = []
    ) -> [WallpaperScene] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered = scenes.filter { scene in
            let matchesQuery = normalizedQuery.isEmpty
                || scene.title.localizedCaseInsensitiveContains(normalizedQuery)
                || scene.author.localizedCaseInsensitiveContains(normalizedQuery)

            let matchesScope: Bool
            switch scope {
            case .all:
                matchesScope = true
            case .video:
                matchesScope = scene.kind == .video
            case .still:
                matchesScope = scene.kind == .image
            case .favorites:
                matchesScope = favoriteIDs.contains(scene.id)
            case .collection:
                matchesScope = collectionIDs.contains(scene.id)
            }
            return matchesQuery && matchesScope
        }

        return filtered.sorted { lhs, rhs in
            switch sort {
            case .recent:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .kind:
                if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }
}
