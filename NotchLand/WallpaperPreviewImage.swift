//
//  WallpaperPreviewImage.swift
//  MacFlow
//
//  Cancelable, cached wallpaper preview loading that never performs file I/O
//  from a SwiftUI body evaluation.
//

import AppKit
import ImageIO
import SwiftUI

private struct DecodedWallpaperPreview: @unchecked Sendable {
    let image: CGImage
    let byteCost: Int
}

private actor WallpaperPreviewImageCache {
    static let shared = WallpaperPreviewImageCache()

    private var values: [URL: DecodedWallpaperPreview] = [:]
    private var order: [URL] = []
    private var totalBytes = 0
    private let maximumBytes = 96 * 1_024 * 1_024

    func image(for url: URL) async -> CGImage? {
        if let cached = values[url] {
            touch(url)
            return cached.image
        }

        let loaded = await Task.detached(priority: .userInitiated) { () -> DecodedWallpaperPreview? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_600,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return DecodedWallpaperPreview(
                image: image,
                byteCost: image.bytesPerRow * image.height
            )
        }.value
        guard let loaded else { return nil }

        values[url] = loaded
        touch(url)
        totalBytes += loaded.byteCost
        while totalBytes > maximumBytes, let oldest = order.first {
            order.removeFirst()
            if let removed = values.removeValue(forKey: oldest) {
                totalBytes -= removed.byteCost
            }
        }
        return loaded.image
    }

    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }
}

struct WallpaperPreviewImage: View {
    let scene: WallpaperScene
    let url: URL
    var scalingMode: WallpaperSceneRenderingConfiguration.ScalingMode = .fill
    var dimming: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: CGImage?

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
            guard let loadedImage = await WallpaperPreviewImageCache.shared.image(for: url),
                  !Task.isCancelled else { return }
            withAnimation(AppMotion.insertion(reduceMotion: reduceMotion)) {
                image = loadedImage
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(scene.title), \(scene.kind.displayName) wallpaper")
    }

    @ViewBuilder
    private func imageView(_ image: CGImage, size: CGSize) -> some View {
        switch scalingMode {
        case .fill:
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        case .fit:
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
        case .stretch:
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: size.width, height: size.height)
        }
    }
}
