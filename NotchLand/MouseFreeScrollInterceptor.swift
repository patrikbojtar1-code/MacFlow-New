//
//  MouseFreeScrollInterceptor.swift
//  MacFlow
//
//  Accessibility-gated external mouse wheel event interceptor.
//

import AppKit
import CoreGraphics
import Foundation
import os
import QuartzCore

@MainActor
final class MouseFreeScrollInterceptor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var displayLink: CADisplayLink?
    private var displayID: CGDirectDisplayID?
    private var previousFrameTimestamp: CFTimeInterval?
    private let engine = MouseFreeScrollEngine()

    var reverseScroll = true
    var scrollSpeed = 1.15
    var smoothFeel: Double = 0.55
    var acceleration: Double = 0.35
    var optionBypassEnabled = true
    var disabledBundleIDs: Set<String> = []
    private(set) var isRunning = false

    private let generatedEventMarker: Int64 = 0x4D_46_4C_4F_57
    private let logger = Logger(subsystem: "com.rudrashah.MacFlow", category: "MouseFree")

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<MouseFreeScrollInterceptor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return MainActor.assumeIsolated {
                interceptor.handle(type: type, event: event)
            }
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap,
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            self.eventTap = nil
            logger.error("Unable to create the scroll event tap")
            return false
        }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        engine.reset()
        configureDisplayLink(for: screen(at: NSEvent.mouseLocation))
        isRunning = true
        return true
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        displayLink?.invalidate()
        displayLink = nil
        displayID = nil
        previousFrameTimestamp = nil
        engine.reset()
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        if event.getIntegerValueField(.eventSourceUserData) == generatedEventMarker {
            return Unmanaged.passUnretained(event)
        }
        if optionBypassEnabled && event.flags.contains(.maskAlternate) {
            pauseMotion()
            return Unmanaged.passUnretained(event)
        }
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           disabledBundleIDs.contains(bundleID) {
            pauseMotion()
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else {
            pauseMotion()
            return Unmanaged.passUnretained(event)
        }

        var y = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        var x = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        if x == 0 && y == 0 {
            y = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            x = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        }
        guard x != 0 || y != 0 else { return nil }

        if abs(y) > abs(x) * 2.2 { x = 0 }
        if abs(x) > abs(y) * 2.2 { y = 0 }

        let direction = reverseScroll ? -1.0 : 1.0
        engine.addInput(
            x: x * direction,
            y: y * direction,
            timestamp: event.timestamp.mouseFreeSeconds,
            configuration: configuration
        )
        updateDisplayLinkIfNeeded(at: event.location)
        previousFrameTimestamp = nil
        displayLink?.isPaused = false
        return nil
    }

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        let deltaTime = previousFrameTimestamp.map { link.timestamp - $0 }
            ?? (link.duration > 0 ? link.duration : 1.0 / 60.0)
        previousFrameTimestamp = link.timestamp

        if let frame = engine.update(deltaTime: deltaTime, configuration: configuration) {
            postSmoothScroll(x: frame.x, y: frame.y)
        }
        if !engine.isAnimating {
            link.isPaused = true
            previousFrameTimestamp = nil
        }
    }

    private var configuration: MouseScrollConfiguration {
        MouseScrollConfiguration(
            speed: min(max(scrollSpeed, 0.5), 3),
            smoothness: min(max(smoothFeel, 0), 1),
            acceleration: min(max(acceleration, 0), 1)
        )
    }

    private func updateDisplayLinkIfNeeded(at point: CGPoint) {
        guard let target = screen(at: point), screenDisplayID(target) != displayID else { return }
        configureDisplayLink(for: target)
    }

    private func configureDisplayLink(for requestedScreen: NSScreen?) {
        guard let screen = requestedScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let newDisplayID = screenDisplayID(screen)
        guard displayLink == nil || displayID != newDisplayID else { return }
        displayLink?.invalidate()
        let link = screen.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        link.add(to: .main, forMode: .common)
        link.isPaused = true
        displayLink = link
        displayID = newDisplayID
        previousFrameTimestamp = nil
    }

    private func screen(at point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func screenDisplayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    private func pauseMotion() {
        engine.reset()
        displayLink?.isPaused = true
        previousFrameTimestamp = nil
    }

    private func postSmoothScroll(x: Int32, y: Int32) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(
                  scrollWheelEvent2Source: source,
                  units: .pixel,
                  wheelCount: 2,
                  wheel1: y,
                  wheel2: x,
                  wheel3: 0
              ) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: generatedEventMarker)
        event.post(tap: .cghidEventTap)
    }
}

private extension UInt64 {
    var mouseFreeSeconds: TimeInterval {
        let info = mach_timebase_info_data_t.mouseFreeCurrent
        return TimeInterval(self) * TimeInterval(info.numer) / TimeInterval(info.denom) / 1_000_000_000
    }
}

private extension mach_timebase_info_data_t {
    static let mouseFreeCurrent: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()
}
