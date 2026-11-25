// The bar across the top of every screen, over the macOS menu bar: at the menu bar's own height,
// which macOS keeps shown, so AeroSpace keeps the windows below both, and the menu bar never
// slides about. It is opaque, painting what is behind it: the black over a busy screen, else the
// wallpaper as the desktop fills it.
//
// Left: the screen's workspaces that have windows, plus the one on screen; the focused one in the
// accent colour. Each shows its name, then the icons of the apps with windows on it (ChipLayout).
// A click switches; scrolling over them (a wheel, or two fingers on a trackpad, one step per
// swipe) steps to the next or previous one on that screen. Then AeroSpace's mode while it is not
// the main one.
//
// Right: a button for the macOS menu bar, the focused window's app icon, name and title (on the
// focused screen), the status items (Status) and the clock. A click on the button or the app
// takes the bar away from over the menu bar under it, until the pointer has left the top and no
// menu is open; on the clock it opens Notification Center (Clock); on an item it does what the
// item says.
//
// Behind the windows, each screen whose workspace has tiled windows is black, the bar with it, so
// the gaps between them are; a workspace with none, or only floating ones, shows the whole
// wallpaper, the bar's items over it.
import AppKit
import NorenCore
import os

final class Bar: Part {
  /// Events come in bursts (a workspace change brings a focus change); one look covers a burst.
  private static let coalesceDelay = Duration.milliseconds(20)

  private let log = Logger(subsystem: "local.noren", category: "bar")
  private let config: BarConfig
  private let aeroSpace: AeroSpaceClient
  private let stayPointer: (String) -> Void
  let colors: BarColors
  let clock: Clock
  let icons = AppIcons()
  let status: Status?

  /// AeroSpace's state as last read; nil until it first is.
  private(set) var state: BarState?
  private(set) var mode = "main"
  private var screens: [BarScreen] = []
  /// Whether the bars are taken away from over the menu bar.
  private var uncovered = false
  /// The latest of this part's AeroSpace calls; each waits for the one before, so they run in
  /// order.
  private var following: Task<Void, Never>?
  private var refreshQueued = false
  /// Brings the bars back over the menu bar once it is left alone.
  private var watch: MenuBarWatch?
  /// Reads AeroSpace again when the focused window's title changes.
  private var titles: TitleWatch?
  private var reportedNoHeight = false

  init(
    config: BarConfig, showsStatus: Bool, aeroSpace: AeroSpaceClient,
    stayPointer: @escaping (String) -> Void
  ) {
    self.config = config
    self.aeroSpace = aeroSpace
    self.stayPointer = stayPointer
    colors = BarColors(config)
    clock = Clock(configuredKey: config.notificationCenterKey)
    status = showsStatus ? Status() : nil
  }

