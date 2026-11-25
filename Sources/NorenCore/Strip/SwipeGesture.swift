// The three-finger swipe between workspaces, from trackpad frames to where the strip's selection
// is and which workspace it ends on. Like Hyprland's workspace swipe: the strip follows the
// fingers, and on lift-off it switches to the workspace it was dragged toward, or snaps back when
// the swipe was both too short and too slow. One swipe moves one workspace. Fingers moving left
// go to the next workspace, as content follows the fingers with natural scrolling.
//
// Distances are in trackpad widths (0 to 1 across the pad), times in seconds.

/// One finger on a trackpad, as MultitouchSupport reports it.
public struct Contact: Equatable, Sendable {
  /// MultitouchSupport's touch state: 1 start, 2 hover, 3 make, 4 touching, 5 break, 6 linger,
  /// 7 leave.
  public let state: Int
  public let x: Double
  public let y: Double

  public init(state: Int, x: Double, y: Double) {
    self.state = state
    self.x = x
    self.y = y
  }
}

/// One trackpad frame: how many fingers are on the pad, and where their middle is.
public struct TouchFrame: Equatable, Sendable {
  /// Which trackpad; a swipe follows the one it started on.
  public let device: Int
  public let fingers: Int
  public let x: Double
  public let y: Double
  public let time: Double

  public init(device: Int, fingers: Int, x: Double, y: Double, time: Double) {
    self.device = device
    self.fingers = fingers
    self.x = x
    self.y = y
    self.time = time
  }

  /// The frame of `contacts`: those making, holding or breaking contact count as on the pad;
  /// hovering and lingering ones do not.
  public init(device: Int, time: Double, contacts: [Contact]) {
    let down = contacts.filter { (3...5).contains($0.state) }
    let count = Double(max(down.count, 1))
    self.init(
      device: device, fingers: down.count, x: down.map(\.x).reduce(0, +) / count,
      y: down.map(\.y).reduce(0, +) / count, time: time)
  }
}

/// A swipe in progress, fed frame by frame.
public struct SwipeGesture {
  /// The strip for a swipe, asked of AeroSpace when three fingers land.
  public enum Prefetch: Equatable, Sendable {
    case pending
    case ready(StripWorkspaces)
    /// AeroSpace did not answer: this touch is not a swipe.
    case unavailable
  }

  /// What a frame calls for.
  public enum Step: Equatable, Sendable {
    /// Three fingers landed: ask AeroSpace for the strip now, so it is ready by the time the
    /// fingers have moved.
    case armed
    /// The swipe took its direction: show this strip, the selection on the focused workspace.
    case began(StripWorkspaces)
    /// The selection follows the fingers to `position`, in slots from the strip's first
    /// workspace; a whole number is on a workspace.
    case moved(position: Double)
    /// The fingers lifted: the selection settles on slot `target`, and focus switches to
    /// `workspace`, nil when it stays.
    case ended(target: Int, workspace: String?)
  }

  static let fingers = 3
  /// Travel before the swipe takes a direction, or is let go as a vertical one
  static let lockTravel = 0.02
  /// Travel for one whole workspace
  static let stepTravel = 0.30
  /// Of a workspace: a shorter drag snaps back, unless flicked (Hyprland's ratio)
  static let cancelRatio = 0.15
  /// Widths per second at lift-off that commit however short the drag
  static let flickSpeed = 1.0
  /// Workspaces the strip gives past its ends
  static let rubberBand = 0.25

  private enum Phase {
    /// Not three fingers down
    case idle
    /// Three fingers down, no direction yet
    case armed
    /// Dragging the strip
    case tracking(StripWorkspaces)
    /// Not a swipe; waits for every finger to lift
    case ignored
  }

  private var phase = Phase.idle
  private var device = 0
  private var startX = 0.0
  private var startY = 0.0
  private var lastX = 0.0
  private var lastTime = 0.0
  /// Smoothed, in widths per second
  private var velocity = 0.0
  /// Workspaces dragged, toward the next one
  private var offset = 0.0

  public init() {}

  /// Whether the strip is following fingers now.
  public var isTracking: Bool {
    if case .tracking = phase { return true }
    return false
  }

  /// Forgets any swipe in progress, as when the trackpads are attached afresh.
  public mutating func reset() {
    phase = .idle
  }

  /// Follows `frame`, with the strip AeroSpace gave for this touch so far.
  public mutating func follow(_ frame: TouchFrame, prefetch: Prefetch) -> [Step] {
    switch phase {
    case .idle: break
    default: guard frame.device == device else { return [] }
    }
    switch phase {
    case .idle:
      guard frame.fingers == Self.fingers else { return [] }
      phase = .armed
      device = frame.device
      (startX, lastX, startY, lastTime, velocity) = (frame.x, frame.x, frame.y, frame.time, 0)
      return [.armed]
    case .ignored:
      if frame.fingers == 0 { phase = .idle }
      return []
    case .armed:
      guard frame.fingers == Self.fingers else {
        phase = frame.fingers == 0 ? .idle : .ignored
        return []
      }
      let dx = frame.x - startX
      let dy = frame.y - startY
      if abs(dy) > Self.lockTravel && abs(dy) > abs(dx) {
        phase = .ignored
        return []
      }
      guard abs(dx) >= Self.lockTravel else { return [] }
      switch prefetch {
      case .pending:
        return []
      case .unavailable:
        phase = .ignored
        return []
      case .ready(let strip):
        // A swipe that just took its direction is tracked from this frame on
        phase = .tracking(strip)
        offset = 0
        return [.began(strip)] + track(frame, strip)
      }
    case .tracking(let strip):
      return track(frame, strip)
    }
  }

  private mutating func track(_ frame: TouchFrame, _ strip: StripWorkspaces) -> [Step] {
    if frame.fingers == Self.fingers {
      if frame.time > lastTime {
        velocity = 0.5 * (frame.x - lastX) / (frame.time - lastTime) + 0.5 * velocity
      }
      lastX = frame.x
      lastTime = frame.time
      // One workspace each way at most, with some give past the ends of the strip
      let low = max(-1, -Double(strip.focused))
      let high = min(1, Double(strip.names.count - 1 - strip.focused))
      offset = Self.rubberBanded(-(frame.x - startX) / Self.stepTravel, low: low, high: high)
      return [.moved(position: Double(strip.focused) + offset)]
    }
    // Lifting the fingers ends the swipe; a fourth finger calls it off
    phase = frame.fingers == 0 ? .idle : .ignored
    var target = strip.focused
    if frame.fingers < Self.fingers {
      target += Self.direction(offset: offset, velocity: velocity)
    }
    if !strip.names.indices.contains(target) { target = strip.focused }
    return [.ended(target: target, workspace: target == strip.focused ? nil : strip.names[target])]
  }

  /// Which way a swipe lifted with these commits: 1 to the next workspace, -1 to the previous, 0
  /// to snap back. A flick commits in its own direction whatever the distance.
  private static func direction(offset: Double, velocity: Double) -> Int {
    let flick = -velocity  // toward the next workspace
    if abs(flick) >= flickSpeed { return flick > 0 ? 1 : -1 }
    if abs(offset) >= cancelRatio { return offset > 0 ? 1 : -1 }
    return 0
  }

  private static func rubberBanded(_ offset: Double, low: Double, high: Double) -> Double {
    if offset > high { return high + rubberBand * (1 - 1 / (1 + (offset - high) / rubberBand)) }
    if offset < low { return low - rubberBand * (1 - 1 / (1 + (low - offset) / rubberBand)) }
    return offset
  }
}
