// What the bar shows of AeroSpace, worked out from its `list-workspaces` and `list-windows`
// output: each screen's workspace chips, the one on screen, which screens are busy (their
// workspace has tiled windows, so the bar and the gaps go black), and the focused app.

/// An app as the bar keys it: by bundle id, or by process for the rare app without one.
public enum AppKey: Hashable, Sendable {
  case bundle(String)
  case process(Int32)

  /// The key for an app AeroSpace lists with `bundleId` (nil or empty when it has none) and
  /// `pid`.
  public init(bundleId: String?, pid: Int32) {
    if let bundleId, !bundleId.isEmpty {
      self = .bundle(bundleId)
    } else {
      self = .process(pid)
    }
  }
}

/// The focused window's app and title, as the bar shows them.
public struct FocusedApp: Equatable, Sendable {
  public let key: AppKey
  public let name: String
  public let title: String
}

/// AeroSpace's state as the bar shows it. Screens are numbered by their place in
/// NSScreen.screens, from 0.
public struct BarState: Equatable, Sendable {
  /// Each screen's chips: its workspaces with windows, and the one on screen, in AeroSpace's order.
  public private(set) var chips: [Int: [String]]
  /// The workspace on each screen.
  public private(set) var visible: [Int: String]
  /// The screens whose workspace has tiled windows.
  public private(set) var busyScreens: Set<Int>
  /// The screen with keyboard focus, nil when AeroSpace names none.
  public private(set) var focusedScreen: Int?
  /// The workspaces with tiled windows. Floating windows alone leave the wallpaper showing.
  public let tiled: Set<String>
  /// Each workspace's apps with windows on it, each once, in AeroSpace's order.
  public let apps: [String: [AppKey]]
  /// A process of each app, to find its icon by.
  public let pids: [AppKey: Int32]
  public let focused: FocusedApp?

  /// The state AeroSpace's listings give: `workspaces` on every screen, the names of those with
  /// windows (`used`), every window, and the focused one (nil when none is).
  public init(
    workspaces: [ListedWorkspace], used: Set<String>, windows: [ListedWindow],
    focused: ListedWindow?
  ) {
    var tiled: Set<String> = []
    var apps: [String: [AppKey]] = [:]
    var pids: [AppKey: Int32] = [:]
    for window in windows {
      if window.layout != "floating" { tiled.insert(window.workspace) }
      let key = AppKey(bundleId: window.bundleId, pid: window.pid)
      pids[key] = window.pid
      if !apps[window.workspace, default: []].contains(key) {
        apps[window.workspace, default: []].append(key)
      }
    }
    var chips: [Int: [String]] = [:]
    var visible: [Int: String] = [:]
    var busy: Set<Int> = []
    var focusedScreen: Int?
    for workspace in workspaces {
      let screen = workspace.monitorId - 1
      if workspace.isVisible {
        visible[screen] = workspace.name
        if tiled.contains(workspace.name) { busy.insert(screen) }
      }
      if workspace.isFocused { focusedScreen = screen }
      if workspace.isVisible || used.contains(workspace.name) {
        chips[screen, default: []].append(workspace.name)
      }
    }
    let focusedApp = focused.map { window in
      let key = AppKey(bundleId: window.bundleId, pid: window.pid)
      pids[key] = window.pid
      return FocusedApp(key: key, name: window.appName, title: window.title)
    }
    self.chips = chips
    self.visible = visible
    busyScreens = busy
    self.focusedScreen = focusedScreen
    self.tiled = tiled
    self.apps = apps
    self.pids = pids
    self.focused = focusedApp
  }

  /// Shows `workspace` as the one on `screen`, focused, before AeroSpace is asked again: so a
  /// second step goes on from it, and the backdrop changes at once.
  public mutating func show(_ workspace: String, onScreen screen: Int) {
    visible[screen] = workspace
    focusedScreen = screen
    if tiled.contains(workspace) {
      busyScreens.insert(screen)
    } else {
      busyScreens.remove(screen)
    }
  }

  /// The screen `workspace` comes to when it gains focus: the one whose chips last held it, else
  /// the focused screen.
  public func screen(receiving workspace: String) -> Int? {
    chips.first { $0.value.contains(workspace) }?.key ?? focusedScreen
  }

  /// The workspace `step` chips along from the one on `screen`, or nil past either end.
  public func workspace(steppingBy step: Int, onScreen screen: Int) -> String? {
    guard let names = chips[screen], let shown = visible[screen],
      let index = names.firstIndex(of: shown), names.indices.contains(index + step)
    else { return nil }
    return names[index + step]
  }
}
