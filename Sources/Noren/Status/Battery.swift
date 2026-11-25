// The internal battery's charge and whether the Mac is on power, from IOKit's power sources,
// read again on each of their notifications.
import Foundation
import IOKit.ps
import NorenCore

final class Battery {
  private let changed: (StatusReadings.Battery?) -> Void

  /// Reads the battery now, and again on every change; `changed` gets nil without a battery.
  init(changed: @escaping (StatusReadings.Battery?) -> Void) {
    self.changed = changed
    let context = Unmanaged.passUnretained(self).toOpaque()
    if let source = IOPSNotificationCreateRunLoopSource(
      { context in
        MainActor.assumeIsolated {
          Unmanaged<Battery>.fromOpaque(context!).takeUnretainedValue().read()
        }
      }, context)?.takeRetainedValue()
    {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }
    read()
  }

  private func read() {
    changed(Self.internalBattery())
  }

  private static func internalBattery() -> StatusReadings.Battery? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    var battery: StatusReadings.Battery?
    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
          as? [String: Any],
        description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
      else { continue }
      battery = StatusReadings.Battery(
        percent: StatusReadings.Battery.percent(
          current: description[kIOPSCurrentCapacityKey] as? Int ?? 0,
          max: description[kIOPSMaxCapacityKey] as? Int ?? 0),
        onPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
    }
    return battery
  }
}
