// `noren sidecar`: SidecarCore's SidecarDisplayManager, the private framework behind the Screen
// Mirroring menu (as github.com/Ocasio-J/SidecarLauncher uses it), reached through the
// Objective-C runtime.
import Foundation

enum Sidecar {
  /// How long to wait for a connection or disconnection to finish.
  private static let timeout = DispatchTimeInterval.seconds(30)

  private typealias Completion = @convention(block) (NSError?) -> Void
  private typealias ConnectCall = @convention(c) (NSObject, Selector, NSObject, Completion) -> Void

  static func run(_ arguments: [String]) -> Int32 {
    guard
      dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY)
        != nil
    else { return Commands.fail("sidecar: SidecarCore is missing") }
    guard let managerClass = NSClassFromString("SidecarDisplayManager") as? NSObject.Type,
      let manager = managerClass.perform(NSSelectorFromString("sharedManager"))?
        .takeUnretainedValue() as? NSObject
    else { return Commands.fail("sidecar: no SidecarDisplayManager") }
    let devices = manager.value(forKey: "devices") as? [NSObject] ?? []
    let connected = manager.value(forKey: "connectedDevices") as? [NSObject] ?? []

    switch arguments {
    case ["list"]:
      for device in devices {
        print(name(of: device) + (connected.contains(device) ? "  connected" : ""))
      }
      return 0
    case []:
      break
    default:
      return Commands.fail("usage: noren sidecar [list]", status: 2)
    }

    let disconnect = !connected.isEmpty
    guard let device = disconnect ? connected.first : devices.first else {
      return Commands.fail(
        "sidecar: no iPad nearby (same Apple Account, Wi-Fi and Bluetooth on)", status: 3)
    }
    let selector = NSSelectorFromString(
      disconnect ? "disconnectFromDevice:completion:" : "connectToDevice:completion:")
    let call = unsafeBitCast(manager.method(for: selector), to: ConnectCall.self)
    // SidecarCore calls back on a queue of its own, so the main thread can wait for it
    let finished = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var failure: NSError?
    call(manager, selector, device) { error in
      failure = error
      finished.signal()
    }
    guard finished.wait(timeout: .now() + timeout) == .success else {
      return Commands.fail("sidecar: no answer within \(timeout)", status: 4)
    }
    if let failure { return Commands.fail("sidecar: \(failure.localizedDescription)", status: 4) }
    print("\(disconnect ? "disconnected from" : "connected to") \(name(of: device))")
    return 0
  }

  private static func name(of device: NSObject) -> String {
    device.value(forKey: "name") as? String ?? "an unnamed iPad"
  }
}
