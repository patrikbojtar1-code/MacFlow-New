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

import Combine
import CoreAudio
import Foundation
import IOKit

struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    enum Transport: String, Equatable, Sendable {
        case builtIn
        case bluetooth
        case airPlay
        case usb
        case display
        case virtual
        case other
    }

    let id: AudioDeviceID
    let uid: String
    let name: String
    let model: AudioAccessoryModel
    let transport: Transport
    let batteryPercent: Int?
    let isDefault: Bool

    var detail: String {
        if let batteryPercent { return "\(batteryPercent)% battery" }
        return switch transport {
        case .builtIn: "Built-in Output"
        case .bluetooth: "Bluetooth Audio"
        case .airPlay: "AirPlay"
        case .usb: "USB Audio"
        case .display: "Display Audio"
        case .virtual: "Virtual Audio"
        case .other: "Audio Output"
        }
    }
}

enum AudioOutputSelectionState: Equatable {
    case idle
    case switching(AudioDeviceID)
    case failed(String)

    func isSwitching(_ deviceID: AudioDeviceID) -> Bool {
        if case let .switching(activeDeviceID) = self {
            return activeDeviceID == deviceID
        }
        return false
    }
}

@MainActor
protocol AudioOutputDeviceProviding {
    func availableOutputs() -> [AudioOutputDevice]
    func defaultOutputDeviceID() -> AudioDeviceID
    func selectOutput(_ deviceID: AudioDeviceID) throws
}

enum AudioOutputDeviceError: LocalizedError {
    case unavailable
    case selectionFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unavailable: "This audio output is no longer available."
        case let .selectionFailed(status): "macOS could not switch the output (\(status))."
        }
    }
}

/// Public CoreAudio only: discovery is event-driven and switching writes the
/// system default output property directly. Battery lookup is a best-effort
/// read of Apple's HID registry and never starts a polling process.
@MainActor
final class CoreAudioOutputDeviceProvider: AudioOutputDeviceProviding {
    private let batteryReader: AudioAccessoryBatteryReading

    init() {
        batteryReader = IORegistryAudioAccessoryBatteryReader()
    }

    init(batteryReader: AudioAccessoryBatteryReading) {
        self.batteryReader = batteryReader
    }

    func availableOutputs() -> [AudioOutputDevice] {
        let defaultID = defaultOutputDeviceID()
        return allDeviceIDs()
            .filter(hasOutputStreams)
            .compactMap { deviceID in
                guard let name = stringProperty(
                    kAudioObjectPropertyName,
                    deviceID: deviceID
                ) else { return nil }
                let model = AudioAccessoryModel.detect(from: name)
                return AudioOutputDevice(
                    id: deviceID,
                    uid: stringProperty(kAudioDevicePropertyDeviceUID, deviceID: deviceID)
                        ?? String(deviceID),
                    name: name,
                    model: model,
                    transport: transport(for: deviceID),
                    batteryPercent: batteryReader.batteryPercent(for: name, model: model),
                    isDefault: deviceID == defaultID
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                if lhs.transport == .builtIn, rhs.transport != .builtIn { return true }
                if rhs.transport == .builtIn, lhs.transport != .builtIn { return false }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func defaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultOutputAddress
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else { return AudioDeviceID(kAudioObjectUnknown) }
        return deviceID
    }

    func selectOutput(_ deviceID: AudioDeviceID) throws {
        guard availableOutputs().contains(where: { $0.id == deviceID }) else {
            throw AudioOutputDeviceError.unavailable
        }

        var selectedID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var outputAddress = defaultOutputAddress
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &outputAddress,
            0,
            nil,
            size,
            &selectedID
        )
        guard status == noErr else { throw AudioOutputDeviceError.selectionFailed(status) }

        // Keep alert/system sounds on the chosen output when macOS exposes the
        // secondary property. Failure here must not undo a successful media route.
        var systemAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(AudioObjectID(kAudioObjectSystemObject), &systemAddress) {
            _ = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &systemAddress,
                0,
                nil,
                size,
                &selectedID
            )
        }
    }

    private var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }
        var devices = Array(
            repeating: AudioDeviceID(kAudioObjectUnknown),
            count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == noErr else { return [] }
        return devices
    }

    private func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private func stringProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value as String
    }

    private func transport(for deviceID: AudioDeviceID) -> AudioOutputDevice.Transport {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return .other
        }
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: return .display
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return .virtual
        default: return .other
        }
    }
}

