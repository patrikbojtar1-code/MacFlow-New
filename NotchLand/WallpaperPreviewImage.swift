//
//  WallpaperPreviewImage.swift
//  MacFlow
//
//  Cancelable, cached wallpaper preview loading that never performs file I/O
//  from a SwiftUI body evaluation.
//

import AppKit
import SwiftUI

private actor WallpaperPreviewDataCache {
    static let shared = WallpaperPreviewDataCache()

    private var values: [URL: Data] = [:]
    private var order: [URL] = []
    private var totalBytes = 0
    private let maximumBytes = 64 * 1_024 * 1_024

    func data(for url: URL) async -> Data? {
        if let cached = values[url] { return cached }

        let loaded = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
        guard let loaded else { return nil }
        values[url] = loaded
        order.removeAll { $0 == url }
        order.append(url)
        totalBytes += loaded.count
        while totalBytes > maximumBytes, let oldest = order.first {
            order.removeFirst()
            if let removed = values.removeValue(forKey: oldest) {
                totalBytes -= removed.count
            }
        }
        return loaded
    }
}

struct WallpaperPreviewImage: View {
    let scene: WallpaperScene
    let url: URL
    var scalingMode: WallpaperSceneRenderingConfiguration.ScalingMode = .fill
    var dimming: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if let image {
                    imageView(image, size: proxy.size)
                        .transition(.opacity)
                } else {
                    Image(systemName: scene.kind.systemImage)
                        .font(.title2.weight(.light))
                        .foregroundStyle(.white.opacity(0.42))
                }

                Color.black.opacity(dimming)
            }
        }
        .clipped()
        .task(id: url) {
            image = nil
            guard let data = await WallpaperPreviewDataCache.shared.data(for: url),
                  !Task.isCancelled,
                  let loadedImage = NSImage(data: data) else { return }
            withAnimation(AppMotion.insertion(reduceMotion: reduceMotion)) {
                image = loadedImage
            }
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
