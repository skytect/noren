// Raw frames from every trackpad, through the private MultitouchSupport framework: a CGEvent tap
// no longer carries a gesture's fingers on recent macOS. Reading them needs Input Monitoring.
//
// The frames stop after sleep, a screen lock, or the trackpad settings being applied again, so the
// trackpads are attached afresh then. Whatever applies the settings can say so by posting the
// Darwin notification `local.noren.reattach-trackpads` (`notifyutil -p
// local.noren.reattach-trackpads`).
import AppKit
import NorenCore
import NorenPrivate
import notify
import os

/// MultitouchSupport's functions, looked up at run time.
private struct MultitouchSupport {
  let createList: MTDeviceCreateListFunction
  let register: MTRegisterContactFrameCallbackFunction
  let unregister: MTUnregisterContactFrameCallbackFunction
  let start: MTDeviceStartFunction
  let stop: MTDeviceStopFunction

  struct Missing: Error, CustomStringConvertible {
    let description: String
  }

  static func load() throws(Missing) -> MultitouchSupport {
    guard let handle = dlopen(NOR_MULTITOUCH_SUPPORT_PATH, RTLD_LAZY) else {
      throw Missing(description: "cannot open MultitouchSupport: \(String(cString: dlerror()))")
    }
    func function<T>(_ name: String, as type: T.Type) throws(Missing) -> T {
      guard let symbol = dlsym(handle, name) else {
        throw Missing(description: "MultitouchSupport has no \(name)")
      }
      return unsafeBitCast(symbol, to: type)
    }
    return MultitouchSupport(
      createList: try function("MTDeviceCreateList", as: MTDeviceCreateListFunction.self),
      register: try function(
        "MTRegisterContactFrameCallback", as: MTRegisterContactFrameCallbackFunction.self),
      unregister: try function(
        "MTUnregisterContactFrameCallback", as: MTUnregisterContactFrameCallbackFunction.self),
      start: try function("MTDeviceStart", as: MTDeviceStartFunction.self),
      stop: try function("MTDeviceStop", as: MTDeviceStopFunction.self))
  }
}

/// Every trackpad's frames, handed over on the main actor.
final class Trackpads {
  /// The Darwin notification that has the trackpads attached afresh.
  static let reattachNotification = "local.noren.reattach-trackpads"

  /// The one listening; MultitouchSupport's callback carries no context to find it by
  private static weak var listening: Trackpads?

  private let log = Logger(subsystem: "local.noren", category: "strip")
  private let multitouch: MultitouchSupport
  private let frames: (TouchFrame) -> Void
  private let attached: () -> Void
  private var devices: CFArray?
  private var observers: [any NSObjectProtocol] = []

  /// Starts listening: `frames` gets every frame in order, and `attached` runs each time the
  /// trackpads are attached afresh, when a frame of a touch in progress may never come. Throws
  /// when MultitouchSupport lacks a function noren calls.
  init(frames: @escaping (TouchFrame) -> Void, attached: @escaping () -> Void) throws {
    multitouch = try MultitouchSupport.load()
    self.frames = frames
    self.attached = attached
    Self.listening = self
    attach()
    let workspace = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
    ] {
      observers.append(
        workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
          MainActor.assumeIsolated { self.attach() }
        })
    }
    observers.append(
      DistributedNotificationCenter.default().addObserver(
        forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
      ) { _ in
        MainActor.assumeIsolated { self.attach() }
      })
    var token: Int32 = 0
    let status = notify_register_dispatch(Self.reattachNotification, &token, .main) { _ in
      MainActor.assumeIsolated { self.attach() }
    }
    if status != NOTIFY_STATUS_OK {
      log.error("cannot follow \(Self.reattachNotification, privacy: .public): status \(status)")
    }
  }

  /// Listens to every trackpad present now, dropping the ones listened to before.
  private func attach() {
    for device in Self.deviceRefs(devices) {
      multitouch.unregister(device, receiveContacts)
      multitouch.stop(device)
    }
    devices = multitouch.createList()?.takeRetainedValue()
    let present = Self.deviceRefs(devices)
    for device in present {
      multitouch.register(device, receiveContacts)
      multitouch.start(device, 0)
    }
    attached()
    log.info("listening to \(present.count) trackpad(s)")
  }

  private static func deviceRefs(_ devices: CFArray?) -> [MTDeviceRef] {
    guard let devices else { return [] }
    return (0..<CFArrayGetCount(devices)).compactMap { index in
      UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(devices, index))
    }
  }

  fileprivate static func deliver(_ frame: TouchFrame) {
    listening?.frames(frame)
  }
}

/// MultitouchSupport's callback, on its own thread: reduces the frame and hands it to the main
/// actor, in order.
private nonisolated func receiveContacts(
  device: MTDeviceRef?, touches: UnsafeMutablePointer<MTTouch>?, count: Int32, timestamp: Double,
  frame: Int32
) -> Int32 {
  let contacts = UnsafeBufferPointer(start: touches, count: touches == nil ? 0 : Int(count)).map {
    Contact(
      state: Int($0.state), x: Double($0.normalized.position.x),
      y: Double($0.normalized.position.y))
  }
  let frame = TouchFrame(device: Int(bitPattern: device), time: timestamp, contacts: contacts)
  DispatchQueue.main.async {
    MainActor.assumeIsolated { Trackpads.deliver(frame) }
  }
  return 0
}