@MainActor
protocol AudioAccessoryBatteryReading {
    func batteryPercent(for deviceName: String, model: AudioAccessoryModel) -> Int?
}

@MainActor
struct IORegistryAudioAccessoryBatteryReader: AudioAccessoryBatteryReading {
    func batteryPercent(for deviceName: String, model: AudioAccessoryModel) -> Int? {
        guard model != .macBookAirM4, model != .generic else { return nil }
        let candidates = registryCandidates(className: "AppleDeviceManagementHIDEventService")
            + registryCandidates(className: "AppleHSBluetoothDevice")
        let normalizedTarget = normalize(deviceName)
        let matching = candidates.first { candidate in
            let name = registryName(in: candidate).map(normalize) ?? ""
            return name == normalizedTarget
                || (!name.isEmpty && (normalizedTarget.contains(name) || name.contains(normalizedTarget)))
                || AudioAccessoryModel.detect(from: name) == model
        }
        return matching.flatMap(batteryValue)
    }

    private func registryCandidates(className: String) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(className),
            &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var results: [[String: Any]] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(
                service,
                &properties,
                kCFAllocatorDefault,
                0
            ) == KERN_SUCCESS,
            let dictionary = properties?.takeRetainedValue() as? [String: Any] else { continue }
            results.append(dictionary)
        }
        return results
    }

    private func registryName(in properties: [String: Any]) -> String? {
        for key in ["Product", "ProductName", "DeviceName", "BTName"] {
            if let name = properties[key] as? String, !name.isEmpty { return name }
        }
        return nil
    }

    private func batteryValue(in properties: [String: Any]) -> Int? {
        for key in ["BatteryPercent", "BatteryPercentSingle", "BatteryLevel", "Battery Level"] {
            if let number = properties[key] as? NSNumber {
                return min(100, max(0, number.intValue))
            }
        }
        return nil
    }

    private func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).lowercased()
    }
}

@MainActor
final class AudioDeviceActivitySource: ObservableObject {
    @Published private(set) var outputs: [AudioOutputDevice] = []
    @Published private(set) var selectionState: AudioOutputSelectionState = .idle

    private let activities: LiveActivityController
    private let provider: AudioOutputDeviceProviding
    private var lastDeviceID: AudioDeviceID = 0
    private var lastExternalDevice: (name: String, model: AudioAccessoryModel)?
    private var transitionTask: Task<Void, Never>?
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var devicesListenerBlock: AudioObjectPropertyListenerBlock?
    private var selectionStateResetTask: Task<Void, Never>?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init(activities: LiveActivityController) {
        self.activities = activities
        provider = CoreAudioOutputDeviceProvider()
    }

    init(activities: LiveActivityController, provider: AudioOutputDeviceProviding) {
        self.activities = activities
        self.provider = provider
    }

    func start() {
        guard listenerBlock == nil else { return }
        refreshOutputs()
        lastDeviceID = provider.defaultOutputDeviceID()
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

        let devicesHandler: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.availableDevicesChanged() }
            }
        }
        devicesListenerBlock = devicesHandler
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            .main,
            devicesHandler
        )
    }

    func stop() {
        transitionTask?.cancel()
        transitionTask = nil
        selectionStateResetTask?.cancel()
        selectionStateResetTask = nil
        if let block = listenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, block
            )
            listenerBlock = nil
        }
        if let block = devicesListenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &devicesAddress,
                .main,
                block
            )
            devicesListenerBlock = nil
        }
    }

    var currentOutput: AudioOutputDevice? {
        outputs.first(where: \.isDefault)
    }

    func refreshOutputs() {
        outputs = provider.availableOutputs()
    }

    @discardableResult
    func selectOutput(_ deviceID: AudioDeviceID) async -> Bool {
        guard !selectionState.isSwitching(deviceID) else { return false }
        selectionStateResetTask?.cancel()
        selectionState = .switching(deviceID)
        await Task.yield()

        do {
            try provider.selectOutput(deviceID)
            refreshOutputs()
            selectionState = .idle
            return true
        } catch {
            selectionState = .failed(error.localizedDescription)
            selectionStateResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
                self?.selectionState = .idle
                self?.selectionStateResetTask = nil
            }
            return false
        }
    }

    func debugPostSample() {
        postConnectChip(name: "Rudra's AirPods Pro")
    }

    private func defaultDeviceChanged() {
        refreshOutputs()
        let device = provider.defaultOutputDeviceID()
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

    private func availableDevicesChanged() {
        refreshOutputs()
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
