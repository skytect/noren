// Ctrl+drag moves a window: hold Ctrl and drag anywhere in a window, as Super+drag does on
// Hyprland (with a keyboard remapper, the Super key can be the Ctrl key).
//
// An event tap takes a left-button press with Ctrl (without Cmd) over an app's window, and the drag
// that follows: the app sees neither, so it works the same in every app, AppKit or not (Chromium
// and Electron windows ignore macOS's own Ctrl+Cmd+drag, NSWindowShouldDragOnGesture). The window
// is focused at the press, so AeroSpace takes the move for a drag of the focused window, and the
// release goes on to the app and AeroSpace, which puts the window where it was dropped. The cost:
// Ctrl+click over a window is no longer a right-click.
//
// The window moves from inside the Dock when the Dock payload is there (NORMessageMove, docs/
// dock.md): the window server moves it as it does one dragged by its title bar. Without it, through
// Accessibility, which the app answers in its own time, so only the latest point is sent, one at a
// time (Mover).
//
// Needs Accessibility, to change events. An active tap whose process loses that grant can hold
// every click on the screen, so the tap runs only while the grant is there: it is looked at every
// grantCheckInterval, and the tap removed when it is gone and made again when it is back.
//
// The com.apple.accessibility.api distributed notification, posted when the Accessibility list
// changes, does not replace the timer: it is not posted when an app's row is removed, the case
// where a tap left running would hold the clicks, and on a first grant it can arrive before the
// grant is committed, so a check made on it reads the old answer.
import AppKit
import NorenPrivate
import Synchronization
import os

final class Drag: Part {
  private static let grantCheckInterval: TimeInterval = 2

  /// A window being dragged: where it and the pointer were at the press
  private struct Dragged {
    let mover: Mover
    let origin: CGPoint
    let start: CGPoint
  }

  private let log = Logger(subsystem: "local.noren", category: "drag")
  /// nil while there is no tap
  private var tap: (port: CFMachPort, source: CFRunLoopSource)?
  /// The drag under way, nil when there is none
  private var dragged: Dragged?

  func start() {
    // Asks once (the system prompt); the later looks take no options: an empty dictionary there
    // crashed in AXIsProcessTrustedWithOptions. The key is kAXTrustedCheckOptionPrompt's value:
    // Swift 6 reads that C global as shared mutable state.
    let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    if AXIsProcessTrustedWithOptions(prompt) {
      startTap()
    } else {
      log.info("no Accessibility permission yet: Ctrl+drag starts once it is granted")
    }
    let timer = Timer(timeInterval: Self.grantCheckInterval, repeats: true) { [unowned self] _ in
      MainActor.assumeIsolated { grantMayHaveChanged() }
    }
    RunLoop.main.add(timer, forMode: .common)
  }

  private func grantMayHaveChanged() {
    let granted = AXIsProcessTrusted()
    if granted, tap == nil { startTap() }
    if !granted, tap != nil { stopTap() }
  }

  private func startTap() {
    let mask: CGEventMask =
      1 << CGEventType.leftMouseDown.rawValue | 1 << CGEventType.leftMouseDragged.rawValue
      | 1 << CGEventType.leftMouseUp.rawValue
    guard
      let port = CGEvent.tapCreate(
        tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask,
        callback: { _, type, event, drag in
          // The tap's source is on the main run loop
          let passed = MainActor.assumeIsolated {
            Unmanaged<Drag>.fromOpaque(drag!).takeUnretainedValue().handle(type, event)
          }
          return passed ? Unmanaged.passUnretained(event) : nil
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      log.error("could not create the event tap; Ctrl+drag is off")
      return
    }
    let source = CFMachPortCreateRunLoopSource(nil, port, 0)!
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    tap = (port, source)
    log.info("Ctrl+drag on")
  }

  private func stopTap() {
    guard let tap else { return }
    CGEvent.tapEnable(tap: tap.port, enable: false)
    CFRunLoopRemoveSource(CFRunLoopGetMain(), tap.source, .commonModes)
    CFMachPortInvalidate(tap.port)
    self.tap = nil
    dragged?.mover.finish()
    dragged = nil
    log.info("Accessibility permission gone: Ctrl+drag off until it is back")
  }

  /// Follows `event`; false to take it from the app under the pointer.
  private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      if let tap { CGEvent.tapEnable(tap: tap.port, enable: true) }
      return true
    case .leftMouseDown:
      dragged?.mover.finish()
      dragged = nil
      guard event.flags.contains(.maskControl), !event.flags.contains(.maskCommand),
        let window = Self.window(at: event.location)
      else { return true }
      let mover = Mover(window: window.id, pid: window.pid)
      NSRunningApplication(processIdentifier: window.pid)?.activate()
      dragged = Dragged(mover: mover, origin: window.frame.origin, start: event.location)
      return false
    case .leftMouseDragged:
      guard let dragged else { return true }
      let pointer = event.location
      var point = CGPoint(
        x: dragged.origin.x + pointer.x - dragged.start.x,
        y: dragged.origin.y + pointer.y - dragged.start.y)
      // The title bar stays on the screen under the pointer, below its top edge
      if let top = Self.screenTop(at: pointer) { point.y = max(point.y, top) }
      dragged.mover.move(to: point)
      return false
    case .leftMouseUp:
      dragged?.mover.finish()
      dragged = nil
      return true
    default:
      return true
    }
  }

  /// The app window at `point` (the window server's global coordinates): the frontmost window
  /// there, past noren's own (the border lets clicks through) and see-through ones, if it is an app
  /// window at the normal level, not the menu bar, the Dock or another app's overlay.
  private static func window(at point: CGPoint) -> (id: CGWindowID, pid: pid_t, frame: CGRect)? {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return nil }
    let own = ProcessInfo.processInfo.processIdentifier
    for window in windows {
      guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != own,
        (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
        let bounds = window[kCGWindowBounds as String] as? NSDictionary,
        let frame = CGRect(dictionaryRepresentation: bounds), frame.contains(point)
      else { continue }
      guard window[kCGWindowLayer as String] as? Int == 0,
        let id = window[kCGWindowNumber as String] as? CGWindowID
      else { return nil }
      return (id, pid, frame)
    }
    return nil
  }

  /// The top edge of the screen at `point`, in the window server's global coordinates
  private static func screenTop(at point: CGPoint) -> CGFloat? {
    var display: CGDirectDisplayID = 0
    var count: UInt32 = 0
    guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else {
      return nil
    }
    return CGDisplayBounds(display).minY
  }
}

