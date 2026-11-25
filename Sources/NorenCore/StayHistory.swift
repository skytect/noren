// Staying on a workspace when its last window closes (Noren/Stay.swift). macOS then activates
// some other app, and AeroSpace follows that app to its workspace, maybe on another screen
// (nikitabobko/AeroSpace#1097). So when the focused workspace changes, the workspace left had
// windows just before and has none now, and no AeroSpace key was pressed just before, focus goes
// back to it. A key pressed is what moved focus on purpose (moving the last window to another
// workspace empties its own); a key that closes windows is the exception, as it counts as a
// close.
//
// Not told apart: dragging the last window of a workspace onto another screen with the mouse also
// brings focus back to the emptied workspace.

/// The occupied workspaces looked at lately, and the last key pressed: what tells a workspace
/// emptied by a close from one emptied on purpose.
public struct StayHistory {
  public typealias Instant = ContinuousClock.Instant

  /// A focused workspace change.
  public struct Change: Equatable, Sendable {
    public let workspace: String
    public let previous: String

    public init(workspace: String, previous: String) {
      self.workspace = workspace
      self.previous = previous
    }
  }

  /// A key pressed within this long before a change is what made it.
  static let bindingWindow = Duration.milliseconds(500)
  /// The events of one close (focus changed, workspace changed) arrive in either order within
  /// this long, so what was occupied before a close is the latest look taken longer ago than this.
  static let settle = Duration.milliseconds(250)
  static let length = 8

  /// The bindings that close a window.
  public var closeBindings: Set<String>
  /// Looks at the occupied workspaces, oldest first
  private var looks: [(at: Instant, occupied: Set<String>)] = []
  private var lastBinding: Instant?

  public init(closeBindings: Set<String>) {
    self.closeBindings = closeBindings
  }

  /// Follows the binding `binding` pressed at `time`.
  public mutating func bindingTriggered(_ binding: String, at time: Instant) {
    if !closeBindings.contains(binding) { lastBinding = time }
  }

  /// Forgets every look, as when AeroSpace comes back: what was occupied meanwhile is unknown.
  public mutating func forget() {
    looks.removeAll()
  }

  /// Follows an event other than a binding, received at `received`. `occupied` is the look at the
  /// occupied workspaces taken for it at `lookedAt`, nil when AeroSpace did not answer; `change`
  /// is the event's focused workspace change, if it is one. Returns the workspace focus goes back
  /// to, if the change was a close.
  public mutating func follow(
    _ change: Change?, received: Instant, occupied: Set<String>?, lookedAt: Instant
  ) -> String? {
    let before = occupiedBefore(received)
    if let occupied {
      looks.append((lookedAt, occupied))
      if looks.count > Self.length { looks.removeFirst() }
    }
    guard let change, let before, let occupied, change.previous != change.workspace,
      before.contains(change.previous), !occupied.contains(change.previous)
    else { return nil }
    if let lastBinding, received - lastBinding < Self.bindingWindow { return nil }
    return change.previous
  }

  /// The latest look taken at least `settle` before `moment`; the oldest look when none was.
  private func occupiedBefore(_ moment: Instant) -> Set<String>? {
    looks.last { $0.at <= moment - Self.settle }?.occupied ?? looks.first?.occupied
  }
}
