//
//  WallpaperRuntimeVisibility.swift
//  NotchLand
//
//  Privacy-preserving fullscreen detection based on public WindowServer metadata.
//

import AppKit
import CoreGraphics
import Foundation

nonisolated struct WallpaperWindowSnapshot: Equatable, Sendable {
    let ownerPID: pid_t
    let layer: Int
    let bounds: CGRect
    let alpha: Double
}

nonisolated enum WallpaperFullscreenDetector {
    private static let dimensionTolerance: CGFloat = 3

    static func isFullscreen(
        frontmostPID: pid_t?,
        windows: [WallpaperWindowSnapshot],
        displayFrames: [CGRect]
    ) -> Bool {
        guard let frontmostPID else { return false }
        return windows.contains { window in
            guard window.ownerPID == frontmostPID,
                  window.layer == 0,
                  window.alpha > 0.01 else { return false }

            return displayFrames.contains { display in
                abs(window.bounds.width - display.width) <= dimensionTolerance
                    && abs(window.bounds.height - display.height) <= dimensionTolerance
            }
        }
    }

    static func currentWindowSnapshots() -> [WallpaperWindowSnapshot] {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return rawWindows.compactMap { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  let alpha = info[kCGWindowAlpha as String] as? NSNumber,
                  let rawBounds = info[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as! CFDictionary) else {
                return nil
            }
            return WallpaperWindowSnapshot(
                ownerPID: pid_t(ownerPID.int32Value),
                layer: layer.intValue,
                bounds: bounds,
                alpha: alpha.doubleValue
            )
        }
    }
}
