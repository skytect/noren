// The focused window's border: a ring over the window's outermost `width` points, one window
// level above its window: above app windows, or, for a tiled window Layers put one level down,
// above the tiled windows and under the floating ones. Inside the window's edge, so the gaps
// between windows look the same whichever window has focus. Ordering it just above the window
// instead did not hold: activating an app raises its windows over the ring. The level's cost: a
// window on the same level overlapping the focused one shows the ring over it. A window AeroSpace
// fills its monitor with has no ring.
//
// The focused window comes from AeroSpace, asked after each focus event for the window server's
// id of it (%{window-id-native}; the events' windowId is AeroSpace's own numbering); its frame and
// stacking from the window server. Nothing is looked at while nothing happens: the ring is fitted
// again when Accessibility says the window moved, resized, minimized or closed, or its app hid
// (WindowWatch), and after any AeroSpace event. For a moment after each of those, and while the
// mouse drags, the frame is followed every frame too, in case the notifications come too far
// apart to keep the ring on a window being dragged or resized, and because the window server may
// report a window's new corners a moment after it moved.
//
// A new window the Dock payload holds hidden gets its ring only once it has faded in (Appear).
//
// Each corner follows the window's own (CornerRadii works them out again each time the ring is
// fitted): a window's corners can differ, a bottom one near the screen's rounded corner from the
// rest, so the ring is four pieces, each a quarter of the ring clipped from a ring with that
// corner's radius, all with continuous corners like the windows'.
//
// The ring's colour runs from `color` at its top-left to `color-end` at its bottom-right, as
// Hyprland's gradient borders do: one gradient, with the four pieces as its mask.
import AppKit
import NorenCore
import os

final class Border: Part {
  private static let frameInterval: TimeInterval = 1.0 / 60
  /// How long the ring follows every frame after something moved the window, or may have
  private static let followAfterEvent: TimeInterval = 0.5

  private let log = Logger(subsystem: "local.noren", category: "border")
  private let config: BorderConfig
  private let aeroSpace: AeroSpaceClient
  private let isHeld: (CGWindowID) -> Bool
  private let isBelow: (CGWindowID) -> Bool
  private let ring: Ring
  /// The focused window, nil when none is or it fills its monitor
  private var target: CGWindowID?
  /// Accessibility's notifications about the focused window
  private var watch: WindowWatch?
  private var reportedUntrusted = false
  /// Runs every frame while the ring follows the window closely, nil otherwise
  private var timer: Timer?
  private var followUntil = Date.distantPast
  /// The latest read of the focused window; each waits for the one before, so the ring ends on
  /// the window focused last
  private var following: Task<Void, Never>?

  /// `isHeld` tells whether the Dock payload holds a new window hidden, or it is still fading in;
  /// `isBelow` whether a window is one level below app windows (Layers).
  init(
    config: BorderConfig, aeroSpace: AeroSpaceClient, isHeld: @escaping (CGWindowID) -> Bool,
    isBelow: @escaping (CGWindowID) -> Bool
  ) {
    self.config = config
    self.aeroSpace = aeroSpace
    self.isHeld = isHeld
    self.isBelow = isBelow
    ring = Ring(width: config.width)
  }

  func start() {
    applyColors()
    if config.color == nil {
      // The accent colour can change while noren runs
      NotificationCenter.default.addObserver(
        forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
      ) { [unowned self] _ in
        MainActor.assumeIsolated { applyColors() }
      }
    }
    // A window dragged or resized may tell Accessibility only when the drag ends
    NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [unowned self] _ in
      follow()
    }
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [unowned self] _ in
      MainActor.assumeIsolated { wake() }
    }
  }

  func handle(_ event: AeroSpaceEvent) {
    switch event {
    // A binding may have made the window fill its monitor, or float it
    case .connected, .focusChanged, .focusedWorkspaceChanged, .bindingTriggered:
      readFocusedWindow()
    default: wake()
    }
  }

  /// Looks at the focused window again now, and follows it closely for a moment: AeroSpace is
  /// moving windows about, or a window the ring left alone may have appeared.
  func wake() {
    followUntil = Date(timeIntervalSinceNow: Self.followAfterEvent)
    tick()
  }

  /// Follows the window every frame for a moment, without fitting the ring now if it already is.
  private func follow() {
    followUntil = Date(timeIntervalSinceNow: Self.followAfterEvent)
    if timer == nil { tick() }
  }

  private func applyColors() {
    let start = (config.color.map { NSColor($0) } ?? NSColor.controlAccentColor)
      .withAlphaComponent(config.opacity)
    let end = config.colorEnd.map { NSColor($0, alpha: config.opacity) } ?? start
    ring.setColors(start: start, end: end)
  }

  private func readFocusedWindow() {
    following = Task { [previous = following] in
      await previous?.value
      retarget(await focusedWindow())
    }
  }

  /// The focused window, nil when none is or it fills its monitor
  private func focusedWindow() async -> CGWindowID? {
    let window: ListedWindow?
    do {
      window = try await aeroSpace.run(
        ["list-windows", "--focused", "--json", "--format", ListedWindow.format],
        as: [ListedWindow].self
      ).first
    } catch AeroSpaceError.noWindowFocused {
      return nil
    } catch {
      log.error("could not read the focused window: \(error, privacy: .public)")
      return nil
    }
    guard let window, !window.isFullscreen else { return nil }
    return window.nativeId
  }

  private func retarget(_ window: CGWindowID?) {
    if window != target {
      target = window
      ring.forgetFrame()
      watch?.stop()
      watch = window.flatMap(watchWindow)
    }
    wake()
  }

  /// Starts Accessibility's notifications about `window`; nil when they cannot start.
  private func watchWindow(_ window: CGWindowID) -> WindowWatch? {
    guard AXIsProcessTrusted() else {
      if !reportedUntrusted {
        reportedUntrusted = true
        Problems.report(
          "noren needs Accessibility for the border to follow windows; until then it moves only"
            + " on AeroSpace's events")
      }
      return nil
    }
    guard let pid = Self.windowInfo(window)?[kCGWindowOwnerPID as String] as? pid_t else {
      return nil
    }
    return WindowWatch(window: window, pid: pid) { [unowned self] in follow() }
  }

  /// Fits the ring, and keeps doing so every frame until the moment of following is over.
  private func tick() {
    fit()
    let following = followUntil.timeIntervalSinceNow > 0
    if following, timer == nil {
      let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [unowned self] _ in
        MainActor.assumeIsolated { tick() }
      }
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    } else if !following {
      timer?.invalidate()
      timer = nil
    }
  }

  /// Fits the ring over the focused window's edge, or hides it when there is nothing to ring.
  private func fit() {
    guard let target, !isHeld(target), let frame = Self.frame(of: target) else {
      ring.hide()
      return
    }
    // Asked each time, not only when the frame changes: the window server may report an app's new
    // corners a moment after its window has moved
    ring.show(frame: frame, corners: CornerRadii.of(target, frame: frame), below: isBelow(target))
  }

  /// The window server's description of `window`, nil if it is gone.
  private static func windowInfo(_ window: CGWindowID) -> [String: Any]? {
    // The array holds the window ids themselves, not number objects
    var ids: [UnsafeRawPointer?] = [UnsafeRawPointer(bitPattern: UInt(window))]
    guard let array = CFArrayCreate(nil, &ids, 1, nil),
      let infos = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]]
    else { return nil }
    return infos.first
  }

  /// `window`'s frame in Cocoa coordinates, or nil if it is gone or not on screen.
  private static func frame(of window: CGWindowID) -> CGRect? {
    guard let info = windowInfo(window), info[kCGWindowIsOnscreen as String] as? Bool == true,
      let bounds = info[kCGWindowBounds as String] as? NSDictionary,
      let quartz = CGRect(dictionaryRepresentation: bounds)
    else { return nil }
    // The window server's origin is the primary screen's top-left, with y growing downwards
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(
      x: quartz.minX, y: primaryHeight - quartz.maxY, width: quartz.width, height: quartz.height)
  }
}

