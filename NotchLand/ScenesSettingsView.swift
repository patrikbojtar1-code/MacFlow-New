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
                WallpaperNativeSearchField(text: $browser.query)
                    .frame(minWidth: 180, idealWidth: 260, maxWidth: 320, minHeight: 30, maxHeight: 30)
                    .layoutPriority(1)
                    .accessibilityIdentifier("wallpapers.search")

                WallpaperNativeMenuButton(
                    systemImage: "arrow.up.arrow.down",
                    accessibilityLabel: "Sort scenes",
                    items: WallpaperBrowserSort.allCases.map(\.title)
                ) { index in
                    guard WallpaperBrowserSort.allCases.indices.contains(index) else { return }
                    selectSort(WallpaperBrowserSort.allCases[index])
                }
                .frame(width: 34, height: 30)
                .accessibilityIdentifier("wallpapers.sort")

                WallpaperNativeMenuButton(
                    systemImage: "ellipsis.circle",
                    accessibilityLabel: "Scene and automation options",
                    items: sceneOptionTitles
                ) { index in
                    handleSceneOption(at: index)
                }
                .frame(width: 34, height: 30)
                .accessibilityIdentifier("wallpapers.options")

                WallpaperNativeLayoutControl(selection: $browser.layout)
                    .frame(width: 76, height: 30)

                WallpaperNativeActionButton(
                    title: "Import",
                    systemImage: "plus",
                    isEnabled: !isImporting,
                    action: presentImporter
                )
                .frame(width: 92, height: 30)
                .accessibilityIdentifier("wallpapers.import")
            }
        }
        .padding(.horizontal, MacFlowSpacing.space16)
        .frame(minHeight: 62)
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

    private var sceneOptionTitles: [String] {
        ["Automation…", "New Collection…"]
            + controller.library.collections
                .filter { $0.kind == .custom }
                .map(\.title)
    }

    private func handleSceneOption(at index: Int) {
        switch index {
        case 0:
            presentsAutomation = true
        case 1:
            presentsNewCollection = true
        default:
            let collections = controller.library.collections.filter { $0.kind == .custom }
            let collectionIndex = index - 2
            guard collections.indices.contains(collectionIndex) else { return }
            selectScope(.collection(collections[collectionIndex].id))
        }
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
        }
    }

    private func presentImporter() {
        let panel = NSOpenPanel()
        panel.title = "Import Wallpaper Scene"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.image, .movie, .notchLandScene]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in handleImportedURL(url) }
        }
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

private struct WallpaperNativeSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search scenes"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = true
        field.delegate = context.coordinator
        field.focusRingType = .default
        field.setAccessibilityLabel("Search scenes")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        guard field.stringValue != text else { return }
        field.stringValue = text
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

private struct WallpaperNativeMenuButton: NSViewRepresentable {
    let systemImage: String
    let accessibilityLabel: String
    let items: [String]
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectItem(_:))
        button.setAccessibilityLabel(accessibilityLabel)
        configure(button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        guard context.coordinator.items != items else { return }
        configure(button)
    }

    private func configure(_ button: NSPopUpButton) {
        button.removeAllItems()
        button.addItem(withTitle: accessibilityLabel)
        button.item(at: 0)?.image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: accessibilityLabel
        )
        items.forEach { button.addItem(withTitle: $0) }
        button.selectItem(at: 0)
        (button.target as? Coordinator)?.items = items
    }

    final class Coordinator: NSObject {
        var items: [String] = []
        var onSelect: (Int) -> Void

        init(onSelect: @escaping (Int) -> Void) {
            self.onSelect = onSelect
        }

        @objc func selectItem(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem - 1
            sender.selectItem(at: 0)
            guard items.indices.contains(index) else { return }
            onSelect(index)
        }
    }
}

private struct WallpaperNativeLayoutControl: NSViewRepresentable {
    @Binding var selection: WallpaperBrowserLayout

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = 2
        control.trackingMode = .selectOne
        control.segmentStyle = .rounded
        control.setImage(NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Grid"), forSegment: 0)
        control.setImage(NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "List"), forSegment: 1)
        control.setWidth(34, forSegment: 0)
        control.setWidth(34, forSegment: 1)
        control.target = context.coordinator
        control.action = #selector(Coordinator.changeLayout(_:))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        control.selectedSegment = selection == .grid ? 0 : 1
    }

    final class Coordinator: NSObject {
        var selection: Binding<WallpaperBrowserLayout>

        init(selection: Binding<WallpaperBrowserLayout>) {
            self.selection = selection
        }

        @objc func changeLayout(_ sender: NSSegmentedControl) {
            selection.wrappedValue = sender.selectedSegment == 0 ? .grid : .list
        }
    }
}

private struct WallpaperNativeActionButton: NSViewRepresentable {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.performAction))
        button.bezelStyle = .rounded
        button.bezelColor = .controlAccentColor
        button.contentTintColor = .white
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel("Import wallpaper")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
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
