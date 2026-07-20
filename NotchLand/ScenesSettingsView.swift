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
    @State private var presentsPlaylistEditor = false
    @State private var newCollectionName = ""
    @State private var isImporting = false
    @State private var activationTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool
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
        .alert("New Playlist", isPresented: $presentsNewCollection) {
            TextField("Playlist name", text: $newCollectionName)
            Button("Cancel", role: .cancel) { newCollectionName = "" }
            Button("Create") {
                if let collection = controller.library.createCollection(named: newCollectionName) {
                    selectScope(.collection(collection.id))
                }
                newCollectionName = ""
            }
            .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Playlists keep an ordered set of scenes without copying their files.")
        }
        .sheet(isPresented: $presentsAutomation) {
            WallpaperAutomationEditor()
                .environmentObject(controller)
        }
        .sheet(isPresented: $presentsPlaylistEditor) {
            WallpaperPlaylistEditor()
                .environmentObject(controller)
        }
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

            HStack(spacing: MacFlowSpacing.space8) {
                wallpaperSearchField
                    .layoutPriority(1)

                wallpaperSortMenu
                wallpaperOptionsMenu
                wallpaperLayoutControl

                Button(action: presentImporter) {
                    Label("Import", systemImage: "plus")
                        .frame(minWidth: 66)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(MacFlowColor.accent)
                .disabled(isImporting)
                .accessibilityIdentifier("wallpapers.import")
            }
        }
        .padding(.horizontal, MacFlowSpacing.space16)
        .frame(minHeight: 62)
        .background(MacFlowColor.canvas)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        .zIndex(20)
    }

    private var wallpaperSearchField: some View {
        HStack(spacing: MacFlowSpacing.space8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MacFlowColor.textTertiary)

            TextField("Search scenes", text: $browser.query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit(synchronizeSelectionToVisibleScenes)
                .accessibilityIdentifier("wallpapers.search.field")

            if !browser.query.isEmpty {
                Button {
                    browser.query = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(MacFlowColor.textTertiary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, MacFlowSpacing.space12)
        .frame(minWidth: 180, idealWidth: 260, maxWidth: 320, minHeight: 32, maxHeight: 32)
        .background(MacFlowColor.surface2, in: RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
                .stroke(isSearchFocused ? MacFlowColor.accent.opacity(0.8) : MacFlowColor.borderSubtle, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onTapGesture { isSearchFocused = true }
        .accessibilityIdentifier("wallpapers.search")
    }

    private var wallpaperSortMenu: some View {
        Menu {
            ForEach(WallpaperBrowserSort.allCases) { sort in
                Button {
                    selectSort(sort)
                } label: {
                    Label(sort.title, systemImage: browser.sort == sort ? "checkmark" : sort.systemImage)
                }
            }
        } label: {
            toolbarIcon("arrow.up.arrow.down", accessibilityLabel: "Sort scenes")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("wallpapers.sort")
    }

    private var wallpaperOptionsMenu: some View {
        Menu {
            Button("Automation…", systemImage: "clock.arrow.2.circlepath") {
                presentsAutomation = true
            }
            Button("New Playlist…", systemImage: "rectangle.stack.badge.plus") {
                presentsNewCollection = true
            }
            Button("Manage Playlists…", systemImage: "music.note.list") {
                presentsPlaylistEditor = true
            }
            if !controller.library.collections.filter({ $0.kind == .custom }).isEmpty {
                Divider()
                ForEach(controller.library.collections.filter { $0.kind == .custom }) { collection in
                    Button(collection.title, systemImage: "folder") {
                        selectScope(.collection(collection.id))
                    }
                }
            }
        } label: {
            toolbarIcon("ellipsis.circle", accessibilityLabel: "Scene and automation options")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityIdentifier("wallpapers.options")
    }

    private var wallpaperLayoutControl: some View {
        HStack(spacing: MacFlowSpacing.space4) {
            wallpaperLayoutButton(.grid, systemImage: "square.grid.2x2")
            wallpaperLayoutButton(.list, systemImage: "list.bullet")
        }
        .padding(MacFlowSpacing.space4)
        .background(MacFlowColor.surface2, in: RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
                .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func wallpaperLayoutButton(_ layout: WallpaperBrowserLayout, systemImage: String) -> some View {
        Button {
            selectLayout(layout)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 24)
                .background(
                    browser.layout == layout ? MacFlowColor.accent.opacity(0.22) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout == .grid ? "Grid" : "List")
        .accessibilityValue(browser.layout == layout ? "Selected" : "Not selected")
        .accessibilityAddTraits(browser.layout == layout ? .isSelected : [])
        .accessibilityIdentifier("wallpapers.layout.\(layout.rawValue)")
    }

    private func toolbarIcon(_ systemImage: String, accessibilityLabel: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 32, height: 30)
            .background(MacFlowColor.surface2, in: RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MacFlowRadius.control, style: .continuous)
                    .stroke(MacFlowColor.borderSubtle, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
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
                        selectedSceneStage(scene)

                        Divider().overlay(MacFlowColor.borderSubtle)

                        selectedSceneInspector(scene)
                            .frame(width: 282)
                    }
                    .frame(height: 264)
                }
            } else {
                MacFlowPanel(.grouped) {
                    MacFlowEmptyState(
                        systemImage: "photo",
                        title: "No scene matches",
                        detail: "Clear the search or choose another filter."
                    )
                    .frame(height: 264)
                }
            }
        }
    }

    private func selectedSceneStage(_ scene: WallpaperScene) -> some View {
        WallpaperThumbnailView(
            scene: scene,
            url: controller.library.previewURL(for: scene),
            scalingMode: scene.rendering.scalingMode,
            dimming: scene.rendering.dimming,
            animatesMotion: true
        )
        .overlay {
            LinearGradient(
                colors: [.clear, .black.opacity(0.08), .black.opacity(0.76)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: MacFlowSpacing.space8) {
                statusBadge(for: scene)
                if scene.kind == .video {
                    Label("LOOP", systemImage: "repeat")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, MacFlowSpacing.space8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.48), in: Capsule())
                }
            }
            .padding(MacFlowSpacing.space12)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                controller.library.toggleFavorite(scene)
                NotchHaptics.perform(.navigation)
            } label: {
                Image(systemName: controller.library.isFavorite(scene) ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(controller.library.isFavorite(scene) ? .yellow : .white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.48), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(MacFlowSpacing.space12)
            .accessibilityLabel(controller.library.isFavorite(scene) ? "Remove from Favorites" : "Add to Favorites")
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                Text(scene.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                HStack(spacing: MacFlowSpacing.space8) {
                    Text("by \(scene.author)")
                    Text("•")
                    Label(scene.kind.displayName, systemImage: scene.kind.systemImage)
                    Text("•")
                    Text(scene.createdAt, format: .dateTime.month(.abbreviated).day())
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
            }
            .padding(MacFlowSpacing.space16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func selectedSceneInspector(_ scene: WallpaperScene) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: MacFlowSpacing.space8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CUSTOMIZE")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(MacFlowColor.textSecondary)
                        .tracking(0.85)
                    Text(scene.id == controller.activeSceneID ? "Applied to desktop" : "Preview before applying")
                        .font(.system(size: 10.5))
                        .foregroundStyle(MacFlowColor.textTertiary)
                }
                Spacer()
                sceneActionsMenu(scene)
            }
            .padding(.horizontal, MacFlowSpacing.space12)
            .padding(.vertical, MacFlowSpacing.space8)

            Divider().overlay(MacFlowColor.borderSubtle)

            ScrollView {
                inspectorSettings(scene)
            }
            .scrollIndicators(.hidden)

            Divider().overlay(MacFlowColor.borderSubtle)

            HStack(spacing: MacFlowSpacing.space8) {
                if scene.id == controller.activeSceneID {
                    Button {
                        controller.togglePaused()
                    } label: {
                        Label(controller.isPaused ? "Resume" : "Pause", systemImage: controller.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        controller.deactivate()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Stop wallpaper")
                } else {
                    Button {
                        apply(scene)
                    } label: {
                        Label("Apply to Desktop", systemImage: "display")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MacFlowColor.wallpaper)
                    .accessibilityIdentifier("wallpapers.apply")
                }
            }
            .controlSize(.regular)
            .padding(MacFlowSpacing.space12)
        }
        .background(MacFlowColor.surface1)
    }

    private func statusBadge(for scene: WallpaperScene) -> some View {
        Label(
            scene.id == controller.activeSceneID ? "ACTIVE" : "PREVIEW",
            systemImage: scene.id == controller.activeSceneID ? "checkmark.circle.fill" : "eye.fill"
        )
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, MacFlowSpacing.space8)
        .padding(.vertical, 5)
        .background(scene.id == controller.activeSceneID ? Color.green.opacity(0.78) : .black.opacity(0.48), in: Capsule())
        .accessibilityIdentifier(
            scene.id == controller.activeSceneID
                ? "wallpapers.status.active"
                : "wallpapers.status.preview"
        )
    }

    private func sceneActionsMenu(_ scene: WallpaperScene) -> some View {
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
            Menu("Add to Playlist") {
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
                if controller.library.collections.allSatisfy({ $0.kind != .custom }) {
                    Button("Create Playlist…") { presentsNewCollection = true }
                }
            }
            Divider()
            Button("Remove Scene", role: .destructive) {
                controller.remove(scene)
                synchronizeSelection()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Scene actions")
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
                Label(collectionFilterTitle, systemImage: "rectangle.stack")
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
                                select: { selectScene(scene) },
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
                                select: { selectScene(scene) }
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
            MacFlowInspectorSection("Scene Studio") {
                if scene.kind == .image {
                    Picker(
                        "Motion",
                        selection: renderingBinding(for: scene, keyPath: \.motionPreset)
                    ) {
                        ForEach(WallpaperSceneRenderingConfiguration.MotionPreset.allCases) { preset in
                            Label(preset.title, systemImage: preset.systemImage).tag(preset)
                        }
                    }

                    Text(scene.rendering.motionPreset.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(MacFlowColor.textSecondary)
                } else {
                    Label("Motion is provided by the source video", systemImage: "film")
                        .font(.system(size: 10.5))
                        .foregroundStyle(MacFlowColor.textSecondary)
                }

                gradingSlider(
                    "Saturation",
                    value: scene.rendering.saturation,
                    range: WallpaperSceneRenderingConfiguration.saturationRange,
                    binding: renderingBinding(for: scene, keyPath: \.saturation)
                )
                gradingSlider(
                    "Contrast",
                    value: scene.rendering.contrast,
                    range: WallpaperSceneRenderingConfiguration.contrastRange,
                    binding: renderingBinding(for: scene, keyPath: \.contrast)
                )
                gradingSlider(
                    "Vignette",
                    value: scene.rendering.vignette,
                    range: WallpaperSceneRenderingConfiguration.vignetteRange,
                    binding: renderingBinding(for: scene, keyPath: \.vignette),
                    displaysAsPercent: true
                )
            }
            Divider().overlay(MacFlowColor.borderSubtle)
            MacFlowInspectorSection("Scene Composer") {
                Picker(
                    "Atmosphere",
                    selection: renderingBinding(for: scene, keyPath: \.ambientEffect)
                ) {
                    ForEach(WallpaperSceneRenderingConfiguration.AmbientEffect.allCases) { effect in
                        Label(effect.title, systemImage: effect.systemImage).tag(effect)
                    }
                }

                Text(scene.rendering.ambientEffect.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(MacFlowColor.textSecondary)

                if scene.rendering.ambientEffect != .none {
                    gradingSlider(
                        "Effect intensity",
                        value: scene.rendering.effectIntensity,
                        range: WallpaperSceneRenderingConfiguration.effectIntensityRange,
                        binding: renderingBinding(for: scene, keyPath: \.effectIntensity),
                        displaysAsPercent: true
                    )
                }

                gradingSlider(
                    "Pointer parallax",
                    value: scene.rendering.parallaxStrength,
                    range: WallpaperSceneRenderingConfiguration.parallaxStrengthRange,
                    binding: renderingBinding(for: scene, keyPath: \.parallaxStrength),
                    displaysAsPercent: true
                )

                if controller.performance.effectiveProfile == .eco {
                    Label("Composer effects pause automatically in Eco", systemImage: "leaf.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.green)
                }
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
            Divider().overlay(MacFlowColor.borderSubtle)
            MacFlowInspectorSection("Displays") {
                Picker(
                    "Target",
                    selection: Binding(
                        get: { controller.displayPolicy },
                        set: { controller.setDisplayPolicy($0) }
                    )
                ) {
                    ForEach(NotchDisplayPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()

                if controller.displayPolicy == .selectedDisplays {
                    VStack(spacing: MacFlowSpacing.space4) {
                        ForEach(controller.availableDisplays) { display in
                            Button {
                                controller.toggleTargetDisplay(display.id)
                            } label: {
                                HStack(spacing: MacFlowSpacing.space8) {
                                    Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                                    Text(display.name)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(
                                        systemName: controller.selectedDisplayIDs.contains(display.id)
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                    )
                                    .foregroundStyle(
                                        controller.selectedDisplayIDs.contains(display.id)
                                            ? MacFlowColor.wallpaper
                                            : MacFlowColor.textTertiary
                                    )
                                }
                                .font(.system(size: 10.5, weight: .medium))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text(displayTargetSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(MacFlowColor.textSecondary)
            }
            Divider().overlay(MacFlowColor.borderSubtle)
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
        }
    }

    private func gradingSlider(
        _ title: String,
        value: Double,
        range: ClosedRange<Double>,
        binding: Binding<Double>,
        displaysAsPercent: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5))
                Spacer()
                Text(
                    displaysAsPercent
                        ? value.formatted(.percent.precision(.fractionLength(0)))
                        : value.formatted(.number.precision(.fractionLength(2)))
                )
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(MacFlowColor.textSecondary)
            }
            Slider(value: binding, in: range)
                .tint(MacFlowColor.wallpaper)
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

    private var displayTargetSummary: String {
        let count = controller.targetDisplayIDs.count
        guard count > 0 else { return "No display selected" }
        return count == 1 ? "1 display will update" : "\(count) displays will update together"
    }

    private var collectionFilterTitle: String {
        guard case .collection(let collectionID) = browser.scope,
              let collection = controller.library.collections.first(where: { $0.id == collectionID }) else {
            return "Playlists"
        }
        return collection.title
    }

    private func synchronizeSelection() {
        browser.ensureSelection(in: controller.library.scenes, preferredID: controller.activeSceneID)
    }

    private func synchronizeSelectionToVisibleScenes() {
        browser.ensureSelection(in: visibleScenes, preferredID: controller.activeSceneID)
    }

    private func selectScene(_ scene: WallpaperScene) {
        withAnimation(AppMotion.interaction(reduceMotion: reduceMotion)) {
            browser.selectedSceneID = scene.id
        }
        NotchHaptics.perform(.navigation)
    }

    private func apply(_ scene: WallpaperScene) {
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
        withAnimation(AppMotion.stateChange(reduceMotion: reduceMotion)) {
            browser.layout = layout
        }
    }

    private func selectSort(_ sort: WallpaperBrowserSort) {
        guard browser.sort != sort else { return }
        withAnimation(AppMotion.stateChange(reduceMotion: reduceMotion)) {
            browser.sort = sort
        }
    }

    private func selectScope(_ scope: WallpaperBrowserScope) {
        guard browser.scope != scope else { return }
        withAnimation(AppMotion.stateChange(reduceMotion: reduceMotion)) {
            browser.scope = scope
            if case .collection = scope {
                browser.sort = .playlist
            } else if browser.sort == .playlist {
                browser.sort = .recent
            }
        }
    }

    private func presentImporter() {
        let panel = NSOpenPanel()
        panel.title = "Import Wallpaper Scene"
        panel.prompt = "Import Selected"
        panel.allowedContentTypes = [.image, .movie, .notchLandScene]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            Task { @MainActor in handleImportedURLs(panel.urls) }
        }
    }

    private func handleImportedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        Task { @MainActor in
            var importedScenes: [WallpaperScene] = []
            for url in urls {
                guard !Task.isCancelled else { break }
                if let scene = await controller.importScene(from: url) {
                    importedScenes.append(scene)
                }
            }
            isImporting = false
            if let lastImported = importedScenes.last {
                browser.query = ""
                selectScope(.all)
                browser.selectedSceneID = lastImported.id
                NotchHaptics.perform(.confirmation)
            }
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
    var animatesMotion = false

    var body: some View {
        WallpaperPreviewImage(
            scene: scene,
            url: url,
            scalingMode: scalingMode,
            dimming: dimming,
            saturation: scene.rendering.saturation,
            contrast: scene.rendering.contrast,
            vignette: scene.rendering.vignette,
            motionPreset: scene.rendering.motionPreset,
            ambientEffect: scene.rendering.ambientEffect,
            effectIntensity: scene.rendering.effectIntensity,
            parallaxStrength: scene.rendering.parallaxStrength,
            animatesMotion: animatesMotion
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

private struct WallpaperPlaylistEditor: View {
    @EnvironmentObject private var controller: WallpaperSceneController
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlaylistID: UUID?
    @State private var presentsNewPlaylist = false
    @State private var presentsDeleteConfirmation = false
    @State private var newPlaylistName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                    Text("Playlists")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Build an ordered rotation from your wallpaper library.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(MacFlowColor.textSecondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(MacFlowSpacing.space16)

            Divider().overlay(MacFlowColor.borderSubtle)

            HSplitView {
                playlistSidebar
                    .frame(minWidth: 190, idealWidth: 210, maxWidth: 240)

                playlistContents
                    .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 470, idealHeight: 520)
        .background(MacFlowColor.canvas)
        .alert("New Playlist", isPresented: $presentsNewPlaylist) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
            Button("Create") { createPlaylist() }
                .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("You can add scenes and drag them into any order.")
        }
        .confirmationDialog(
            "Delete this playlist?",
            isPresented: $presentsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Playlist", role: .destructive) { deleteSelectedPlaylist() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Wallpaper files remain safely in your library.")
        }
        .onAppear {
            if selectedPlaylistID == nil {
                selectedPlaylistID = playlists.first?.id
            }
        }
        .onChange(of: playlistIDs) { _, ids in
            if let selectedPlaylistID, ids.contains(selectedPlaylistID) { return }
            selectedPlaylistID = ids.first
        }
    }

    private var playlistSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PLAYLISTS")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(MacFlowColor.textSecondary)
                    .tracking(0.85)
                Spacer()
                Button {
                    presentsNewPlaylist = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Playlist")
            }
            .padding(MacFlowSpacing.space12)

            Divider().overlay(MacFlowColor.borderSubtle)

            if playlists.isEmpty {
                MacFlowEmptyState(
                    systemImage: "music.note.list",
                    title: "No playlists yet",
                    detail: "Create one to arrange wallpaper rotations.",
                    actionTitle: "New Playlist",
                    action: { presentsNewPlaylist = true }
                )
            } else {
                List(selection: $selectedPlaylistID) {
                    ForEach(playlists) { playlist in
                        HStack(spacing: MacFlowSpacing.space8) {
                            Image(systemName: "rectangle.stack.fill")
                                .foregroundStyle(MacFlowColor.wallpaper)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.title)
                                    .lineLimit(1)
                                Text("\(playlist.sceneIDs.count) scenes")
                                    .font(.caption2)
                                    .foregroundStyle(MacFlowColor.textSecondary)
                            }
                        }
                        .tag(playlist.id)
                    }
                }
                .listStyle(.sidebar)
            }

            Divider().overlay(MacFlowColor.borderSubtle)

            HStack {
                Button {
                    presentsNewPlaylist = true
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button(role: .destructive) {
                    presentsDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(selectedPlaylist == nil)
                .accessibilityLabel("Delete Playlist")
            }
            .padding(MacFlowSpacing.space12)
        }
        .background(MacFlowColor.surface1)
    }

    @ViewBuilder
    private var playlistContents: some View {
        if let playlist = selectedPlaylist {
            VStack(spacing: 0) {
                HStack(spacing: MacFlowSpacing.space12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.title)
                            .font(.system(size: 15, weight: .semibold))
                        Text("Drag scenes to define the playback order")
                            .font(.system(size: 10.5))
                            .foregroundStyle(MacFlowColor.textSecondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(availableScenes(for: playlist)) { scene in
                            Button {
                                controller.library.add(scene, to: playlist)
                            } label: {
                                Label(scene.title, systemImage: scene.kind.systemImage)
                            }
                        }
                        if availableScenes(for: playlist).isEmpty {
                            Text("Every scene is already included")
                        }
                    } label: {
                        Label("Add Scenes", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MacFlowColor.wallpaper)
                    .disabled(controller.library.scenes.isEmpty)
                }
                .padding(MacFlowSpacing.space16)

                Divider().overlay(MacFlowColor.borderSubtle)

                if playlistScenes.isEmpty {
                    MacFlowEmptyState(
                        systemImage: "rectangle.stack.badge.plus",
                        title: "This playlist is empty",
                        detail: "Add scenes, then drag them into the order you want."
                    )
                } else {
                    List {
                        ForEach(Array(playlistScenes.enumerated()), id: \.element.id) { index, scene in
                            HStack(spacing: MacFlowSpacing.space12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(MacFlowColor.textTertiary)
                                    .frame(width: 18)
                                WallpaperThumbnailView(
                                    scene: scene,
                                    url: controller.library.previewURL(for: scene),
                                    scalingMode: .fill,
                                    dimming: 0
                                )
                                .frame(width: 76, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scene.title)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .lineLimit(1)
                                    Text(scene.kind.displayName)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(MacFlowColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(MacFlowColor.textTertiary)
                            }
                            .padding(.vertical, MacFlowSpacing.space4)
                        }
                        .onDelete { offsets in
                            for offset in offsets where playlistScenes.indices.contains(offset) {
                                controller.library.remove(playlistScenes[offset], from: playlist)
                            }
                        }
                        .onMove { offsets, destination in
                            controller.library.moveScenes(
                                in: playlist,
                                fromOffsets: offsets,
                                toOffset: destination
                            )
                        }
                    }
                    .listStyle(.inset)
                }
            }
        } else {
            MacFlowEmptyState(
                systemImage: "music.note.list",
                title: "Choose a playlist",
                detail: "Select a playlist or create a new one."
            )
        }
    }

    private var playlists: [WallpaperSceneCollection] {
        controller.library.collections.filter { $0.kind == .custom }
    }

    private var playlistIDs: [UUID] {
        playlists.map(\.id)
    }

    private var selectedPlaylist: WallpaperSceneCollection? {
        guard let selectedPlaylistID else { return nil }
        return playlists.first { $0.id == selectedPlaylistID }
    }

    private var playlistScenes: [WallpaperScene] {
        guard let selectedPlaylist else { return [] }
        return controller.library.scenes(in: selectedPlaylist)
    }

    private func availableScenes(for playlist: WallpaperSceneCollection) -> [WallpaperScene] {
        let membership = Set(playlist.sceneIDs)
        return controller.library.scenes.filter { !membership.contains($0.id) }
    }

    private func createPlaylist() {
        if let playlist = controller.library.createCollection(named: newPlaylistName) {
            selectedPlaylistID = playlist.id
            NotchHaptics.perform(.confirmation)
        }
        newPlaylistName = ""
    }

    private func deleteSelectedPlaylist() {
        guard let selectedPlaylist else { return }
        controller.library.remove(selectedPlaylist)
        selectedPlaylistID = playlists.first?.id
    }
}

struct WallpaperAutomationEditor: View {
    @EnvironmentObject private var controller: WallpaperSceneController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacFlowSpacing.space24) {
            HStack {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space4) {
                    Text("Smart Rotation")
                        .font(.title2.weight(.semibold))
                    Text("Build a context-aware wallpaper timeline from your playlists.")
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
                    icon: "arrow.triangle.2.circlepath",
                    tint: MacFlowColor.wallpaper,
                    title: "Automatic rotation",
                    subtitle: controller.rotationSourceDetail
                ) {
                    Toggle("Automatic rotation", isOn: automationBinding(\.rotatesFavorites))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: controller.automationConfiguration.rotationSource.systemImage,
                    tint: controller.automationConfiguration.rotationSource == .favorites ? .yellow : MacFlowColor.wallpaper,
                    title: "Rotation source"
                ) {
                    Picker("Rotation source", selection: automationBinding(\.rotationSource)) {
                        ForEach(WallpaperAutomationConfiguration.RotationSource.allCases) { source in
                            Label(source.title, systemImage: source.systemImage).tag(source)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                .disabled(!controller.automationConfiguration.rotatesFavorites)

                if controller.automationConfiguration.rotationSource == .playlist {
                    MacFlowInsetDivider()
                    MacFlowSettingsRow(
                        icon: "music.note.list",
                        tint: MacFlowColor.wallpaper,
                        title: "Playlist",
                        subtitle: controller.selectedRotationPlaylist == nil
                            ? "Choose an ordered playlist"
                            : "Scenes follow the order from Playlist Manager"
                    ) {
                        Picker("Playlist", selection: automationBinding(\.rotationPlaylistID)) {
                            Text("Choose…").tag(UUID?.none)
                            ForEach(playlists) { playlist in
                                Text(playlist.title).tag(Optional(playlist.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                    .disabled(!controller.automationConfiguration.rotatesFavorites)
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
                .disabled(!controller.automationConfiguration.rotatesFavorites)

                MacFlowInsetDivider()
                MacFlowSettingsRow(
                    icon: "battery.25percent",
                    tint: .green,
                    title: "Pause rotation on Low Power",
                    subtitle: "Keeps the current scene and avoids unnecessary transitions."
                ) {
                    Toggle(
                        "Pause rotation on Low Power",
                        isOn: automationBinding(\.pausesRotationOnLowPower)
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            HStack(alignment: .top, spacing: MacFlowSpacing.space12) {
                VStack(alignment: .leading, spacing: MacFlowSpacing.space12) {
                    MacFlowSectionHeader("Context")
                    rulePicker(
                        title: "Focus scene",
                        icon: "moon.fill",
                        selection: automationBinding(\.focusSceneID)
                    )
                    rulePicker(
                        title: "Low Power",
                        icon: "battery.25percent",
                        selection: automationBinding(\.lowPowerSceneID)
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
        }
        .frame(width: 720)
        .frame(maxHeight: 680)
        .background(MacFlowColor.canvas)
    }

    private var playlists: [WallpaperSceneCollection] {
        controller.library.collections.filter { $0.kind == .custom }
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
