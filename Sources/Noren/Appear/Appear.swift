// New windows show only once in place. AeroSpace puts a new window in its tile, and Dwindle may
// then nest it: two jumps from wherever the app opened it. The Dock payload (Dock/payload.m) hides
// each new app window as the window server creates it and says so here (NORMessageHeld,
// NorenPrivate/DockProtocol.h); the window is shown again once it is in place:
//
//   - Dwindle shows each window AeroSpace reports (window-detected) once it has nested it or left
//     it, faded in, or at once when the window floats;
//   - a held window that AeroSpace already lists under an older id of its own is shown here, after
//     a list-windows: a new native tab (Finder, Ghostty) becomes the front window of its tab
//     group, which AeroSpace counts as one window and reports nothing for;
//   - noren's own windows are shown at once.
//
// A window of an app AeroSpace floats (Config's appear.floating-apps, by default AeroSpace's own
// app-id floating rules) is shown again at once and not covered: nothing makes room for it, so
// hiding it would only blink it.
//
// Anything else (windows AeroSpace takes for popups) the payload shows by itself after
// NOR_HOLD_LIMIT, as it does every held window when noren stops answering.
//
// While a window is held or fading in, the border leaves it be (holds(_:)): its ring would show
// before the window.
//
// Hiding the new window alone still shows the others make room for it, twice when Dwindle nests
// it. So the screen in use is covered too, with a still capture of itself taken as the window is
// held (ScreenCaptureKit; Screen Recording), until the last held window is shown and the windows
// on the screen have stopped moving (the ones making room may still be on their way): then the
// cover fades out, one change instead of the moves between. A capture that comes back after its
// windows are shown is dropped; a cover never stays up longer than coverLimit.
import AppKit
import NorenCore
import NorenPrivate
import ScreenCaptureKit
import os

final class Appear: Part {
  /// A window AeroSpace reported this recently is Dwindle's to show
  private static let detectedRecently = Duration.seconds(2)
  /// How long after a window is held it is looked up. A command cancels the refresh AeroSpace may
  /// be running to find that very window (runLightSession in
  /// Sources/AppBundle/layout/refresh.swift), so the lookup waits for most new windows to be found
  /// first.
  private static let lookupDelay = Duration.milliseconds(100)
  /// How long a held window AeroSpace lists under an older id waits for a window-detected of its
  /// own, which may still be on its way, before it is shown as a new tab
  private static let detectGrace = Duration.milliseconds(50)
  /// The windows on a covered screen count as still once their frames have not changed for
  /// Stillness.checks looks, stillInterval apart
  private static let stillInterval = Duration.seconds(1.0 / 30)
  /// The longest a cover stays up, whatever else happens
  private static let coverLimit = Duration.seconds(2)
  /// How long noren waits to hand the payload a message, in seconds
  nonisolated private static let sendTimeout: CFTimeInterval = 0.25

  private let log = Logger(subsystem: "local.noren", category: "appear")
  private let aeroSpace: AeroSpaceClient
  /// Has the border look at the focused window again: one it left alone may have appeared
  private let wakeBorder: () -> Void
  /// The floating apps the config names, or nil to read them from AeroSpace's config
  private let configuredFloatingApps: [String]?
  /// Bundle ids of the apps whose windows float
  private var floatingApps: Set<String>
  /// The latest message to the payload; each waits for the one before, so they arrive in order
  private var sending: Task<Void, Never>?
  /// Until when each held window counts as held, by window server id, and the task that lets the
  /// border look at it then
  private var held: [CGWindowID: (until: ContinuousClock.Instant, expiry: Task<Void, Never>)] = [:]
  /// When AeroSpace reported each recent window, by AeroSpace's window id
  private var detected: [UInt32: ContinuousClock.Instant] = [:]
  /// Held windows not looked up yet, and whether a lookup is under way
  private var unchecked: Set<CGWindowID> = []
  private var checking = false
  /// The cover over the screen in use, and the held windows it waits for
  private var cover: NSWindow?
  private var covered: Set<CGWindowID> = []
  /// Which cover a capture or a deadline belongs to
  private var coverGeneration = 0
  /// ScreenCaptureKit's displays by display id, looked up ahead so a cover costs only its capture
  private var displays: [CGDirectDisplayID: SCDisplay] = [:]
  private var screensObserver: (any NSObjectProtocol)?

  init(config: AppearConfig, aeroSpace: AeroSpaceClient, wakeBorder: @escaping () -> Void) {
    self.aeroSpace = aeroSpace
    self.wakeBorder = wakeBorder
    configuredFloatingApps = config.floatingApps
    floatingApps = Set(config.floatingApps ?? [])
  }

