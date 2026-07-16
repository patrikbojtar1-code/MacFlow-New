//
//  AudioDeviceActivitySource.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Posts a chip when the default audio output device changes to a different
//  physical device (AirPods connect moment). Ignores the built-in speakers
//  switchback so only external connects get the celebration.
//

import CoreAudio
import Foundation

@MainActor
final class AudioDeviceActivitySource {
    private let activities: LiveActivityController
    private var lastDeviceID: AudioDeviceID = 0
    private var lastExternalDevice: (name: String, model: AudioAccessoryModel)?
    private var transitionTask: Task<Void, Never>?
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init(activities: LiveActivityController) {
        self.activities = activities
    }

    func start() {
        guard listenerBlock == nil else { return }
        lastDeviceID = currentDefaultDevice()
        let initialName = deviceName(lastDeviceID)
        if !isBuiltInOutput(initialName) {
            lastExternalDevice = (initialName, AudioAccessoryModel.detect(from: initialName))
        }
        let handler: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.defaultDeviceChanged() }
            }
        }
        listenerBlock = handler
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, handler
        )
    }

    func stop() {
        transitionTask?.cancel()
        transitionTask = nil
        if let block = listenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, block
            )
            listenerBlock = nil
        }
    }

    func debugPostSample() {
        postConnectChip(name: "Rudra's AirPods Pro")
    }

    private func defaultDeviceChanged() {
        let device = currentDefaultDevice()
        guard device != lastDeviceID, device != 0 else { return }
        lastDeviceID = device
        let name = deviceName(device)
        if isBuiltInOutput(name) {
            if let lastExternalDevice {
                postDisconnectSequence(device: lastExternalDevice, builtInName: name)
                self.lastExternalDevice = nil
            }
            return
        }

        let model = AudioAccessoryModel.detect(from: name)
        lastExternalDevice = (name, model)
        postConnectSequence(name: name, model: model)
    }

    private func postConnectChip(name: String) {
        let model = AudioAccessoryModel.detect(from: name)
        postConnectSequence(name: name, model: model)
    }

    private func postConnectSequence(name: String, model: AudioAccessoryModel) {
        transitionTask?.cancel()
        let activityID = UUID()
        activities.post(LiveActivity(
            id: activityID,
            kind: .audioDevice(
                name: name,
                model: model,
                batteryPercent: nil,
                phase: .connecting
            ),
            title: name,
            detail: AudioAccessoryConnectionPhase.connecting.displayName,
            progress: nil
        ))
        transitionTask = Task { @MainActor [weak activities] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            activities?.post(LiveActivity(
                id: activityID,
                kind: .audioDevice(
                    name: name,
                    model: model,
                    batteryPercent: nil,
                    phase: .connected
                ),
                title: name,
                detail: AudioAccessoryConnectionPhase.connected.displayName,
                progress: nil
            ))
            try? await Task.sleep(for: .seconds(3.35))
            guard !Task.isCancelled else { return }
            activities?.end(activityID)
        }
    }

    private func postDisconnectSequence(
        device: (name: String, model: AudioAccessoryModel),
        builtInName: String
    ) {
        transitionTask?.cancel()
        let activityID = UUID()
        activities.post(LiveActivity(
            id: activityID,
            kind: .audioDevice(
                name: device.name,
                model: device.model,
                batteryPercent: nil,
                phase: .disconnecting
            ),
            title: device.name,
            detail: AudioAccessoryConnectionPhase.disconnecting.displayName,
            progress: nil
        ))
        transitionTask = Task { @MainActor [weak activities] in
            try? await Task.sleep(for: .milliseconds(520))
            guard !Task.isCancelled else { return }
            activities?.post(LiveActivity(
                id: activityID,
                kind: .audioDevice(
                    name: device.name,
                    model: device.model,
                    batteryPercent: nil,
                    phase: .disconnected
                ),
                title: device.name,
                detail: AudioAccessoryConnectionPhase.disconnected.displayName,
                progress: nil
            ))
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }

            // Make the new output destination explicit. The CoreAudio name is
            // usually "MacBook Air Speakers"; the product identity requested
            // by this app is shown with Apple's MacBook glyph.
            let builtInDisplayName = builtInName.localizedCaseInsensitiveContains("macbook")
                ? "MacBook Air M4"
                : builtInName
            activities?.post(LiveActivity(
                id: activityID,
                kind: .audioDevice(
                    name: builtInDisplayName,
                    model: .macBookAirM4,
                    batteryPercent: nil,
                    phase: .connected
                ),
                title: builtInDisplayName,
                detail: "Built-in Speakers",
                progress: nil
            ))
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            activities?.end(activityID)
        }
    }

    private func isBuiltInOutput(_ name: String) -> Bool {
        let normalized = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).lowercased()
        return normalized.contains("speaker")
            || normalized.contains("macbook")
            || normalized.contains("built-in")
            || normalized.contains("vestav")
    }

    private func currentDefaultDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return deviceID
    }

    private func deviceName(_ id: AudioDeviceID) -> String {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &size, ptr)
        }
        return status == noErr ? (name as String) : "Audio Device"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
