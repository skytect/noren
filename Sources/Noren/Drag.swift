// Ctrl+drag moves a window: hold Ctrl and drag anywhere in a window, as Super+drag does on
// Hyprland (with a keyboard remapper, the Super key can be the Ctrl key).
//
// macOS moves a window on Ctrl+Cmd+drag once NSWindowShouldDragOnGesture is on (`defaults write
// -g NSWindowShouldDragOnGesture -bool true`); the app's AppKit reads the modifiers off the mouse
// events. This tap adds Cmd to a left-button press that has Ctrl without Cmd, and to the drag and
// release that follow it, so Ctrl+drag alone does the same. The cost: Ctrl+click is no longer a
// right-click.
//
// Needs Accessibility, to change events. An active tap whose process loses that grant can hold
// every click on the screen, so the tap runs only while the grant is there: it is looked at every
// grantCheckInterval, and the tap removed when it is gone and made again when it is back.
import AppKit
import os

final class Drag: Part {
  private static let grantCheckInterval: TimeInterval = 2

  private let log = Logger(subsystem: "local.noren", category: "drag")
  /// nil while there is no tap
  private var tap: (port: CFMachPort, source: CFRunLoopSource)?
  /// Whether the press under way is a Ctrl+drag, so its drag and release get Cmd too
  private var dragging = false

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
          MainActor.assumeIsolated {
            Unmanaged<Drag>.fromOpaque(drag!).takeUnretainedValue().handle(type, event)
          }
          return Unmanaged.passUnretained(event)
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
    dragging = false
    log.info("Accessibility permission gone: Ctrl+drag off until it is back")
  }

  private func handle(_ type: CGEventType, _ event: CGEvent) {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap.port, enable: true) }
      return
    }
    if type == .leftMouseDown {
      dragging = event.flags.contains(.maskControl) && !event.flags.contains(.maskCommand)
    }
    if dragging { event.flags.formUnion([.maskControl, .maskCommand]) }
    if type == .leftMouseUp { dragging = false }
  }
}
