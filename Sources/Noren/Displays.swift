// Where the screens sit, and what they show.
//
// Layout: each display a [[displays.place]] rule matches is kept beside the built-in screen,
// where the rule says (DisplayPlacement in NorenCore). It is put back after every display
// reconfiguration, System Settings changes included. Only displays that are online and out of
// place are moved, so the move's own reconfiguration does not loop. With the lid closed, or the
// built-in screen mirrored, there is nothing to arrange around.
//
// Wallpaper: when set, it goes on every screen at start and whenever screens change, so a screen
// that arrives later (an iPad) gets it too. NSWorkspace needs no Automation permission, unlike
// scripting Finder or System Events.
import AppKit
import NorenCore
import os

final class Displays: Part {
  private let log = Logger(subsystem: "local.noren", category: "displays")
  private let rules: [DisplayPlacement]
  private let wallpaper: URL?
  /// Reconfiguration arrives as a burst of callbacks; the layout is applied this long after the
  /// last
  private let settleDelay = Duration.milliseconds(500)
  /// The arrangement waiting for the burst to end, replaced by each callback
  private var settling: Task<Void, Never>?

  init(config: DisplaysConfig) {
    rules = config.place
    wallpaper = config.wallpaper.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
  }

  func start() {
    arrange()
    // The callback may come on any thread, and carries this part as its context; parts live as
    // long as noren does, so it is not retained
    let context = Unmanaged.passUnretained(self).toOpaque()
    CGDisplayRegisterReconfigurationCallback(
      { _, flags, context in
        guard !flags.contains(.beginConfigurationFlag), let context else { return }
        let address = UInt(bitPattern: context)
        Task { @MainActor in
          guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
          Unmanaged<Displays>.fromOpaque(pointer).takeUnretainedValue().reconfigured()
        }
      }, context)
    setWallpaper()
    _ = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [unowned self] _ in
      MainActor.assumeIsolated { setWallpaper() }
    }
  }

  private func reconfigured() {
    settling?.cancel()
    settling = Task {
      do {
        try await Task.sleep(for: settleDelay)
      } catch {
        return
      }
      arrange()
    }
  }

  // MARK: Layout

  private func arrange() {
    var ids = [CGDirectDisplayID](repeating: kCGNullDirectDisplay, count: 16)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return }
    let online = ids.prefix(Int(count))
    guard let builtin = online.first(where: { CGDisplayIsBuiltin($0) != 0 }),
      CGDisplayIsInMirrorSet(builtin) == 0
    else { return }
    let others = online.filter { $0 != builtin }.map {
      OnlineDisplay(
        id: $0, vendor: CGDisplayVendorNumber($0), model: CGDisplayModelNumber($0),
        serial: CGDisplaySerialNumber($0), bounds: CGDisplayBounds($0))
    }
    let moves = DisplayPlacement.moves(
      placing: others, beside: CGDisplayBounds(builtin), by: rules)
    guard !moves.isEmpty else { return }

    var configuration: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&configuration) == .success else { return }
    for move in moves {
      CGConfigureDisplayOrigin(
        configuration, move.id, Int32(move.origin.x), Int32(move.origin.y))
    }
    let error = CGCompleteDisplayConfiguration(configuration, .permanently)
    if error == .success {
      log.info("arranged \(moves.count) screen(s)")
    } else {
      log.error("could not move the screens (error \(error.rawValue))")
    }
  }

  // MARK: Wallpaper

  private func setWallpaper() {
    guard let wallpaper else { return }
    let workspace = NSWorkspace.shared
    for screen in NSScreen.screens where workspace.desktopImageURL(for: screen) != wallpaper {
      do {
        try workspace.setDesktopImageURL(wallpaper, for: screen, options: [:])
      } catch {
        log.error(
          "could not set the wallpaper on \(screen.localizedName, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }
}
