import AudioToolbox
import CoreAudio
import Foundation
import HoloCore

enum SystemAudioRouteError: Error, LocalizedError {
    case builtInMicrophoneUnavailable
    case deviceBindingFailed(OSStatus)
    case propertyReadFailed(selector: AudioObjectPropertySelector, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .builtInMicrophoneUnavailable:
            return "The built-in MacBook microphone is unavailable. Holo will not switch to a headset microphone."
        case .deviceBindingFailed(let status):
            return "Holo could not select the built-in microphone (error \(status))."
        case .propertyReadFailed(_, let status):
            return "Core Audio could not inspect the current audio route (error \(status))."
        }
    }
}

enum SystemAudioRouteInspector {
    static func currentRoute(inputDeviceID: AudioDeviceID? = nil) throws -> AudioRouteInfo {
        let input = try inputDeviceID.map { try endpoint(deviceID: $0) } ?? endpoint(forDefaultDevice: kAudioHardwarePropertyDefaultInputDevice)
        let output = try? endpoint(forDefaultDevice: kAudioHardwarePropertyDefaultOutputDevice)
        return AudioRouteInfo(input: input, output: output)
    }

    private static func endpoint(
        forDefaultDevice selector: AudioObjectPropertySelector
    ) throws -> AudioEndpointInfo? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr else {
            throw SystemAudioRouteError.propertyReadFailed(selector: selector, status: status)
        }
        guard deviceID != kAudioObjectUnknown else { return nil }

        return try endpoint(deviceID: deviceID)
    }

    static func builtInMicrophone() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr else {
            throw SystemAudioRouteError.propertyReadFailed(selector: address.mSelector, status: status)
        }
        guard size > 0 else { throw SystemAudioRouteError.builtInMicrophoneUnavailable }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        status = devices.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else {
            throw SystemAudioRouteError.propertyReadFailed(selector: address.mSelector, status: status)
        }
        for device in devices {
            guard (try? transportType(device)) == kAudioDeviceTransportTypeBuiltIn else { continue }
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr,
               streamSize > 0 { return device }
        }
        throw SystemAudioRouteError.builtInMicrophoneUnavailable
    }

    static func bindInput(_ unit: AudioUnit, to deviceID: AudioDeviceID) throws {
        var device = deviceID
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw SystemAudioRouteError.deviceBindingFailed(status) }
        guard try inputDevice(of: unit) == deviceID else {
            throw SystemAudioRouteError.builtInMicrophoneUnavailable
        }
    }

    static func inputDevice(of unit: AudioUnit) throws -> AudioDeviceID {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &device, &size)
        guard status == noErr else { throw SystemAudioRouteError.deviceBindingFailed(status) }
        return device
    }

    private static func endpoint(deviceID: AudioDeviceID) throws -> AudioEndpointInfo {
        let name = (try? deviceName(deviceID)) ?? "Unknown audio device"
        let transport = try transportType(deviceID)
        return AudioEndpointInfo(
            name: name,
            isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn
        )
    }

    private static func deviceName(_ deviceID: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &unmanagedName
        )
        guard status == noErr else {
            throw SystemAudioRouteError.propertyReadFailed(
                selector: kAudioObjectPropertyName,
                status: status
            )
        }
        return (unmanagedName?.takeUnretainedValue() as String?) ?? "Unknown audio device"
    }

    private static func transportType(_ deviceID: AudioDeviceID) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = kAudioDeviceTransportTypeUnknown
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        guard status == noErr else {
            throw SystemAudioRouteError.propertyReadFailed(
                selector: kAudioDevicePropertyTransportType,
                status: status
            )
        }
        return transport
    }
}