/// Moves one window while it is dragged: through the Dock payload when it is there, else through
/// Accessibility. Off the main thread, one move at a time, always to the latest point asked for: a
/// slow app skips points rather than trailing behind the pointer. `port` and `element` are only
/// touched on `queue`.
nonisolated private final class Mover: @unchecked Sendable {
  private struct State {
    var latest: CGPoint?
    var busy = false
    var finished = false
  }

  /// How long the payload or an app may take with one move, in seconds
  private static let timeout: CFTimeInterval = 0.1
  private static let queue = DispatchQueue(label: "local.noren.drag")

  private let window: CGWindowID
  private let pid: pid_t
  private let state = Mutex(State())
  /// The payload's port, nil when it is not there; set on `queue` before any move
  private var port: CFMessagePort?
  /// The window's Accessibility element; set on `queue` before any move
  private var element: AXUIElement?

  init(window: CGWindowID, pid: pid_t) {
    self.window = window
    self.pid = pid
    Self.queue.async { [self] in
      port = CFMessagePortCreateRemote(nil, NOR_DOCK_PORT as CFString)
      element = Accessibility.shared.element(window, of: pid)
      raise()
    }
  }

  func move(to point: CGPoint) {
    let start = state.withLock { state in
      state.latest = point
      guard !state.busy, !state.finished else { return false }
      state.busy = true
      return true
    }
    if start { Self.queue.async { [self] in drain() } }
  }

  /// No more moves after the ones asked for
  func finish() {
    state.withLock { $0.finished = true }
    Self.queue.async { [self] in Accessibility.shared.release(pid: pid) }
  }

  /// Sends the latest point until no newer one is waiting. On `queue`.
  private func drain() {
    while let point = state.withLock({ state -> CGPoint? in
      guard let point = state.latest else {
        state.busy = false
        return nil
      }
      state.latest = nil
      return point
    }) {
      if !moveInDock(point), let element {
        Accessibility.shared.move(element, of: pid, to: point)
      }
    }
  }

  /// Hands the move to the Dock payload; false when it is not there.
  private func moveInDock(_ point: CGPoint) -> Bool {
    guard let port else { return false }
    var move = NORMove(window: window, x: point.x, y: point.y)
    let data = Data(bytes: &move, count: MemoryLayout<NORMove>.size)
    return CFMessagePortSendRequest(
      port, NORMessage.move.rawValue, data as CFData, Self.timeout, 0, nil, nil)
      == kCFMessagePortSuccess
  }

  /// Brings the window to the front of its app, which the press made active: the app's other
  /// windows stay behind it, and AeroSpace focuses it.
  private func raise() {
    guard let element else { return }
    AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
  }
}

/// The Accessibility side of a drag, on Mover's queue: finding the window's element, and moving
/// it. Chromium, Firefox and Electron animate every move of a window while their
/// AXEnhancedUserInterface is on, so it is off while one of their windows is dragged.
nonisolated private final class Accessibility: @unchecked Sendable {
  static let shared = Accessibility()

  private static let enhancedUserInterface = "AXEnhancedUserInterface"
  /// The apps whose AXEnhancedUserInterface was turned off for a drag, to turn back on
  private var enhanced: Set<pid_t> = []

  func element(_ window: CGWindowID, of pid: pid_t) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.1)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
      let windows = value as? [AXUIElement]
    else { return nil }
    return windows.first { element in
      var found: CGWindowID = 0
      return _AXUIElementGetWindow(element, &found) == .success && found == window
    }
  }

  func move(_ element: AXUIElement, of pid: pid_t, to point: CGPoint) {
    let app = AXUIElementCreateApplication(pid)
    var on: CFTypeRef?
    if !enhanced.contains(pid),
      AXUIElementCopyAttributeValue(app, Self.enhancedUserInterface as CFString, &on) == .success,
      (on as? Bool) == true
    {
      AXUIElementSetAttributeValue(app, Self.enhancedUserInterface as CFString, kCFBooleanFalse)
      enhanced.insert(pid)
    }
    var position = point
    guard let value = AXValueCreate(.cgPoint, &position) else { return }
    AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
  }

  /// Turns the app's AXEnhancedUserInterface back on, if a drag turned it off
  func release(pid: pid_t) {
    guard enhanced.remove(pid) != nil else { return }
    AXUIElementSetAttributeValue(
      AXUIElementCreateApplication(pid), Self.enhancedUserInterface as CFString, kCFBooleanTrue)
  }
}
