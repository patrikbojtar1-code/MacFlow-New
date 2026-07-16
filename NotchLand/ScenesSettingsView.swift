//
//  ScenesSettingsView.swift
//  NotchLand
//
//  Phase 1 library and runtime controls for NotchLand Scenes.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScenesSettingsView: View {
    @EnvironmentObject private var controller: WallpaperSceneController
    @State private var presentsImporter = false
    @State private var isImporting = false
    @State private var presentsNewCollection = false
    @State private var newCollectionName = ""
    @State private var editingScene: WallpaperScene?

    private enum Metrics {
        static let sectionSpacing: CGFloat = 20
        static let cardRadius: CGFloat = 16
        static let previewSize = CGSize(width: 92, height: 62)
        static let collectionCardWidth: CGFloat = 158
        static let collectionCardHeight: CGFloat = 76
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                hero
                runtimeCard
                performanceCard
                automationCard
                collectionsSection
                librarySection
            }
            .padding(24)
        }
        .background(Color.clear)
        .fileImporter(
            isPresented: $presentsImporter,
            allowedContentTypes: [.image, .movie, .notchLandScene],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        .alert(
            "Scenes",
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
                _ = withAnimation(NotchMotion.contentOpen) {
                    controller.library.createCollection(named: newCollectionName)
                }
                newCollectionName = ""
            }
            .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Group scenes for moods, rooms, or projects.")
        }
        .sheet(item: $editingScene) { scene in
            SceneInspectorView(
                scene: scene,
                previewURL: controller.library.previewURL(for: scene)
            )
            .environmentObject(controller)
        }
    }

    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.indigo.opacity(0.9), .blue.opacity(0.55), .black.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text("MacFlow Wallpapers")
                    .font(.title2.weight(.semibold))
                Text("Living desktops, built natively for your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                presentsImporter = true
            } label: {
                Label("Import Scene", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImporting)
        }
    }

    private var runtimeCard: some View {
        HStack(spacing: 14) {
            statusGlyph

            VStack(alignment: .leading, spacing: 3) {
                Text(controller.activeScene?.title ?? "No active scene")
                    .font(.headline)
                    .lineLimit(1)
                Text(runtimeDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if controller.activeScene != nil {
                Button {
                    NotchHaptics.perform(.navigation)
                    withAnimation(NotchMotion.selection) {
                        controller.togglePaused()
                    }
                } label: {
                    Label(
                        controller.isPaused ? "Resume" : "Pause",
                        systemImage: controller.isPaused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(.bordered)

                Button("Stop", role: .destructive) {
                withAnimation(NotchMotion.dismiss) {
                        controller.deactivate()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var statusGlyph: some View {
        ZStack {
            Circle()
                .fill(controller.isRunning ? Color.green.opacity(0.16) : Color.secondary.opacity(0.12))
            Image(systemName: controller.isRunning ? "display.and.arrow.down" : "display")
                .foregroundStyle(controller.isRunning ? .green : .secondary)
        }
        .frame(width: 38, height: 38)
    }

    private var runtimeDetail: String {
        guard let scene = controller.activeScene else {
            return "Import an image or looping video to begin."
        }
        if controller.isPaused { return "Paused · \(scene.kind.displayName)" }
        if scene.kind == .video, let suspensionDetail = controller.suspensionDetail {
            return suspensionDetail
        }
        return "Live on \(NSScreen.screens.count) display\(NSScreen.screens.count == 1 ? "" : "s")"
    }

    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Performance", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.headline)
                Spacer()
                Text("Effective: \(controller.performance.effectiveProfile.title)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Picker(
                "Performance",
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
            .pickerStyle(.segmented)

            Text(controller.performance.selectedProfile.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private var automationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.14))
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.indigo)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Scenes")
                        .font(.headline)
                    Text(controller.automationStatusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(
                    "Smart Scenes",
                    isOn: Binding(
                        get: { controller.automationConfiguration.isEnabled },
                        set: { isEnabled in
                            controller.updateAutomationConfiguration { $0.isEnabled = isEnabled }
                        }
                    )
                )
                .labelsHidden()
            }

            if controller.automationConfiguration.isEnabled {
                Divider()

                HStack {
                    Toggle(
                        "Rotate favorites",
                        isOn: Binding(
                            get: { controller.automationConfiguration.rotatesFavorites },
                            set: { rotatesFavorites in
                                controller.updateAutomationConfiguration {
                                    $0.rotatesFavorites = rotatesFavorites
                                }
                            }
                        )
                    )

                    Spacer()

                    Picker(
                        "Every",
                        selection: Binding(
                            get: { controller.automationConfiguration.rotationIntervalMinutes },
                            set: { interval in
                                controller.updateAutomationConfiguration {
                                    $0.rotationIntervalMinutes = interval
                                }
                            }
                        )
                    ) {
                        ForEach(WallpaperAutomationConfiguration.supportedRotationIntervals, id: \.self) { minutes in
                            Text("Every \(minutes) min").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 128)
                    .disabled(!controller.automationConfiguration.rotatesFavorites)
                }

                sceneRuleRow(
                    title: "When Focus starts",
                    systemImage: "moon.fill",
                    selection: Binding(
                        get: { controller.automationConfiguration.focusSceneID },
                        set: { sceneID in
                            controller.updateAutomationConfiguration { $0.focusSceneID = sceneID }
                        }
                    )
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 10
                ) {
                    ForEach(WallpaperDayPeriod.allCases) { period in
                        dayPeriodRule(period)
                    }
                }

                if controller.isManualOverrideActive {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.orange)
                        Text("Your manual scene stays in control for two hours.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Resume now") { controller.resumeAutomationNow() }
                            .buttonStyle(.link)
                    }
                }
            }
        }
        .padding(16)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        )
        .animation(NotchMotion.contentOpen, value: controller.automationConfiguration.isEnabled)
    }

    private func sceneRuleRow(
        title: String,
        systemImage: String,
        selection: Binding<UUID?>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout)
            Spacer()
            scenePicker(selection: selection)
                .frame(width: 190)
        }
    }

    private func dayPeriodRule(_ period: WallpaperDayPeriod) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(period.title, systemImage: period.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            scenePicker(
                selection: Binding(
                    get: { controller.automationConfiguration.sceneID(for: period) },
                    set: { sceneID in
                        controller.updateAutomationConfiguration {
                            $0.setSceneID(sceneID, for: period)
                        }
                    }
                )
            )
        }
        .padding(11)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func scenePicker(selection: Binding<UUID?>) -> some View {
        Picker("Scene", selection: selection) {
            Text("No rule").tag(UUID?.none)
            ForEach(controller.library.scenes) { scene in
                Text(scene.title).tag(Optional(scene.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Collections")
                    .font(.headline)
                Spacer()
                Button {
                    presentsNewCollection = true
                } label: {
                    Label("New Collection", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(controller.library.collections) { collection in
                        collectionCard(collection)
                    }
                }
            }
        }
    }

    private func collectionCard(_ collection: WallpaperSceneCollection) -> some View {
        let count = controller.library.scenes(in: collection).count
        return HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        collection.kind == .favorites
                            ? Color.yellow.opacity(0.16)
                            : Color.accentColor.opacity(0.12)
                    )
                Image(systemName: collection.kind == .favorites ? "star.fill" : "rectangle.stack.fill")
                    .foregroundStyle(collection.kind == .favorites ? .yellow : Color.accentColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(collection.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text("\(count) scene\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if collection.kind == .custom {
                Menu {
                    Button("Delete Collection", role: .destructive) {
                        withAnimation(NotchMotion.dismiss) {
                            controller.library.remove(collection)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(11)
        .frame(width: Metrics.collectionCardWidth, height: Metrics.collectionCardHeight)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Library")
                    .font(.headline)
                Text("\(controller.library.scenes.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
                Spacer()
            }

            if isImporting {
                importingPlaceholder
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if controller.library.scenes.isEmpty, !isImporting {
                emptyLibrary
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(controller.library.scenes) { scene in
                        SceneLibraryRow(
                            scene: scene,
                            assetURL: controller.library.previewURL(for: scene),
                            isActive: controller.activeSceneID == scene.id,
                            isFavorite: controller.library.isFavorite(scene),
                            isExporting: controller.exportingSceneID == scene.id,
                            collections: controller.library.collections.filter { $0.kind == .custom },
                            isInCollection: { controller.library.contains(scene, in: $0) },
                            apply: { controller.apply(scene) },
                            toggleFavorite: { controller.library.toggleFavorite(scene) },
                            toggleCollection: { controller.library.toggle(scene, in: $0) },
                            edit: { editingScene = scene },
                            export: { exportScene(scene) },
                            remove: { controller.remove(scene) }
                        )
                    }
                }
            }
        }
        .animation(NotchMotion.contentOpen, value: controller.library.scenes)
        .animation(NotchMotion.contentOpen, value: isImporting)
    }

    private var importingPlaceholder: some View {
        HStack(spacing: 14) {
            ShimmerBlock(cornerRadius: 12)
                .frame(width: Metrics.previewSize.width, height: Metrics.previewSize.height)
            VStack(alignment: .leading, spacing: 8) {
                ShimmerBlock(cornerRadius: 4).frame(width: 150, height: 12)
                ShimmerBlock(cornerRadius: 4).frame(width: 95, height: 9)
            }
            Spacer()
        }
        .padding(10)
    }

    private var emptyLibrary: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.secondary)
            Text("Build your first scene")
                .font(.headline)
            Text("Images stay perfectly still. Videos loop silently and adapt to your Mac's power state.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Choose a File") { presentsImporter = true }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true
            Task {
                await controller.importAndApply(from: url)
                withAnimation(NotchMotion.contentOpen) { isImporting = false }
            }
        case .failure(let error):
            controller.errorMessage = error.localizedDescription
        }
    }

    private func exportScene(_ scene: WallpaperScene) {
        let panel = NSSavePanel()
        panel.title = "Export NotchLand Scene"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.notchLandScene]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(sanitizedPackageName(scene.title)).notchscene"
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        Task {
            await controller.export(scene, to: destinationURL)
        }
    }

    private func sanitizedPackageName(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        let components = title.components(separatedBy: invalidCharacters)
        let sanitized = components.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "NotchLand Scene" : sanitized
    }
}

private struct SceneLibraryRow: View {
    let scene: WallpaperScene
    let assetURL: URL
    let isActive: Bool
    let isFavorite: Bool
    let isExporting: Bool
    let collections: [WallpaperSceneCollection]
    let isInCollection: (WallpaperSceneCollection) -> Bool
    let apply: () -> Void
    let toggleFavorite: () -> Void
    let toggleCollection: (WallpaperSceneCollection) -> Void
    let edit: () -> Void
    let export: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            SceneThumbnail(scene: scene, assetURL: assetURL)
                .frame(width: 92, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(scene.title)
                        .font(.headline)
                        .lineLimit(1)
                    if isActive {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.13), in: Capsule())
                    }
                }
                Label(scene.kind.displayName, systemImage: scene.kind.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isExporting {
                ShimmerBlock(cornerRadius: 4)
                    .frame(width: 52, height: 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .accessibilityLabel("Exporting scene")
            }

            Button {
                NotchHaptics.perform(.navigation)
                edit()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Edit Scene Appearance")

            Button {
                NotchHaptics.perform(.navigation)
                toggleFavorite()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")

            if !isActive {
                Button("Apply") {
                    NotchHaptics.perform(.confirmation)
                    apply()
                }
                .buttonStyle(.borderedProminent)
            }

            Menu {
                Button(action: export) {
                    Label("Export Scene…", systemImage: "square.and.arrow.up")
                }
                if !collections.isEmpty {
                    Section("Collections") {
                        ForEach(collections) { collection in
                            Button {
                                toggleCollection(collection)
                            } label: {
                                Label(
                                    collection.title,
                                    systemImage: isInCollection(collection) ? "checkmark.circle.fill" : "circle"
                                )
                            }
                        }
                    }
                    Divider()
                }
                Button("Remove", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(isExporting)
        }
        .padding(10)
        .background(
            isActive ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(isActive ? Color.accentColor.opacity(0.28) : .white.opacity(0.05), lineWidth: 1)
        }
        .animation(NotchMotion.contentOpen, value: isExporting)
    }
}

private struct SceneInspectorView: View {
    private enum Metrics {
        static let width: CGFloat = 620
        static let previewHeight: CGFloat = 270
        static let contentSpacing: CGFloat = 18
        static let previewRadius: CGFloat = 16
        static let horizontalPadding: CGFloat = 24
        static let verticalPadding: CGFloat = 22
    }

    let scene: WallpaperScene
    let previewURL: URL

    @EnvironmentObject private var controller: WallpaperSceneController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var configuration: WallpaperSceneRenderingConfiguration

    init(scene: WallpaperScene, previewURL: URL) {
        self.scene = scene
        self.previewURL = previewURL
        _configuration = State(initialValue: scene.rendering)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            header
            preview
            scalingControl

            if scene.kind == .video {
                playbackControl
            }

            dimmingControl

            HStack {
                Button("Reset") {
                    NotchHaptics.perform(.navigation)
                    withAnimation(NotchMotion.selection) {
                        configuration = .default
                    }
                }
                .buttonStyle(.bordered)
                .disabled(configuration == .default)

                Spacer()

                Text("Changes are saved automatically")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
        .frame(width: Metrics.width)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: configuration) { _, updatedConfiguration in
            controller.updateRendering(
                for: scene.id,
                configuration: updatedConfiguration
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.indigo.opacity(0.14))
                Image(systemName: "paintbrush.pointed.fill")
                    .foregroundStyle(.indigo)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(scene.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text("Scene Engine Profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(scene.kind.displayName, systemImage: scene.kind.systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.secondary.opacity(0.1), in: Capsule())
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let image = NSImage(contentsOf: previewURL) {
                    previewImage(image, size: proxy.size)
                } else {
                    Image(systemName: scene.kind.systemImage)
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Color.black.opacity(configuration.dimming)

                VStack {
                    Spacer()
                    HStack {
                        Label(
                            configuration.scalingMode.title,
                            systemImage: configuration.scalingMode.systemImage
                        )
                        Spacer()
                        if scene.kind == .video {
                            Text("\(configuration.playbackRate.formatted(.number.precision(.fractionLength(0...2))))×")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.64)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.previewRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.previewRadius, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.previewRadius, style: .continuous))
        }
        .frame(height: Metrics.previewHeight)
        .animation(reduceMotion ? nil : NotchMotion.selection, value: configuration)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wallpaper preview, \(configuration.scalingMode.title)")
    }

    @ViewBuilder
    private func previewImage(_ image: NSImage, size: CGSize) -> some View {
        switch configuration.scalingMode {
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

    private var scalingControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scaling")
                .font(.headline)
            Picker("Scaling", selection: $configuration.scalingMode) {
                ForEach(WallpaperSceneRenderingConfiguration.ScalingMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var playbackControl: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Playback Speed")
                    .font(.headline)
                Text("Video stays silent and loops continuously.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Playback Speed", selection: $configuration.playbackRate) {
                ForEach(WallpaperSceneRenderingConfiguration.playbackRateOptions, id: \.self) { rate in
                    Text("\(rate.formatted(.number.precision(.fractionLength(0...2))))×").tag(rate)
                }
            }
            .labelsHidden()
            .frame(width: 112)
        }
    }

    private var dimmingControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Dimming")
                    .font(.headline)
                Spacer()
                Text(configuration.dimming, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.secondary)
                Slider(
                    value: $configuration.dimming,
                    in: WallpaperSceneRenderingConfiguration.dimmingRange
                )
                Image(systemName: "moon.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SceneThumbnail: View {
    let scene: WallpaperScene
    let assetURL: URL

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
            if let image = NSImage(contentsOf: assetURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                if scene.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.5), in: Circle())
                }
            } else {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .clipped()
        .accessibilityLabel("\(scene.title), \(scene.kind.displayName) scene")
    }
}

private struct ShimmerBlock: View {
    let cornerRadius: CGFloat
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.secondary.opacity(0.12))
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.14), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 180)
                .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .onAppear {
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