/// The ring's window: four quarter pieces of rings with their own corner radii, masking one
/// gradient.
private final class Ring {
  /// One above app windows (level 0), below floating panels, menus and the menu bar
  private static let level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
  /// One above the windows Layers puts below the others, under the floating ones
  private static let levelBelow = NSWindow.Level(
    rawValue: Int(CGWindowLevelForKey(.backstopMenu)) + 1)

  private let window: NSWindow
  private let gradient = CAGradientLayer()
  /// Top-left, top-right, bottom-left, bottom-right: each clips its ring to its quarter
  private let pieces = (0..<4).map { _ in CALayer() }
  private let rings = (0..<4).map { _ in CALayer() }
  /// The frame the ring was last fitted to, in Cocoa coordinates; .zero when hidden
  private var shownFrame = CGRect.zero
  /// The corners the ring was last laid out with
  private var shownCorners: WindowCorners?

  init(width: CGFloat) {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = Self.level
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    let view = NSView()
    view.wantsLayer = true
    window.contentView = view
    // Unit coordinates with the origin at the bottom-left: top-left to bottom-right
    gradient.startPoint = CGPoint(x: 0, y: 1)
    gradient.endPoint = CGPoint(x: 1, y: 0)
    let mask = CALayer()
    gradient.mask = mask
    view.layer?.addSublayer(gradient)
    for (piece, ring) in zip(pieces, rings) {
      piece.masksToBounds = true
      ring.borderWidth = width
      ring.borderColor = CGColor.black  // only its shape counts
      ring.cornerCurve = .continuous
      piece.addSublayer(ring)
      mask.addSublayer(piece)
    }
  }

  func setColors(start: NSColor, end: NSColor) {
    gradient.colors = [start.cgColor, end.cgColor]
  }

  /// Fits the ring over `frame` with `corners`, and orders it in if it is out.
  func show(frame: CGRect, corners: WindowCorners, below: Bool) {
    let level = below ? Self.levelBelow : Self.level
    if window.level != level { window.level = level }
    let moved = frame != shownFrame
    if moved {
      shownFrame = frame
      window.setFrame(frame, display: false)
    }
    if moved || corners != shownCorners {
      shownCorners = corners
      layOut(corners)
    }
    if !window.isVisible { window.orderFrontRegardless() }
  }

  func hide() {
    window.orderOut(nil)
    shownFrame = .zero
  }

  /// Makes the next show fit the ring afresh: it is for another window.
  func forgetFrame() {
    shownFrame = .zero
  }

  /// Lays the four pieces over the window's content, each ring with its corner's radius. The
  /// content layer's origin is its bottom-left corner.
  private func layOut(_ corners: WindowCorners) {
    guard let bounds = window.contentView?.layer?.bounds else { return }
    let radii = [corners.topLeft, corners.topRight, corners.bottomLeft, corners.bottomRight]
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    gradient.frame = bounds
    gradient.mask?.frame = bounds
    for (index, (piece, ring)) in zip(pieces, rings).enumerated() {
      let right = index % 2 == 1
      let top = index < 2
      let quarter = CGRect(
        x: right ? bounds.width / 2 : 0, y: top ? bounds.height / 2 : 0, width: bounds.width / 2,
        height: bounds.height / 2)
      piece.frame = quarter
      ring.frame = bounds.offsetBy(dx: -quarter.minX, dy: -quarter.minY)
      ring.cornerRadius = radii[index]
    }
    CATransaction.commit()
  }
}
