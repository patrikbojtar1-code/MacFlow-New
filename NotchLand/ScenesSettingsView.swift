//
//  ScenesSettingsView.swift
//  MacFlow
//
//  Wallpaper browser with click-to-apply scene selection.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScenesSettingsView: View {
    @EnvironmentObject private var controller: WallpaperSceneController
    @StateObject private var browser = WallpaperBrowserState()
    @State private var presentsAutomation = false
    @State private var presentsNewCollection = false
    @State private var presentsSceneConfiguration = false
    @State private var newCollectionName = ""
    @State private var isImporting = false
    @State private var presentsImporter = false
    @State private var showsCompactSearch = false
    @State private var showsSortOptions = false
    @State private var showsSceneOptions = false
    @State private var activationTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    action: presentImporter
                )
            } else {
                browserContent
            }
        }
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
                    selectScope(.collection(collection.id))
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
        .sheet(isPresented: $presentsSceneConfiguration) {
            if let scene = selectedScene {
                sceneConfigurationSheet(scene)
            }
        }
        .fileImporter(
            isPresented: $presentsImporter,
            allowedContentTypes: [.image, .movie, .notchLandScene],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .onAppear { synchronizeSelection() }
        .onDisappear {
            activationTask?.cancel()
            activationTask = nil
        }
        .onChange(of: sceneIDs) { _, _ in synchronizeSelection() }
        .onChange(of: controller.activeSceneID) { _, _ in synchronizeSelection() }
        .onChange(of: browser.scope) { _, _ in synchronizeSelectionToVisibleScenes() }
        .onChange(of: browser.query) { _, _ in synchronizeSelectionToVisibleScenes() }
    }

    private var browserToolbar: some View {
        HStack(spacing: MacFlowSpacing.space8) {
            Text("Wallpapers")
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.25)

            Spacer(minLength: MacFlowSpacing.space16)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: MacFlowSpacing.space8) {
                    searchField
                    sortControl
                    sceneOptionsControl
                    layoutControl
                    importControl(showsTitle: true)
                }

                HStack(spacing: MacFlowSpacing.space8) {
                    compactSearchControl
                    sortControl
                    sceneOptionsControl
                    layoutControl
                    importControl(showsTitle: false)
                }
            }
        }
        .padding(.horizontal, MacFlowSpacing.space16)
        .frame(minHeight: 62)
    }

    private var searchField: some View {
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
        .padding(.horizontal, MacFlowSpacing.space12)
        .frame(width: 168, height: 30)
        .background(
            MacFlowColor.surface2,
            in: RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
                .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
        }
    }

    private var compactSearchControl: some View {
        Button {
            showsCompactSearch.toggle()
        } label: {
            Image(systemName: "magnifyingglass")
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Search scenes")
        .accessibilityLabel("Search scenes")
        .popover(isPresented: $showsCompactSearch, arrowEdge: .bottom) {
            searchField
                .padding(MacFlowSpacing.space12)
        }
    }

    private var sortControl: some View {
        Button {
            showsSortOptions.toggle()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            MacFlowColor.surface2,
            in: RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
                .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
        }
        .fixedSize()
        .help("Sort: \(browser.sort.title)")
        .accessibilityLabel("Sort scenes")
        .accessibilityValue(browser.sort.title)
        .accessibilityIdentifier("wallpapers.sort")
        .popover(isPresented: $showsSortOptions, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                ForEach(WallpaperBrowserSort.allCases) { sort in
                    Button {
                        showsSortOptions = false
                        selectSort(sort)
                    } label: {
                        HStack(spacing: MacFlowSpacing.space8) {
                            Image(systemName: sort.systemImage)
                                .frame(width: 16)
                            Text(sort.title)
                            Spacer(minLength: MacFlowSpacing.space16)
                            if browser.sort == sort {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(MacFlowColor.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, MacFlowSpacing.space8)
                    .frame(height: 28)
                    .accessibilityIdentifier("wallpapers.sort.\(sort.rawValue)")
                }
            }
            .padding(MacFlowSpacing.space8)
            .frame(width: 164)
        }
    }

    private var sceneOptionsControl: some View {
        Button {
            showsSceneOptions.toggle()
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            MacFlowColor.surface2,
            in: RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
                .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
        }
        .fixedSize()
        .help("Scene and automation options")
        .accessibilityLabel("Scene and automation options")
        .accessibilityIdentifier("wallpapers.options")
        .popover(isPresented: $showsSceneOptions, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                sceneOptionButton(
                    title: "Automation…",
                    systemImage: "clock.arrow.2.circlepath",
                    identifier: "wallpapers.options.automation"
                ) {
                    showsSceneOptions = false
                    presentsAutomation = true
                }

                Divider()

                sceneOptionButton(
                    title: "New Collection…",
                    systemImage: "folder.badge.plus",
                    identifier: "wallpapers.options.newCollection"
                ) {
                    showsSceneOptions = false
                    presentsNewCollection = true
                }

                ForEach(controller.library.collections.filter { $0.kind == .custom }) { collection in
                    sceneOptionButton(
                        title: collection.title,
                        systemImage: "folder",
                        identifier: "wallpapers.options.collection.\(collection.id.uuidString)"
                    ) {
                        showsSceneOptions = false
                        selectScope(.collection(collection.id))
                    }
                }
            }
            .padding(MacFlowSpacing.space8)
            .frame(width: 200)
        }
    }

    private func sceneOptionButton(
        title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: MacFlowSpacing.space8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MacFlowSpacing.space8)
        .frame(height: 28)
        .accessibilityIdentifier(identifier)
    }

    private var layoutControl: some View {
        HStack(spacing: MacFlowSpacing.space4) {
            layoutButton(.grid, systemImage: "square.grid.2x2", title: "Grid")
            layoutButton(.list, systemImage: "list.bullet", title: "List")
        }
        .padding(MacFlowSpacing.space4)
        .background(
            MacFlowColor.surface2,
            in: RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
                .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
        }
    }

    private func layoutButton(
        _ layout: WallpaperBrowserLayout,
        systemImage: String,
        title: String
    ) -> some View {
        let isSelected = browser.layout == layout
        return Button {
            selectLayout(layout)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .primary : MacFlowColor.textSecondary)
                .frame(width: 24, height: 22)
                .background(
                    isSelected ? MacFlowColor.surface3 : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("wallpapers.layout.\(layout.rawValue)")
    }

    @ViewBuilder
    private func importControl(showsTitle: Bool) -> some View {
        Button {
            presentImporter()
        } label: {
            if showsTitle {
                Label("Import", systemImage: "plus")
            } else {
                Image(systemName: "plus")
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(MacFlowColor.accent)
        .controlSize(.small)
        .disabled(isImporting)
        .help("Import wallpaper")
        .accessibilityLabel("Import wallpaper")
        .accessibilityIdentifier("wallpapers.import")
    }

    private var browserContent: some View {
        VStack(spacing: 0) {
            selectedPreview
                .padding(.horizontal, MacFlowSpacing.space16)
                .padding(.top, MacFlowSpacing.space16)

            libraryHeader
                .padding(.horizontal, MacFlowSpacing.space16)
                .padding(.top, MacFlowSpacing.space16)
                .padding(.bottom, MacFlowSpacing.space12)

            if isImporting {
                WallpaperImportSkeleton()
                    .padding(.horizontal, MacFlowSpacing.space16)
                    .padding(.bottom, MacFlowSpacing.space12)
            }

            sceneLibrary
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                    .font(.system(size: 17, weight: .semibold))
                                    .lineLimit(2)
                            }

                            Label(scene.kind.displayName, systemImage: scene.kind.systemImage)
                            .font(.system(size: 10.5))
                            .foregroundStyle(MacFlowColor.textSecondary)

                            Spacer(minLength: 0)

                            previewActions(for: scene)
                        }
                        .padding(MacFlowSpacing.space12)
                        .frame(width: 180, alignment: .leading)

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
                                    .padding(.vertical, MacFlowSpacing.space8)
                                    .background(.black.opacity(0.60), in: Capsule())
                                    .padding(MacFlowSpacing.space12)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                    .frame(height: 162)
                }
            } else {
                MacFlowPanel(.grouped) {
                    MacFlowEmptyState(
                        systemImage: "photo",
                        title: "No scene matches",
                        detail: "Clear the search or choose another filter."
                    )
                    .frame(height: 162)
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
                    Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(MacFlowColor.accent)
                .help(controller.isPaused ? "Resume wallpaper" : "Pause wallpaper")
                .accessibilityLabel(controller.isPaused ? "Resume wallpaper" : "Pause wallpaper")

                Button {
                    controller.deactivate()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .help("Stop wallpaper")
                .accessibilityLabel("Stop wallpaper")
            }

            Button {
                presentsSceneConfiguration = true
            } label: {
                Label("Configure", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)

            Menu {
                Button {
                    controller.library.toggleFavorite(scene)
                } label: {
                    Label(
                        controller.library.isFavorite(scene) ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: controller.library.isFavorite(scene) ? "star.slash" : "star"
                    )
                }
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
                                systemImage: controller.library.contains(scene, in: collection)
                                    ? "checkmark.circle.fill"
                                    : "circle"
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
            .help("Scene actions")
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
                        selectScope(.collection(collection.id))
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
            selectScope(scope)
        }
        .buttonStyle(MacFlowInteractiveButtonStyle())
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(isSelected ? .primary : MacFlowColor.textSecondary)
        .padding(.horizontal, MacFlowSpacing.space12)
        .padding(.vertical, MacFlowSpacing.space8)
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
                    selectScope(.all)
                }
            )
        } else {
            ScrollView {
                if browser.layout == .grid {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 145, maximum: 230), spacing: MacFlowSpacing.space8)],
                        spacing: MacFlowSpacing.space12
                    ) {
                        ForEach(visibleScenes) { scene in
                            WallpaperSceneTile(
                                scene: scene,
                                previewURL: controller.library.previewURL(for: scene),
                                isSelected: scene.id == browser.selectedSceneID,
                                isActive: scene.id == controller.activeSceneID,
                                isFavorite: controller.library.isFavorite(scene),
                                select: { activate(scene) },
                                toggleFavorite: { controller.library.toggleFavorite(scene) }
                            )
                        }
                    }
                } else {
                    LazyVStack(spacing: MacFlowSpacing.space8) {
                        ForEach(visibleScenes) { scene in
                            WallpaperSceneListRow(
                                scene: scene,
                                previewURL: controller.library.previewURL(for: scene),
                                isSelected: scene.id == browser.selectedSceneID,
                                isActive: scene.id == controller.activeSceneID,
                                select: { activate(scene) }
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

                VStack(alignment: .leading, spacing: MacFlowSpacing.space8) {
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
        }
    }

    private func sceneConfigurationSheet(_ scene: WallpaperScene) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                    Text(scene.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Wallpaper settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { presentsSceneConfiguration = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(MacFlowSpacing.space16)

            Divider()

            ScrollView {
                inspectorSettings(scene)
                    .padding(.vertical, MacFlowSpacing.space8)
            }
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 360, idealHeight: 440)
        .background(MacFlowColor.canvas)
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

    private func activate(_ scene: WallpaperScene) {
        withAnimation(AppMotion.interaction(reduceMotion: reduceMotion)) {
            browser.selectedSceneID = scene.id
        }
        guard controller.activeSceneID != scene.id else { return }
        NotchHaptics.perform(.confirmation)
        activationTask?.cancel()
        activationTask = Task { @MainActor in
            // Give SwiftUI one render pass to show the selection before the
            // AppKit wallpaper renderer starts preparing windows and media.
            await Task.yield()
            guard !Task.isCancelled else { return }
            controller.apply(scene)
            activationTask = nil
        }
    }

    private func selectLayout(_ layout: WallpaperBrowserLayout) {
        guard browser.layout != layout else { return }
        Task { @MainActor in
            // AppKit's segmented/menu controls are still completing their
            // action here. Rebuilding the large library on the next turn
            // avoids constraint invalidation re-entrancy in NSHostingView.
            await Task.yield()
            withAnimation(AppMotion.stateChange(reduceMotion: reduceMotion)) {
                browser.layout = layout
            }
        }
    }

    private func selectSort(_ sort: WallpaperBrowserSort) {
        guard browser.sort != sort else { return }
        Task { @MainActor in
            await Task.yield()
            withAnimation(AppMotion.stateChange(reduceMotion: reduceMotion)) {
                browser.sort = sort
            }
        }
    }

    private func selectScope(_ scope: WallpaperBrowserScope) {
        guard browser.scope != scope else { return }
        Task { @MainActor in
            await Task.yield()
            withAnimation(AppMotion.stateChange(reduceMotion: reduceMotion)) {
                browser.scope = scope
            }
        }
    }

    private func presentImporter() {
        presentsImporter = true
    }

    private func handleImportedURL(_ url: URL) {
        isImporting = true
        Task {
            let imported = await controller.importAndApply(from: url)
            isImporting = false
            if imported {
                browser.query = ""
                selectScope(.all)
                browser.selectedSceneID = controller.activeSceneID
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            handleImportedURL(url)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 0) {
                    WallpaperThumbnailView(scene: scene, url: previewURL, scalingMode: .fill, dimming: 0)
                        .aspectRatio(16 / 9, contentMode: .fit)

                    HStack(spacing: MacFlowSpacing.space8) {
                        VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                            Text(scene.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                            HStack(spacing: MacFlowSpacing.space4) {
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
                    .padding(MacFlowSpacing.space12)
                }
                .background(MacFlowColor.surface1)
                .clipShape(RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous)
                        .stroke(
                            isSelected ? MacFlowColor.wallpaper : MacFlowColor.borderSubtle,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MacFlowInteractiveButtonStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])

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
        .onHover { isHovered = $0 }
        .animation(AppMotion.stateChange(reduceMotion: reduceMotion), value: isHovered)
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
        .buttonStyle(MacFlowInteractiveButtonStyle())
    }
}

private struct WallpaperThumbnailView: View {
    let scene: WallpaperScene
    let url: URL
    let scalingMode: WallpaperSceneRenderingConfiguration.ScalingMode
    let dimming: Double

    var body: some View {
        WallpaperPreviewImage(
            scene: scene,
            url: url,
            scalingMode: scalingMode,
            dimming: dimming
        )
    }
}

private struct WallpaperImportSkeleton: View {
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
            ProgressView("Importing")
                .controlSize(.small)
                .foregroundStyle(MacFlowColor.textSecondary)
        }
        .padding(MacFlowSpacing.space12)
        .background(MacFlowColor.surface1, in: RoundedRectangle(cornerRadius: MacFlowRadius.compact, style: .continuous))
    }
}

private struct WallpaperAutomationEditor: View {
    @EnvironmentObject private var controller: WallpaperSceneController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space24) {
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
        HStack(spacing: MacFlowSpacing.space12) {
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
        .padding(MacFlowSpacing.space12)
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
