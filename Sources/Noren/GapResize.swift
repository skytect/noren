// Dragging the gap between tiled windows resizes them (GapHit says which), as Hyprland's
// resize_on_border does; where gaps cross, both ways. Drag's event tap hands over a plain press
// that lands on no window, and the drag after it; each move becomes `aerospace resize` on the
// window left of or above the gap, which AeroSpace takes from or gives to its neighbours. Moves
// come faster than AeroSpace answers, so they add up while a resize is under way and go as one.
//
// Over a gap the pointer is a resize arrow. Only the app under the pointer may set the cursor, the
// desktop here, unless the window server lets noren's connection set it in the background
// (SkyLight's SetsCursorInBackground, the property other window managers set for the same).
//
// The tiled windows on the visible workspaces are listed again after each AeroSpace event; their
// frames are read from the window server at each look, so they are never stale.
import AppKit
import NorenCore
import os

final class GapResize {
  private let log = Logger(subsystem: "local.noren", category: "gaps")
  private let aeroSpace: AeroSpaceClient
  /// The tiled windows on the visible workspaces: AeroSpace's id and the window server's
  private var tiled: [(id: UInt32, nativeId: CGWindowID)] = []
  /// The latest listing; each waits for the one before
  private var listing: Task<Void, Never>?
  /// The resize under way: its gap, and the pointer when it last moved
  private var resizing: (hit: GapHit, last: CGPoint)?
  /// Points dragged and not yet sent to AeroSpace
  private var pending = CGVector.zero
  /// Sending `pending`, nil when nothing is
  private var sending: Task<Void, Never>?
  /// Whether noren set the cursor, and so must give it back
  private var cursorSet = false

  init(aeroSpace: AeroSpaceClient) {
    self.aeroSpace = aeroSpace
  }

  func start() {
    SkyLight.shared?.setCursorInBackground()
    NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [unowned self] _ in
      hover(at: Self.pointer)
    }
  }

  /// Lists the tiled windows again: AeroSpace may have moved, opened or closed some
  func handle(_ event: AeroSpaceEvent) {
    if case .modeChanged = event { return }
    listing = Task { [previous = listing] in
      await previous?.value
      do {
        let windows = try await aeroSpace.run(
          ["list-windows", "--workspace", "visible", "--json", "--format", ListedWindow.format],
          as: [ListedWindow].self)
        tiled = windows.compactMap { window in
          guard window.layout.hasSuffix("_tiles") || window.layout.hasSuffix("_accordion"),
            let nativeId = window.nativeId
          else { return nil }
          return (window.id, nativeId)
        }
      } catch {
        log.error("could not list the windows: \(error, privacy: .public)")
      }
    }
  }

  /// The gap at `point` (the window server's coordinates), if a press there resizes
  func hit(at point: CGPoint) -> GapHit? {
    GapHit(at: point, among: tiles())
  }

  /// Starts resizing `hit`'s windows from `point`
  func begin(_ hit: GapHit, at point: CGPoint) {
    resizing = (hit, point)
    showCursor(for: hit)
  }

  var isResizing: Bool { resizing != nil }

  /// Follows the pointer to `point`
  func drag(to point: CGPoint) {
    guard let (hit, last) = resizing else { return }
    resizing = (hit, point)
    pending.dx += hit.width == nil ? 0 : point.x - last.x
    pending.dy += hit.height == nil ? 0 : point.y - last.y
    showCursor(for: hit)
    if sending == nil { send(hit) }
  }

  func end() {
    resizing = nil
    hover(at: Self.pointer)
  }

  /// Sends what was dragged until nothing more is, whole points at a time
  private func send(_ hit: GapHit) {
    sending = Task {
      while true {
        let dx = pending.dx.rounded(.towardZero)
        let dy = pending.dy.rounded(.towardZero)
        guard dx != 0 || dy != 0 else { break }
        pending.dx -= dx
        pending.dy -= dy
        if let id = hit.width, dx != 0 { await resize(id, "width", dx) }
        if let id = hit.height, dy != 0 { await resize(id, "height", dy) }
      }
      sending = nil
    }
  }

  private func resize(_ window: UInt32, _ dimension: String, _ by: CGFloat) async {
    let amount = (by > 0 ? "+" : "-") + String(Int(abs(by)))
    do {
      _ = try await aeroSpace.run(["resize", "--window-id", String(window), dimension, amount])
    } catch {
      log.error("could not resize window \(window): \(error, privacy: .public)")
    }
  }

  /// Shows the resize arrow over a gap, and gives the cursor back once off it
  private func hover(at point: CGPoint) {
    guard resizing == nil else { return }
    if let hit = hit(at: point) {
      showCursor(for: hit)
    } else if cursorSet {
      cursorSet = false
      NSCursor.arrow.set()
    }
  }

  private func showCursor(for hit: GapHit) {
    cursorSet = true
    switch (hit.width, hit.height) {
    case (.some, .some): NSCursor.frameResize(position: .bottomRight, directions: .all).set()
    case (.some, nil): NSCursor.columnResize.set()
    default: NSCursor.rowResize.set()
    }
  }

  /// The tiled windows on screen, with their frames as the window server has them now
  private func tiles() -> [GapHit.Tile] {
    guard !tiled.isEmpty else { return [] }
    var ids = tiled.map { UnsafeRawPointer(bitPattern: UInt($0.nativeId)) }
    guard let array = CFArrayCreate(nil, &ids, ids.count, nil),
      let infos = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]]
    else { return [] }
    let byNative = Dictionary(tiled.map { ($0.nativeId, $0.id) }, uniquingKeysWith: { a, _ in a })
    return infos.compactMap { info in
      guard info[kCGWindowIsOnscreen as String] as? Bool == true,
        let number = info[kCGWindowNumber as String] as? CGWindowID, let id = byNative[number],
        let bounds = info[kCGWindowBounds as String] as? NSDictionary,
        let frame = CGRect(dictionaryRepresentation: bounds)
      else { return nil }
      return GapHit.Tile(id: id, frame: frame)
    }
  }

  /// The pointer in the window server's coordinates
  private static var pointer: CGPoint {
    CGEvent(source: nil)?.location ?? .zero
  }
}