  func start() {
    lookUpDisplays()
    screensObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [unowned self] _ in
      MainActor.assumeIsolated { lookUpDisplays() }
    }
    // The port lives as long as noren, and keeps this part with it
    var context = CFMessagePortContext(
      version: 0, info: Unmanaged.passRetained(self).toOpaque(), retain: nil, release: nil,
      copyDescription: nil)
    let port = CFMessagePortCreateLocal(
      nil, NOR_APP_PORT as CFString,
      { _, message, data, info in
        // Its run loop source is on the main run loop
        MainActor.assumeIsolated {
          Unmanaged<Appear>.fromOpaque(info!).takeUnretainedValue().received(message, data)
        }
        return nil
      }, &context, nil)
    guard let port else {
      log.error("could not open \(NOR_APP_PORT, privacy: .public); new windows show as they open")
      return
    }
    let source = CFMessagePortCreateRunLoopSource(nil, port, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
  }

  func handle(_ event: AeroSpaceEvent) {
    switch event {
    case .connected:
      guard configuredFloatingApps == nil else { return }
      Task {
        do {
          floatingApps = try await aeroSpace.configFacts().floatingApps
        } catch {
          log.error("could not read AeroSpace's floating apps: \(error, privacy: .public)")
        }
      }
    case .windowDetected(let window, _, _, _):
      detected = detected.filter { isRecent($0.value) }
      detected[window] = .now
    default:
      break
    }
  }

  /// Has the Dock payload show the new window `window` (a window server id) if it holds it hidden:
  /// faded in, or at once.
  func show(_ window: CGWindowID, fade: Bool) {
    guard window != 0 else { return }
    send(fade ? .reveal : .show, window)
    uncovered(window, fade: fade)
    if held[window] != nil { hold(window, for: fade ? .seconds(NOR_FADE) : .zero) }
  }

  /// Whether `window` is held hidden or still fading in, as far as noren knows.
  func holds(_ window: CGWindowID) -> Bool {
    held[window].map { $0.until > .now } ?? false
  }

  // MARK: - The payload

  /// The payload's NORMessageHeld for the windows in `data`
  private func received(_ message: Int32, _ data: CFData?) {
    guard message == NORMessage.held.rawValue, let data else { return }
    let own = Set(NSApp.windows.map { CGWindowID($0.windowNumber) })
    for window in Self.windows(in: data as Data) {
      if own.contains(window) || floats(window) {
        send(.show, window)
        continue
      }
      hold(window, for: .seconds(NOR_HOLD_LIMIT + NOR_FADE))
      coverScreen(for: window)
      unchecked.insert(window)
    }
    Task {
      try? await Task.sleep(for: Self.lookupDelay)
      check()
    }
  }

  /// The window server ids in a message's data: an array of uint32_t
  private static func windows(in data: Data) -> [CGWindowID] {
    data.withUnsafeBytes { bytes in
      let size = MemoryLayout<CGWindowID>.size
      return (0..<bytes.count / size).map {
        bytes.loadUnaligned(fromByteOffset: $0 * size, as: CGWindowID.self)
      }
    }
  }

  private func send(_ message: NORMessage, _ window: CGWindowID) {
    sending = Task { [previous = sending] in
      await previous?.value
      await Self.deliver(message, window)
    }
  }

  /// Hands the payload `message` about `window`. Off the main thread: sending may wait up to
  /// sendTimeout.
  @concurrent
  nonisolated private static func deliver(_ message: NORMessage, _ window: CGWindowID) async {
    // No payload in the Dock: nothing is hidden
    guard let port = CFMessagePortCreateRemote(nil, NOR_DOCK_PORT as CFString) else { return }
    let data = withUnsafeBytes(of: window) { Data($0) }
    CFMessagePortSendRequest(port, message.rawValue, data as CFData, sendTimeout, 0, nil, nil)
  }

  /// Counts `window` as held for `duration` more, then lets the border look at it
  private func hold(_ window: CGWindowID, for duration: Duration) {
    held[window]?.expiry.cancel()
    let expiry = Task {
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else { return }
      held[window] = nil
      wakeBorder()
    }
    held[window] = (.now + duration, expiry)
  }