  func start() {
    status?.start { [unowned self] in redraw() }
    clock.start { [unowned self] in redraw() }
    titles = TitleWatch { [unowned self] in refresh() }
    watch = MenuBarWatch(
      inMenuBar: { [unowned self] in inMenuBar($0) }, cover: { [unowned self] in uncover(false) })
    buildScreens()
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [unowned self] _ in
      MainActor.assumeIsolated {
        buildScreens()
        refresh()
      }
    }
  }

  func handle(_ event: AeroSpaceEvent) {
    switch event {
    case .bindingTriggered:
      return
    case .modeChanged(let mode):
      if let mode { self.mode = mode }
      redraw()
      return
    case .focusedWorkspaceChanged(let workspace, _):
      if var state, let screen = state.screen(receiving: workspace) {
        state.show(workspace, onScreen: screen)
        self.state = state
        redraw()
      }
    case .connected:
      readMode()
    default:
      break
    }
    refresh()
  }

  // MARK: Actions from the bar's views

  /// Switches to `workspace` on screen `index`, showing it at once.
  func switchTo(_ workspace: String, onScreen index: Int) {
    guard var state else { return }
    state.show(workspace, onScreen: index)
    self.state = state
    redraw()
    stayPointer(workspace)
    follow { aeroSpace in
      _ = try await aeroSpace.run(["workspace", workspace])
    }
  }

  /// Takes the bars away from over the menu bar at once, so the next click reaches it, or fades
  /// them back in. Ordered out, not made to ignore clicks: the window server can be late to take a
  /// change of that back, and a click then falls through the bar.
  func uncover(_ uncovered: Bool) {
    self.uncovered = uncovered
    for screen in screens {
      if uncovered {
        screen.panel.orderOut(nil)
      } else {
        screen.fadeIn()
      }
    }
    if uncovered { watch?.start() }
  }

  // MARK: Drawing

  func redraw() {
    for screen in screens {
      screen.show(busy: state?.busyScreens.contains(screen.index) ?? false)
    }
  }

  private func buildScreens() {
    for screen in screens { screen.close() }
    let height = barHeight()
    screens = NSScreen.screens.enumerated().map { index, nsScreen in
      let screen = BarScreen(
        screen: nsScreen, index: index, minimumHeight: height, bar: self,
        busy: state?.busyScreens.contains(index) ?? false)
      if uncovered { screen.panel.orderOut(nil) }
      return screen
    }
  }

  /// The configured height, or the tallest menu bar among the screens, the one beside a notch.
  private func barHeight() -> CGFloat {
    if let height = config.height { return height }
    let tallest = NSScreen.screens.map { $0.frame.maxY - $0.visibleFrame.maxY }.max() ?? 0
    if tallest <= 0 && !reportedNoHeight {
      reportedNoHeight = true
      Problems.report(
        "macOS hides the menu bar on every screen, so the bar has no height of its own; "
          + "set bar.height")
    }
    return tallest
  }

  /// Whether `point`, in screen coordinates, is in some screen's menu bar.
  private func inMenuBar(_ point: NSPoint) -> Bool {
    screens.contains { screen in
      let bar = screen.panel.frame
      return (bar.minX...bar.maxX).contains(point.x) && (bar.minY...bar.maxY).contains(point.y)
    }
  }

  // MARK: Reading AeroSpace

  /// Runs `call` after this part's earlier AeroSpace calls; logs its failure.
  private func follow(_ call: @escaping (AeroSpaceClient) async throws -> Void) {
    following = Task { [previous = following, aeroSpace, log] in
      await previous?.value
      do {
        try await call(aeroSpace)
      } catch {
        log.error("\(error, privacy: .public)")
      }
    }
  }

  private func readMode() {
    follow { [unowned self] aeroSpace in
      let current = try await aeroSpace.run(["list-modes", "--current"])
      if let line = current.split(whereSeparator: \.isNewline).first { mode = String(line) }
      redraw()
    }
  }

  /// Reads AeroSpace's state afresh, once for a burst of calls.
  private func refresh() {
    guard !refreshQueued else { return }
    refreshQueued = true
    Task { [unowned self] in
      try? await Task.sleep(for: Self.coalesceDelay)
      refreshQueued = false
      follow { [unowned self] aeroSpace in
        let state = try await Self.readState(aeroSpace)
        self.state = state
        redraw()
        titles?.follow(pid: state.focused.flatMap { state.pids[$0.key] })
      }
    }
  }

  private static func readState(_ aeroSpace: AeroSpaceClient) async throws -> BarState {
    let workspaces = try await aeroSpace.run(
      ["list-workspaces", "--monitor", "all", "--json", "--format", ListedWorkspace.format],
      as: [ListedWorkspace].self)
    let used = try await aeroSpace.run(
      ["list-workspaces", "--monitor", "all", "--empty", "no", "--json"],
      as: [ListedWorkspaceName].self)
    let windows = try await aeroSpace.run(
      ["list-windows", "--all", "--json", "--format", ListedWindow.format],
      as: [ListedWindow].self)
    let focused: ListedFocusedWindow?
    do {
      focused = try await aeroSpace.run(
        ["list-windows", "--focused", "--json", "--format", ListedFocusedWindow.format],
        as: [ListedFocusedWindow].self
      ).first
    } catch AeroSpaceError.noWindowFocused {
      focused = nil
    }
    return BarState(
      workspaces: workspaces, used: Set(used.map(\.name)), windows: windows, focused: focused)
  }
}
