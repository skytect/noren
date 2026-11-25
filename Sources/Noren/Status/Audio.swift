// The output volume and whether a microphone is in use, from CoreAudio, read again whenever a
// property they depend on changes:
//
//   volume      the default output device's virtual main volume and mute, with a listener on each
//               and on which device is the default
//   microphone  an input device running somewhere. A device that also plays (a headset) runs for
//               its output alone, so it counts only while a process records from it
//               (kAudioProcessPropertyIsRunningInput). Not that property alone: the system's
//               speech recognition and virtual microphones record without the microphone running.
import AudioToolbox
import CoreAudio
import NorenCore

final class Audio {
  private let changed: (StatusReadings.Output?, Bool) -> Void
  /// The properties already listened to, so each gets one listener.
  private var listening: Set<Listener> = []

  private struct Listener: Hashable {
    let object: AudioObjectID
    let selector: AudioObjectPropertySelector
    let scope: AudioObjectPropertyScope
  }

  /// Reads the output and the microphones now, and again on every change; `changed` gets the
  /// default output (nil when there is none) and whether a microphone is in use.
  init(changed: @escaping (StatusReadings.Output?, Bool) -> Void) {
    self.changed = changed
    let system = AudioObjectID(kAudioObjectSystemObject)
    listen(system, kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal)
    listen(system, kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal)
    listen(system, kAudioHardwarePropertyProcessObjectList, kAudioObjectPropertyScopeGlobal)
    read()
  }

  private func read() {
    changed(output(), microphoneInUse())
  }

  private func output() -> StatusReadings.Output? {
    guard
      let device: AudioObjectID = value(
        AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal),
      device != kAudioObjectUnknown
    else { return nil }
    listen(
      device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput
    )
    listen(device, kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
    // A device without a volume control (HDMI, some interfaces) shows without a level
    let volume: Float32? = value(
      device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      kAudioObjectPropertyScopeOutput)
    let mute: UInt32? = value(device, kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
    return StatusReadings.Output(
      volume: volume.map { Double(min(1, max(0, $0))) }, muted: (mute ?? 0) != 0)
  }

  private func microphoneInUse() -> Bool {
    for device in list(
      AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices,
      kAudioObjectPropertyScopeGlobal)
    where hasStreams(device, kAudioObjectPropertyScopeInput) {
      listen(device, kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal)
      let running: UInt32? = value(
        device, kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal)
      guard (running ?? 0) != 0 else { continue }
      if !hasStreams(device, kAudioObjectPropertyScopeOutput) || isRecorded(device) {
        return true
      }
    }
    return false
  }

  /// Whether some process records from `device`.
  private func isRecorded(_ device: AudioObjectID) -> Bool {
    for process in list(
      AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList,
      kAudioObjectPropertyScopeGlobal)
    {
      listen(process, kAudioProcessPropertyIsRunningInput, kAudioObjectPropertyScopeGlobal)
      let running: UInt32? = value(
        process, kAudioProcessPropertyIsRunningInput, kAudioObjectPropertyScopeGlobal)
      guard (running ?? 0) != 0 else { continue }
      if list(process, kAudioProcessPropertyDevices, kAudioObjectPropertyScopeInput)
        .contains(device)
      {
        return true
      }
    }
    return false
  }

  private func hasStreams(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
    !list(device, kAudioDevicePropertyStreams, scope).isEmpty
  }

  /// Reads everything again whenever `selector` changes on `object`; once per property.
  private func listen(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope
  ) {
    let listener = Listener(object: object, selector: selector, scope: scope)
    guard !listening.contains(listener) else { return }
    var address = Self.address(selector, scope)
    guard AudioObjectHasProperty(object, &address) else { return }
    let status = AudioObjectAddPropertyListenerBlock(object, &address, .main) {
      [weak self] _, _ in
      MainActor.assumeIsolated { self?.read() }
    }
    if status == noErr { listening.insert(listener) }
  }

  /// The value of a fixed-size property, or nil when `object` does not have it.
  private func value<Value: BitwiseCopyable & ExpressibleByIntegerLiteral>(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope
  ) -> Value? {
    var address = Self.address(selector, scope)
    guard AudioObjectHasProperty(object, &address) else { return nil }
    var value: Value = 0
    var size = UInt32(MemoryLayout<Value>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
      return nil
    }
    return value
  }

  /// The objects a list property holds: devices, processes, a process's devices.
  private func list(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope
  ) -> [AudioObjectID] {
    var address = Self.address(selector, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0
    else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else {
      return []
    }
    return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
  }

  private static func address(
    _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }
}