  /// Whether `window` belongs to an app AeroSpace floats
  private func floats(_ window: CGWindowID) -> Bool {
    var ids: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: UInt(window))]
    guard let array = CFArrayCreate(nil, &ids, 1, nil),
      let infos = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]],
      infos.count == 1, let pid = infos[0][kCGWindowOwnerPID as String] as? pid_t,
      let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    else { return false }
    return floatingApps.contains(bundle)
  }

  // MARK: - New tabs

  private func isRecent(_ instant: ContinuousClock.Instant) -> Bool {
    instant.duration(to: .now) < Self.detectedRecently
  }

  private func detectedRecently(_ window: UInt32) -> Bool {
    detected[window].map(isRecent) ?? false
  }

  /// Shows the held `window`, which AeroSpace lists as its window `listed`, unless AeroSpace has
  /// reported `listed` as new: then Dwindle is placing it
  private func showUnlessNew(_ window: CGWindowID, listed: UInt32) {
    guard !detectedRecently(listed) else { return }
    Task {
      try? await Task.sleep(for: Self.detectGrace)
      if !detectedRecently(listed) { show(window, fade: true) }
    }
  }

  /// Looks the held windows up in AeroSpace, one list-windows for all that came meanwhile. A
  /// window AeroSpace does not list yet is left to Dwindle, or to the payload's deadline.
  private func check() {
    guard !checking, !unchecked.isEmpty else { return }
    checking = true
    let windows = unchecked
    unchecked.removeAll()
    Task {
      var listed: [CGWindowID: UInt32] = [:]
      do {
        for window in try await aeroSpace.run(
          ["list-windows", "--all", "--json", "--format", "%{window-id-native} %{window-id}"],
          as: [ListedWindow].self)
        {
          listed[window.nativeId] = window.id
        }
      } catch {
        log.error("could not list the windows: \(error, privacy: .public)")
      }
      checking = false
      for window in windows {
        if let id = listed[window] { showUnlessNew(window, listed: id) }
      }
      check()
    }
  }

  // MARK: - The cover

  private func lookUpDisplays() {
    Task {
      do {
        let content = try await SCShareableContent.current
        displays = Dictionary(
          content.displays.map { ($0.displayID, $0) }, uniquingKeysWith: { first, _ in first })
      } catch {
        log.notice("new windows go uncovered: \(error, privacy: .public)")
        displays = [:]
      }
    }
  }

  /// Covers the screen with keyboard focus, where AeroSpace puts new windows, for the held
  /// `window`
  private func coverScreen(for window: CGWindowID) {
    covered.insert(window)
    guard covered.count == 1 else { return }  // a cover for an earlier window is on its way or up
    coverGeneration += 1
    let generation = coverGeneration
    // Not looked up yet, or no Screen Recording: no cover
    guard let screen = NSScreen.main, let display = displays[screen.displayID] else { return }
    let frame = screen.frame
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let configuration = SCStreamConfiguration()
    configuration.width = Int((frame.width * CGFloat(filter.pointPixelScale)).rounded())
    configuration.height = Int((frame.height * CGFloat(filter.pointPixelScale)).rounded())
    configuration.showsCursor = false
    Task {
      let image: CGImage
      do {
        image = try await SCScreenshotManager.captureImage(
          contentFilter: filter, configuration: configuration)
      } catch {
        log.error("could not capture the screen to cover it: \(error, privacy: .public)")
        return
      }
      // Its windows were shown before the capture came back
      guard generation == coverGeneration, !covered.isEmpty else { return }
      let cover = NSWindow(
        contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
      cover.isReleasedWhenClosed = false
      cover.isOpaque = true
      cover.hasShadow = false
      cover.ignoresMouseEvents = true
      cover.level = .statusBar
      cover.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
      cover.contentView?.wantsLayer = true
      cover.contentView?.layer?.contents = image
      cover.setFrame(frame, display: false)
      cover.orderFrontRegardless()
      self.cover?.orderOut(nil)  // never two
      self.cover = cover
      // This cover goes after the limit whatever else happens
      Task {
        try? await Task.sleep(for: Self.coverLimit)
        if self.cover === cover { uncover(fade: false) }
        cover.orderOut(nil)
      }
    }
  }

  private func uncover(fade: Bool) {
    let cover = self.cover
    self.cover = nil
    covered.removeAll()
    coverGeneration += 1
    guard let cover else { return }
    guard fade else {
      cover.orderOut(nil)
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NOR_FADE
      cover.animator().alphaValue = 0
    }
    Task {
      try? await Task.sleep(for: .seconds(NOR_FADE))
      cover.orderOut(nil)
    }
  }

  /// The frames of the windows on screen under the cover, in front-to-back order
  private func windowFrames() -> [WindowFrame] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return [] }
    return infos.compactMap { info in
      guard info[kCGWindowLayer as String] as? Int ?? 0 == 0,
        let window = info[kCGWindowNumber as String] as? CGWindowID,
        let bounds = info[kCGWindowBounds as String] as? NSDictionary,
        let rect = CGRect(dictionaryRepresentation: bounds)
      else { return nil }
      return WindowFrame(window: window, bounds: rect)
    }
  }

  /// Lifts cover `generation` once the windows under it have been still for Stillness.checks
  /// looks
  private func uncoverWhenStill(_ generation: Int, fade: Bool) {
    Task {
      var stillness = Stillness()
      while generation == coverGeneration {
        if stillness.look(windowFrames()) {
          uncover(fade: fade)
          return
        }
        try? await Task.sleep(for: Self.stillInterval)
      }
    }
  }

  /// The held `window` is being shown: the cover goes once it waits for no other and the windows
  /// under it are still
  private func uncovered(_ window: CGWindowID, fade: Bool) {
    guard covered.remove(window) != nil, covered.isEmpty else { return }
    guard cover != nil else {
      uncover(fade: fade)  // the capture has not come back: it is dropped
      return
    }
    uncoverWhenStill(coverGeneration, fade: fade)
  }
}
