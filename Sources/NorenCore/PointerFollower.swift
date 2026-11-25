// The pointer follows keyboard focus (Noren/Pointer.swift): it moves to the middle of a newly
// focused window, unless it is already inside it (so focusing by mouse leaves it be), and to the
// middle of a newly focused screen. A workspace chosen with the pointer, on the bar, leaves the
// pointer where it is: the focus events of that one switch are skipped. AeroSpace's
// on-focus-changed callbacks cannot tell the two apart, so noren moves the pointer instead.

/// Where the pointer goes for each AeroSpace event.
public struct PointerFollower {
  /// A `move-mouse` target.
  public enum Target: String, Sendable {
    case window = "window-lazy-center"
    case monitor = "monitor-lazy-center"
  }

  /// The workspace the pointer stays for: its switch's focus events are skipped, until the first
  /// focus change into it or a change to another workspace
  private var stayFor: String?

  public init() {}

  /// Leaves the pointer where it is for the switch to `workspace` about to be made.
  public mutating func stay(forSwitchTo workspace: String) {
    stayFor = workspace
  }

  /// Where the pointer moves for `event`; nil when it stays.
  public mutating func follow(_ event: AeroSpaceEvent) -> Target? {
    switch event {
    case .focusedWorkspaceChanged(let workspace, _):
      if workspace != stayFor { stayFor = nil }
      return nil
    case .focusChanged(_, let workspace):
      defer { stayFor = nil }
      return workspace == stayFor ? nil : .window
    case .focusedMonitorChanged(let workspace, _):
      if workspace == stayFor { return nil }
      stayFor = nil
      return .monitor
    default:
      return nil
    }
  }
}
