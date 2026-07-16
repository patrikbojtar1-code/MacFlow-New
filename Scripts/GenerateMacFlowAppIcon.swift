#!/usr/bin/env swift

import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "MacFlow-1024.png")
let canvasSize = CGSize(width: 1024, height: 1024)
let image = NSImage(size: canvasSize)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create drawing context")
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let tileRect = CGRect(x: 88, y: 76, width: 848, height: 848)
let tilePath = CGPath(
    roundedRect: tileRect,
    cornerWidth: 210,
    cornerHeight: 210,
    transform: nil
)
context.saveGState()
context.addPath(tilePath)
context.clip()
let backgroundColors = [
    NSColor(red: 0.055, green: 0.078, blue: 0.157, alpha: 1).cgColor,
    NSColor(red: 0.129, green: 0.090, blue: 0.278, alpha: 1).cgColor,
] as CFArray
let colorSpace = CGColorSpaceCreateDeviceRGB()
let backgroundGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: backgroundColors,
    locations: [0, 1]
)!
context.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: tileRect.minX, y: tileRect.maxY),
    end: CGPoint(x: tileRect.maxX, y: tileRect.minY),
    options: []
)
context.restoreGState()

context.addPath(tilePath)
context.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
context.setLineWidth(2)
context.strokePath()

let ribbon = CGMutablePath()
ribbon.move(to: CGPoint(x: 260, y: 400))
ribbon.addCurve(
    to: CGPoint(x: 458, y: 594),
    control1: CGPoint(x: 260, y: 648),
    control2: CGPoint(x: 386, y: 692)
)
ribbon.addCurve(
    to: CGPoint(x: 512, y: 512),
    control1: CGPoint(x: 483, y: 560),
    control2: CGPoint(x: 496, y: 512)
)
ribbon.addCurve(
    to: CGPoint(x: 566, y: 594),
    control1: CGPoint(x: 528, y: 512),
    control2: CGPoint(x: 541, y: 560)
)
ribbon.addCurve(
    to: CGPoint(x: 764, y: 400),
    control1: CGPoint(x: 638, y: 692),
    control2: CGPoint(x: 764, y: 648)
)

context.saveGState()
context.addPath(ribbon)
context.setLineWidth(94)
context.setLineCap(.round)
context.setLineJoin(.round)
context.replacePathWithStrokedPath()
context.clip()
let ribbonColors = [
    NSColor(red: 0.29, green: 0.91, blue: 1, alpha: 1).cgColor,
    NSColor(red: 0.48, green: 0.55, blue: 1, alpha: 1).cgColor,
    NSColor(red: 0.76, green: 0.39, blue: 1, alpha: 1).cgColor,
] as CFArray
let ribbonGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: ribbonColors,
    locations: [0, 0.5, 1]
)!
context.drawLinearGradient(
    ribbonGradient,
    start: CGPoint(x: 240, y: 512),
    end: CGPoint(x: 784, y: 512),
    options: []
)
context.restoreGState()

context.setFillColor(NSColor.white.cgColor)
context.fillEllipse(in: CGRect(x: 489, y: 307, width: 46, height: 46))
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode app icon")
}

try png.write(to: outputURL, options: .atomic)
print(outputURL.path)
