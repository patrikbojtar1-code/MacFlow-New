//
//  ScenesSettingsView.swift
//  MacFlow
//
//  Wallpaper browser, active preview, library, and selected-scene inspector.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScenesSettingsView: View {
    @EnvironmentObject private var controller: WallpaperSceneController
    @StateObject private var browser = WallpaperBrowserState()
    @State private var presentsImporter = false
    @State private var presentsAutomation = false
    @State private var presentsNewCollection = false
    @State private var newCollectionName = ""
    @State private var isImporting = false
    @State private var inspectorTab: InspectorTab = .details

    private enum InspectorTab: String, CaseIterable, Identifiable {
        case details
        case settings
        case displays

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            browserToolbar
            Divider().overlay(MacFlowColor.borderSubtle)

            if controller.library.scenes.isEmpty, !isImporting {
                MacFlowEmptyState(
                    systemImage: "photo.on.rectangle.angled",
                    title: "Build your wallpaper library",
                    detail: "Import a still image, looping video, or a safe .notchscene package.",
                    actionTitle: "Import Scene",
                    action: { presentsImporter = true }
                )
            } else {
                browserContent
            }
        }
        .fileImporter(
            isPresented: $presentsImporter,
            allowedContentTypes: [.image, .movie, .notchLandScene],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .alert(
            "Wallpapers",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { controller.errorMessage = nil }
        } message: {
            Text(controller.errorMessage ?? "Unknown error")
        }
        .alert("New Collection", isPresented: $presentsNewCollection) {
            TextField("Collection name", text: $newCollectionName)
            Button("Cancel", role: .cancel) { newCollectionName = "" }
            Button("Create") {
                if let collection = controller.library.createCollection(named: newCollectionName) {
                    browser.scope = .collection(collection.id)
                }
                newCollectionName = ""
            }
            .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Collections organize scenes without copying their files.")
        }
        .sheet(isPresented: $presentsAutomation) {
            WallpaperAutomationEditor()
                .environmentObject(controller)
        }
        .onAppear { synchronizeSelection() }
        .onChange(of: sceneIDs) { _, _ in synchronizeSelection() }
        .onChange(of: controller.activeSceneID) { _, _ in synchronizeSelection() }
        .onChange(of: browser.scope) { _, _ in synchronizeSelectionToVisibleScenes() }
        .onChange(of: browser.query) { _, _ in synchronizeSelectionToVisibleScenes() }
    }

    private var browserToolbar: some View {
        HStack(spacing: MacFlowSpacing.space12) {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                Text("Wallpaper Scenes")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.35)
                Text("Browse, apply, and tune your local collection.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(MacFlowColor.textSecondary)
            }

            Spacer(minLength: MacFlowSpacing.space16)

            HStack(spacing: MacFlowSpacing.space8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MacFlowColor.textTertiary)
                TextField("Search scenes", text: $browser.query)
                    .textFieldStyle(.plain)
                if !browser.query.isEmpty {
                    Button {
                        browser.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacFlowColor.textTertiary)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, MacFlowSpacing.space10)
            .frame(width: 210, height: 32)
            .background(MacFlowColor.surface2, in: RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
                    .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
            }

            Menu {
                Picker("Sort", selection: $browser.sort) {
                    ForEach(WallpaperBrowserSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
            } label: {
                Label(browser.sort.title, systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Button {
                    presentsAutomation = true
                } label: {
                    Label("Automation…", systemImage: "clock.arrow.2.circlepath")
                }
                Divider()
                Button {
                    presentsNewCollection = true
                } label: {
                    Label("New Collection…", systemImage: "folder.badge.plus")
                }
                ForEach(controller.library.collections.filter { $0.kind == .custom }) { collection in
                    Button {
                        browser.scope = .collection(collection.id)
                    } label: {
                        Label(collection.title, systemImage: "folder")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .help("Wallpaper options")

            Picker("Layout", selection: $browser.layout) {
                Image(systemName: "square.grid.2x2").tag(WallpaperBrowserLayout.grid)
                Image(systemName: "list.bullet").tag(WallpaperBrowserLayout.list)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 68)

            Button {
                presentsImporter = true
            } label: {
                Label("Import", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(MacFlowColor.accent)
            .disabled(isImporting)
        }
        .padding(.horizontal, MacFlowSpacing.space24)
        .frame(minHeight: 78)
    }

    private var browserContent: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                selectedPreview
                    .padding(.horizontal, MacFlowSpacing.space16)
                    .padding(.top, MacFlowSpacing.space16)

                libraryHeader
                    .padding(.horizontal, MacFlowSpacing.space16)
                    .padding(.top, MacFlowSpacing.space16)
                    .padding(.bottom, MacFlowSpacing.space10)

                if isImporting {
                    WallpaperImportSkeleton()
                        .padding(.horizontal, MacFlowSpacing.space16)
                        .padding(.bottom, MacFlowSpacing.space10)
                }

                sceneLibrary
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(MacFlowColor.borderSubtle)
                .frame(width: 1)

            sceneInspector
                .frame(width: MacFlowMetrics.inspectorWidth)
        }
    }

    private var selectedPreview: some View {
        Group {
            if let scene = selectedScene {
                MacFlowPanel(.elevated) {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
                            HStack(spacing: MacFlowSpacing.space8) {
                                Circle()
                                    .fill(scene.id == controller.activeSceneID ? Color.green : MacFlowColor.textTertiary)
                                    .frame(width: 7, height: 7)
                                Text(scene.id == controller.activeSceneID ? "ACTIVE SCENE" : "SELECTED SCENE")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(MacFlowColor.textSecondary)
                                    .tracking(0.85)
                            }

                            VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                                Text(scene.title)
                                    .font(.system(size: 20, weight: .semibold))
                                    .lineLimit(2)
                                Text("by \(scene.author)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MacFlowColor.textSecondary)
                            }

                            HStack(spacing: MacFlowSpacing.space12) {
                                Label(scene.kind.displayName, systemImage: scene.kind.systemImage)
                                Label(scene.rendering.scalingMode.title, systemImage: scene.rendering.scalingMode.systemImage)
                            }
                            .font(.system(size: 10.5))
                            .foregroundStyle(MacFlowColor.textSecondary)

                            Spacer(minLength: 0)

                            previewActions(for: scene)
                        }
                        .padding(MacFlowSpacing.space16)
                        .frame(width: 222, alignment: .leading)

                        WallpaperThumbnailView(
                            scene: scene,
                            url: controller.library.previewURL(for: scene),
                            scalingMode: .fill,
                            dimming: scene.rendering.dimming
                        )
                        .overlay(alignment: .bottomTrailing) {
                            if scene.kind == .video {
                                Label("Looping video", systemImage: "play.fill")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, MacFlowSpacing.space8)
                                    .padding(.vertical, MacFlowSpacing.space6)
                                    .background(.black.opacity(0.60), in: Capsule())
                                    .padding(MacFlowSpacing.space12)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                    .frame(height: 206)
                }
            } else {
                MacFlowPanel(.grouped) {
                    MacFlowEmptyState(
                        systemImage: "photo",
                        title: "No scene matches",
                        detail: "Clear the search or choose another filter."
                    )
                    .frame(height: 206)
                }
            }
        }
    }

    private func previewActions(for scene: WallpaperScene) -> some View {
        HStack(spacing: MacFlowSpacing.space8) {
            if scene.id == controller.activeSceneID {
                Button {
                    controller.togglePaused()
                } label: {
                    Label(controller.isPaused ? "Resume" : "Pause", systemImage: controller.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(MacFlowColor.accent)

                Button {
                    controller.deactivate()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .help("Stop wallpaper")
                .accessibilityLabel("Stop wallpaper")
            } else {
                Button {
                    NotchHaptics.perform(.confirmation)
                    controller.apply(scene)
                } label: {
                    Label("Apply", systemImage: "display")
                }
                .buttonStyle(.borderedProminent)
                .tint(MacFlowColor.accent)
            }
        }
    }

    private var libraryHeader: some View {
        HStack(spacing: MacFlowSpacing.space8) {
            Text("LIBRARY")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(MacFlowColor.textSecondary)
                .tracking(0.85)

            filterButton(.all)
            filterButton(.video)
            filterButton(.still)
            filterButton(.favorites)

            Menu {
                ForEach(controller.library.collections.filter { $0.kind == .custom }) { collection in
                    Button(collection.title) {
                        browser.scope = .collection(collection.id)
                    }
                }
                if controller.library.collections.allSatisfy({ $0.kind != .custom }) {
                    Text("No custom collections")
                }
            } label: {
                Label(collectionFilterTitle, systemImage: "folder")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Text("\(visibleScenes.count) of \(controller.library.scenes.count)")
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(MacFlowColor.textTertiary)
        }
    }

    private func filterButton(_ scope: WallpaperBrowserScope) -> some View {
        let isSelected = browser.scope == scope
        return Button(scope.title) {
            browser.scope = scope
        }
        .buttonStyle(.plain)
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(isSelected ? .primary : MacFlowColor.textSecondary)
        .padding(.horizontal, MacFlowSpacing.space10)
        .padding(.vertical, MacFlowSpacing.space6)
        .background(
            isSelected ? MacFlowColor.surface3 : MacFlowColor.surface1,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? MacFlowColor.wallpaper.opacity(0.38) : MacFlowColor.borderSubtle, lineWidth: 1)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var sceneLibrary: some View {
        if visibleScenes.isEmpty {
            MacFlowEmptyState(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "No matching scenes",
                detail: "Try a different search, filter, or collection.",
                actionTitle: "Show All",
                action: {
                    browser.query = ""
                    browser.scope = .all
                }
            )
        } else {
            ScrollView {
                if browser.layout == .grid {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: MacFlowSpacing.space10)],
                        spacing: MacFlowSpacing.space10
                    ) {
                        ForEach(visibleScenes) { scene in
                            WallpaperSceneTile(
                                scene: scene,
                                previewURL: controller.library.previewURL(for: scene),
                                isSelected: scene.id == browser.selectedSceneID,
                                isActive: scene.id == controller.activeSceneID,
                                isFavorite: controller.library.isFavorite(scene),
                                select: { browser.selectedSceneID = scene.id },
                                toggleFavorite: { controller.library.toggleFavorite(scene) }
                            )
                        }
                    }
                } else {
                    LazyVStack(spacing: MacFlowSpacing.space6) {
                        ForEach(visibleScenes) { scene in
                            WallpaperSceneListRow(
                                scene: scene,
                                previewURL: controller.library.previewURL(for: scene),
                                isSelected: scene.id == browser.selectedSceneID,
                                isActive: scene.id == controller.activeSceneID,
                                select: { browser.selectedSceneID = scene.id }
                            )
                        }
                    }
                }
            }
            .contentMargins(.horizontal, MacFlowSpacing.space16, for: .scrollContent)
            .contentMargins(.bottom, MacFlowSpacing.space16, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }

    private var sceneInspector: some View {
        VStack(spacing: 0) {
            if let scene = selectedScene {
                inspectorHeader(scene)
                inspectorTabs
                Divider().overlay(MacFlowColor.borderSubtle)
                ScrollView {
                    switch inspectorTab {
                    case .details: inspectorDetails(scene)
                    case .settings: inspectorSettings(scene)
                    case .displays: inspectorDisplays(scene)
                    }
                }
                .scrollIndicators(.hidden)
            } else {
                MacFlowEmptyState(
                    systemImage: "sidebar.right",
                    title: "Select a scene",
                    detail: "Scene details and controls appear here."
                )
            }
        }
        .background(MacFlowColor.sidebar.opacity(0.62))
    }

    private func inspectorHeader(_ scene: WallpaperScene) -> some View {
        HStack(spacing: MacFlowSpacing.space10) {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space2) {
                HStack(spacing: MacFlowSpacing.space6) {
                    Text(scene.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if scene.id == controller.activeSceneID {
                        Text("LIVE")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.green)
                    }
                }
                Text(scene.author)
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacFlowColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                controller.library.toggleFavorite(scene)
            } label: {
                Image(systemName: controller.library.isFavorite(scene) ? "star.fill" : "star")
                    .foregroundStyle(controller.library.isFavorite(scene) ? .yellow : MacFlowColor.textSecondary)
            }
            .buttonStyle(.plain)
            .help(controller.library.isFavorite(scene) ? "Remove from Favorites" : "Add to Favorites")

            Menu {
                Button {
                    exportScene(scene)
                } label: {
                    Label("Export Scene…", systemImage: "square.and.arrow.up")
                }
                Menu("Add to Collection") {
                    ForEach(controller.library.collections.filter { $0.kind == .custom }) { collection in
                        Button {
                            controller.library.toggle(scene, in: collection)
                        } label: {
                            Label(
                                collection.title,
                                systemImage: controller.library.contains(scene, in: collection) ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                }
                Divider()
                Button("Remove Scene", role: .destructive) {
                    controller.remove(scene)
                    synchronizeSelection()
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, MacFlowSpacing.space16)
        .frame(height: 60)
    }

    private var inspectorTabs: some View {
        Picker("Inspector", selection: $inspectorTab) {
            ForEach(InspectorTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.horizontal, MacFlowSpacing.space12)
        .padding(.bottom, MacFlowSpacing.space12)
    }

    private func inspectorDetails(_ scene: WallpaperScene) -> some View {
        VStack(spacing: 0) {
            MacFlowInspectorSection("Scene") {
                inspectorValue("Type", scene.kind.displayName)
                inspectorValue("Scaling", scene.rendering.scalingMode.title)
                inspectorValue("Added", scene.createdAt.formatted(date: .abbreviated, time: .omitted))
                inspectorValue("Package", "Manifest v\(scene.manifestVersion)")
            }
            Divider().overlay(MacFlowColor.borderSubtle)
            MacFlowInspectorSection("Runtime") {
                inspectorValue("State", scene.id == controller.activeSceneID ? runtimeState : "Not applied")
                inspectorValue("Performance", controller.performance.effectiveProfile.title)
                inspectorValue("Displays", "\(NSScreen.screens.count)")
            }
            Divider().overlay(MacFlowColor.borderSubtle)
            MacFlowInspectorSection("Collections") {
                let memberships = controller.library.collections.filter { controller.library.contains(scene, in: $0) }
                if memberships.isEmpty {
                    Text("Not in a collection")
                        .font(.system(size: 11))
                        .foregroundStyle(MacFlowColor.textSecondary)
                } else {
                    MacFlowWrapLayout(spacing: MacFlowSpacing.space6) {
                        ForEach(memberships) { collection in
                            Text(collection.title)
                                .font(.system(size: 9.5, weight: .medium))
                                .padding(.horizontal, MacFlowSpacing.space8)
                                .padding(.vertical, MacFlowSpacing.space4)
                                .background(MacFlowColor.surface2, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func inspectorSettings(_ scene: WallpaperScene) -> some View {
        VStack(spacing: 0) {
            MacFlowInspectorSection("Performance") {
                Picker(
                    "Profile",
                    selection: Binding(
                        get: { controller.performance.selectedProfile },
                        set: { controller.performance.selectedProfile = $0 }
                    )
                ) {
                    ForEach(WallpaperPerformanceProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .labelsHidden()
                Text(controller.performance.effectiveProfile.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(MacFlowColor.textSecondary)
            }
            Divider().overlay(MacFlowColor.borderSubtle)
            MacFlowInspectorSection("Scene rendering") {
                Picker("Scaling", selection: renderingBinding(for: scene, keyPath: \.scalingMode)) {
                    ForEach(WallpaperSceneRenderingConfiguration.ScalingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if scene.kind == .video {
                    HStack {
                        Text("Playback")
                            .font(.system(size: 11.5))
                        Spacer()
                        Picker("Playback", selection: renderingBinding(for: scene, keyPath: \.playbackRate)) {
                            ForEach(WallpaperSceneRenderingConfiguration.playbackRateOptions, id: \.self) { rate in
                                Text("\(rate.formatted(.number.precision(.fractionLength(0...2))))×").tag(rate)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 92)
                    }
                }

                VStack(alignment: .leading, spacing: MacFlowSpacing.space6) {
                    HStack {
                        Text("Dimming").font(.system(size: 11.5))
                        Spacer()
                        Text(scene.rendering.dimming, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(MacFlowColor.textSecondary)
                    }
                    Slider(
                        value: renderingBinding(for: scene, keyPath: \.dimming),
                        in: WallpaperSceneRenderingConfiguration.dimmingRange
                    )
                    .tint(MacFlowColor.wallpaper)
                }

                Button("Reset Scene Settings") {
                    controller.updateRendering(for: scene.id, configuration: .default)
                }
                .buttonStyle(.bordered)
                .disabled(scene.rendering == .default)
            }
            Divider().overlay(MacFlowColor.borderSubtle)
            MacFlowInspectorSection("Automation") {
                Text(controller.automationStatusDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacFlowColor.textSecondary)
                Button("Edit Automation…") { presentsAutomation = true }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func inspectorDisplays(_ scene: WallpaperScene) -> some View {
        VStack(spacing: 0) {
            MacFlowInspectorSection("Connected displays") {
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                    HStack(spacing: MacFlowSpacing.space10) {
                        Image(systemName: "display")
                            .foregroundStyle(scene.id == controller.activeSceneID ? MacFlowColor.wallpaper : MacFlowColor.textSecondary)
                        VStack(alignment: .leading, spacing: MacFlowSpacing.space2) {
                            Text(screen.localizedName)
                                .font(.system(size: 11.5, weight: .medium))
                            Text(index == 0 ? "Primary display" : "Secondary display")
                                .font(.system(size: 9.5))
                                .foregroundStyle(MacFlowColor.textSecondary)
                        }
                        Spacer()
                        if scene.id == controller.activeSceneID {
                            Circle().fill(.green).frame(width: 6, height: 6)
                        }
                    }
                    .padding(.vertical, MacFlowSpacing.space6)
                }
            }
            Divider().overlay(MacFlowColor.borderSubtle)
            MacFlowInspectorSection("Apply") {
                Text("MacFlow currently keeps one coordinated scene across every connected display.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(MacFlowColor.textSecondary)
                Button {
                    controller.apply(scene)
                } label: {
                    Label("Apply to All Displays", systemImage: "display.2")
                }
                .buttonStyle(.borderedProminent)
                .tint(MacFlowColor.accent)
                .disabled(scene.id == controller.activeSceneID)
            }
        }
    }

    private func inspectorValue(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(MacFlowColor.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .multilineTextAlignment(.trailing)
        }
    }

    private func renderingBinding<Value>(
        for scene: WallpaperScene,
        keyPath: WritableKeyPath<WallpaperSceneRenderingConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                controller.library.scene(withID: scene.id)?.rendering[keyPath: keyPath]
                    ?? scene.rendering[keyPath: keyPath]
            },
            set: { newValue in
                guard let latestScene = controller.library.scene(withID: scene.id) else { return }
                var configuration = latestScene.rendering
                configuration[keyPath: keyPath] = newValue
                controller.updateRendering(for: scene.id, configuration: configuration)
            }
        )
    }

    private var selectedScene: WallpaperScene? {
        controller.library.scene(withID: browser.selectedSceneID)
    }

    private var visibleScenes: [WallpaperScene] {
        browser.visibleScenes(in: controller.library)
    }

    private var sceneIDs: [UUID] {
        controller.library.scenes.map(\.id)
    }

    private var runtimeState: String {
        if controller.isPaused { return "Paused" }
        if let detail = controller.suspensionDetail { return detail }
        return controller.isRunning ? "Live" : "Ready"
    }

    private var collectionFilterTitle: String {
        guard case .collection(let collectionID) = browser.scope,
              let collection = controller.library.collections.first(where: { $0.id == collectionID }) else {
            return "Collections"
        }
        return collection.title
    }

    private func synchronizeSelection() {
        browser.ensureSelection(in: controller.library.scenes, preferredID: controller.activeSceneID)
    }

    private func synchronizeSelectionToVisibleScenes() {
        browser.ensureSelection(in: visibleScenes, preferredID: controller.activeSceneID)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true
            Task {
                let imported = await controller.importAndApply(from: url)
                isImporting = false
                if imported {
                    browser.query = ""
                    browser.scope = .all
                    browser.selectedSceneID = controller.activeSceneID
                }
            }
        case .failure(let error):
            controller.errorMessage = error.localizedDescription
        }
    }

    private func exportScene(_ scene: WallpaperScene) {
        let panel = NSSavePanel()
        panel.title = "Export MacFlow Scene"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.notchLandScene]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(sanitizedPackageName(scene.title)).notchscene"
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        Task { await controller.export(scene, to: destinationURL) }
    }

    private func sanitizedPackageName(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        let sanitized = title.components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "MacFlow Scene" : sanitized
    }
}

private struct WallpaperSceneTile: View {
    let scene: WallpaperScene
    let previewURL: URL
    let isSelected: Bool
    let isActive: Bool
    let isFavorite: Bool
    let select: () -> Void
    let toggleFavorite: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 0) {
                WallpaperThumbnailView(scene: scene, url: previewURL, scalingMode: .fill, dimming: 0)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        Button(action: toggleFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isFavorite ? .yellow : .white.opacity(0.82))
                                .frame(width: 26, height: 26)
                                .background(.black.opacity(0.46), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(MacFlowSpacing.space8)
                        .opacity(isHovered || isFavorite ? 1 : 0)
                        .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    }

                HStack(spacing: MacFlowSpacing.space8) {
                    VStack(alignment: .leading, spacing: MacFlowSpacing.space2) {
                        Text(scene.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                        HStack(spacing: MacFlowSpacing.space5) {
                            Circle()
                                .fill(isActive ? Color.green : MacFlowColor.textTertiary)
                                .frame(width: 5, height: 5)
                            Text(isActive ? "Live" : scene.kind.displayName)
                                .font(.system(size: 9.5))
                                .foregroundStyle(MacFlowColor.textSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? MacFlowColor.wallpaper : MacFlowColor.textTertiary)
                }
                .padding(MacFlowSpacing.space10)
            }
            .background(MacFlowColor.surface1)
            .clipShape(RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                    .stroke(isSelected ? MacFlowColor.wallpaper : MacFlowColor.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WallpaperSceneListRow: View {
    let scene: WallpaperScene
    let previewURL: URL
    let isSelected: Bool
    let isActive: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: MacFlowSpacing.space12) {
                WallpaperThumbnailView(scene: scene, url: previewURL, scalingMode: .fill, dimming: 0)
                    .frame(width: 92, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                    Text(scene.title).font(.system(size: 12.5, weight: .medium))
                    Label(scene.kind.displayName, systemImage: scene.kind.systemImage)
                        .font(.system(size: 9.5))
                        .foregroundStyle(MacFlowColor.textSecondary)
                }
                Spacer()
                if isActive {
                    Text("LIVE")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.green)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(isSelected ? MacFlowColor.wallpaper : MacFlowColor.textTertiary)
            }
            .padding(MacFlowSpacing.space8)
            .background(
                isSelected ? MacFlowColor.surface2 : MacFlowColor.surface1,
                in: RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                    .stroke(isSelected ? MacFlowColor.wallpaper.opacity(0.55) : MacFlowColor.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct WallpaperThumbnailView: View {
    let scene: WallpaperScene
    let url: URL
    let scalingMode: WallpaperSceneRenderingConfiguration.ScalingMode
    let dimming: Double

    @State private var image: NSImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let image {
                    imageView(image, size: proxy.size)
                } else {
                    Image(systemName: scene.kind.systemImage)
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.42))
                }
                Color.black.opacity(dimming)
            }
        }
        .clipped()
        .task(id: url) {
            image = NSImage(contentsOf: url)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(scene.title), \(scene.kind.displayName) wallpaper")
    }

    @ViewBuilder
    private func imageView(_ image: NSImage, size: CGSize) -> some View {
        switch scalingMode {
        case .fill:
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        case .fit:
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
        case .stretch:
            Image(nsImage: image)
                .resizable()
                .frame(width: size.width, height: size.height)
        }
    }
}

private struct WallpaperImportSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        HStack(spacing: MacFlowSpacing.space12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(MacFlowColor.surface2)
                .frame(width: 96, height: 54)
            VStack(alignment: .leading, spacing: MacFlowSpacing.space8) {
                RoundedRectangle(cornerRadius: 3).fill(MacFlowColor.surface2).frame(width: 138, height: 10)
                RoundedRectangle(cornerRadius: 3).fill(MacFlowColor.surface1).frame(width: 90, height: 8)
            }
            Spacer()
            Text("Importing…")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(MacFlowColor.textSecondary)
        }
        .padding(MacFlowSpacing.space10)
        .background(MacFlowColor.surface1, in: RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous))
        .overlay {
            if !reduceMotion {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 260)
                .mask(RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

private struct WallpaperAutomationEditor: View {
    @EnvironmentObject private var controller: WallpaperSceneController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space20) {
            HStack {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                    Text("Wallpaper Automation")
                        .font(.title2.weight(.semibold))
                    Text("Choose scenes for time of day, Focus, and favorite rotation.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(MacFlowColor.textSecondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            MacFlowSettingsGroup {
                MacFlowSettingsRow(
                    icon: "clock.arrow.2.circlepath",
                    tint: MacFlowColor.wallpaper,
                    title: "Enable automation",
                    subtitle: controller.automationStatusDetail
                ) {
                    Toggle("Enable automation", isOn: automationBinding(\.isEnabled))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "star.fill",
                    tint: .yellow,
                    title: "Rotate favorites",
                    subtitle: "Cycle through favorite scenes when no specific rule applies."
                ) {
                    Toggle("Rotate favorites", isOn: automationBinding(\.rotatesFavorites))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "timer",
                    tint: MacFlowColor.wallpaper,
                    title: "Rotation interval"
                ) {
                    Picker("Rotation interval", selection: automationBinding(\.rotationIntervalMinutes)) {
                        ForEach(WallpaperAutomationConfiguration.supportedRotationIntervals, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            HStack(alignment: .top, spacing: MacFlowSpacing.space12) {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
                    MacFlowSectionHeader("Focus")
                    rulePicker(
                        title: "Focus scene",
                        icon: "moon.fill",
                        selection: automationBinding(\.focusSceneID)
                    )
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
                    MacFlowSectionHeader("Time of day")
                    ForEach(WallpaperDayPeriod.allCases) { period in
                        rulePicker(
                            title: period.title,
                            icon: period.systemImage,
                            selection: dayPeriodBinding(period)
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if controller.isManualOverrideActive {
                HStack {
                    Label(controller.automationStatusDetail, systemImage: "hand.raised.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(MacFlowColor.textSecondary)
                    Spacer()
                    Button("Resume Now") { controller.resumeAutomationNow() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(MacFlowSpacing.space24)
        .frame(width: 680)
        .background(MacFlowColor.canvas)
    }

    private func rulePicker(title: String, icon: String, selection: Binding<UUID?>) -> some View {
        HStack(spacing: MacFlowSpacing.space10) {
            Image(systemName: icon)
                .foregroundStyle(MacFlowColor.wallpaper)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
            Spacer()
            Picker(title, selection: selection) {
                Text("None").tag(UUID?.none)
                ForEach(controller.library.scenes) { scene in
                    Text(scene.title).tag(Optional(scene.id))
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(MacFlowSpacing.space10)
        .background(MacFlowColor.surface1, in: RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
        }
    }

    private func automationBinding<Value>(
        _ keyPath: WritableKeyPath<WallpaperAutomationConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { controller.automationConfiguration[keyPath: keyPath] },
            set: { newValue in
                controller.updateAutomationConfiguration { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func dayPeriodBinding(_ period: WallpaperDayPeriod) -> Binding<UUID?> {
        Binding(
            get: { controller.automationConfiguration.sceneID(for: period) },
            set: { sceneID in
                controller.updateAutomationConfiguration { $0.setSceneID(sceneID, for: period) }
            }
        )
    }
}

private extension MacFlowSpacing {
    static let space5: CGFloat = 5
}

/// Lightweight layout for the small, variable-width collection chips in the
/// inspector. It avoids a GeometryReader and performs no continuous updates.
private struct MacFlowWrapLayout: Layout {
    let spacing: CGFloat

    struct Cache {
        var sizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let maximumWidth = proposal.width ?? cache.sizes.reduce(0) { $0 + $1.width + spacing }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for size in cache.sizes {
            if x > 0, x + size.width > maximumWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maximumWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for (subview, size) in zip(subviews, cache.sizes) {
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
