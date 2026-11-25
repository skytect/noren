// Whether a camera is in use, from CoreMediaIO: any camera running somewhere
// (kCMIODevicePropertyDeviceIsRunningSomewhere), read again when that or the list of cameras
// changes.
import CoreMediaIO

final class Camera {
  private let changed: (Bool) -> Void
  /// The objects whose property is already listened to, so each gets one listener.
  private var listening: Set<CMIOObjectID> = []

  /// Reads the cameras now, and again on every change; `changed` gets whether one is in use.
  init(changed: @escaping (Bool) -> Void) {
    self.changed = changed
    listen(
      CMIOObjectID(kCMIOObjectSystemObject),
      CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
    read()
  }

  private func read() {
    var address = Self.address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
    let system = CMIOObjectID(kCMIOObjectSystemObject)
    var size: UInt32 = 0
    var used: UInt32 = 0
    var devices: [CMIOObjectID] = []
    if CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 {
      devices = Array(repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
      if CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) != noErr {
        used = 0
      }
    }
    var inUse = false
    for device in devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size) {
      listen(device, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
      var running = Self.address(
        CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
      var value: UInt32 = 0
      var got: UInt32 = 0
      if CMIOObjectGetPropertyData(
        device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &value) == noErr,
        value != 0
      {
        inUse = true
      }
    }
    changed(inUse)
  }

  /// Reads the cameras again whenever `selector` changes on `object`; once per object.
  private func listen(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) {
    guard !listening.contains(object) else { return }
    var address = Self.address(selector)
    let status = CMIOObjectAddPropertyListenerBlock(object, &address, .main) { [weak self] _, _ in
      MainActor.assumeIsolated { self?.read() }
    }
    if status == noErr { listening.insert(object) }
  }

  private static func address(_ selector: CMIOObjectPropertySelector)
    -> CMIOObjectPropertyAddress
  {
    CMIOObjectPropertyAddress(
      mSelector: selector, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
  }
}
