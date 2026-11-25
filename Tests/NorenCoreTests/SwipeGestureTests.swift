import NorenCore
import Testing

@Suite struct SwipeGestureTests {
  /// Workspaces 1 to 3, with 2 focused
  let middle = StripWorkspaces(names: ["1", "2", "3"], focused: 1, monitorId: 1)

  func frame(_ x: Double, _ time: Double, fingers: Int = 3, y: Double = 0.5, device: Int = 7)
    -> TouchFrame
  {
    TouchFrame(device: device, fingers: fingers, x: x, y: y, time: time)
  }

  /// The selection's position, when `steps` move it
  func position(_ steps: [SwipeGesture.Step]) -> Double? {
    for case .moved(let position) in steps { return position }
    return nil
  }

  @Test func `three fingers landing ask for the strip`() {
    var gesture = SwipeGesture()

    #expect(gesture.follow(frame(0.5, 0), prefetch: .unavailable) == [.armed])
  }

  @Test func `the strip appears once the fingers take a direction and follows them`() throws {
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.5, 0), prefetch: .pending)

    let steps = gesture.follow(frame(0.47, 0.1), prefetch: .ready(middle))

    #expect(steps.first == .began(middle))
    // 0.03 of the pad is a tenth of a workspace toward the next
    #expect(abs(try #require(position(steps)) - 1.1) < 1e-9)
  }

  @Test func `a long enough slow swipe to the left switches to the next workspace`() {
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.5, 0), prefetch: .ready(middle))
    _ = gesture.follow(frame(0.47, 0.1), prefetch: .ready(middle))
    _ = gesture.follow(frame(0.44, 0.2), prefetch: .ready(middle))

    let steps = gesture.follow(frame(0.44, 0.3, fingers: 0), prefetch: .ready(middle))

    #expect(steps == [.ended(target: 2, workspace: "3")])
  }

  @Test func `a swipe to the right switches to the previous workspace`() {
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.5, 0), prefetch: .ready(middle))
    _ = gesture.follow(frame(0.56, 0.1), prefetch: .ready(middle))

    let steps = gesture.follow(frame(0.56, 0.2, fingers: 0), prefetch: .ready(middle))

    #expect(steps == [.ended(target: 0, workspace: "1")])
  }

  @Test func `a short slow swipe snaps back`() {
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.5, 0), prefetch: .ready(middle))
    _ = gesture.follow(frame(0.47, 0.1), prefetch: .ready(middle))

    let steps = gesture.follow(frame(0.47, 0.2, fingers: 0), prefetch: .ready(middle))

    #expect(steps == [.ended(target: 1, workspace: nil)])
  }

  @Test func `a short quick flick switches anyway`() {
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.5, 0), prefetch: .ready(middle))
    _ = gesture.follow(frame(0.47, 0.01), prefetch: .ready(middle))

    let steps = gesture.follow(frame(0.47, 0.02, fingers: 0), prefetch: .ready(middle))

    #expect(steps == [.ended(target: 2, workspace: "3")])
  }

  @Test func `one swipe moves the strip one workspace at most`() throws {
    let first = StripWorkspaces(names: ["1", "2", "3"], focused: 0, monitorId: 1)
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.8, 0), prefetch: .ready(first))

    let steps = gesture.follow(frame(0.2, 0.5), prefetch: .ready(first))
    let lifted = gesture.follow(frame(0.2, 0.6, fingers: 0), prefetch: .ready(first))

    // Two workspaces' travel: one, plus 0.25 * (1 - 1 / 5) of give
    #expect(abs(try #require(position(steps)) - 1.2) < 1e-9)
    #expect(lifted == [.ended(target: 1, workspace: "2")])
  }

  @Test func `one swipe moves the strip one workspace back at most`() throws {
    let last = StripWorkspaces(names: ["1", "2", "3"], focused: 2, monitorId: 1)
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.2, 0), prefetch: .ready(last))

    let steps = gesture.follow(frame(0.8, 0.5), prefetch: .ready(last))
    let lifted = gesture.follow(frame(0.8, 0.6, fingers: 0), prefetch: .ready(last))

    // Two workspaces' travel back: one, plus 0.25 * (1 - 1 / 5) of give
    #expect(abs(try #require(position(steps)) - 0.8) < 1e-9)
    #expect(lifted == [.ended(target: 1, workspace: "2")])
  }

  @Test func `swiping past the last workspace gives a little and stays`() throws {
    let last = StripWorkspaces(names: ["1", "2", "3"], focused: 2, monitorId: 1)
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.5, 0), prefetch: .ready(last))

    let steps = gesture.follow(frame(0.35, 0.5), prefetch: .ready(last))
    let lifted = gesture.follow(frame(0.35, 0.6, fingers: 0), prefetch: .ready(last))

    // Half a workspace past the end gives 0.25 * (1 - 1 / 3)
    #expect(abs(try #require(position(steps)) - 2.1666667) < 1e-6)
    #expect(lifted == [.ended(target: 2, workspace: nil)])
  }

  @Test func `a fourth finger calls the swipe off`() {
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.5, 0), prefetch: .ready(middle))
    _ = gesture.follow(frame(0.4, 0.2), prefetch: .ready(middle))

    let steps = gesture.follow(frame(0.4, 0.3, fingers: 4), prefetch: .ready(middle))

    #expect(steps == [.ended(target: 1, workspace: nil)])
  }

  @Test func `a vertical swipe is let go until every finger lifts`() {
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.5, 0), prefetch: .ready(middle))

    #expect(gesture.follow(frame(0.5, 0.1, y: 0.55), prefetch: .ready(middle)) == [])
    #expect(gesture.follow(frame(0.3, 0.2), prefetch: .ready(middle)) == [])
    #expect(gesture.follow(frame(0.3, 0.3, fingers: 0), prefetch: .ready(middle)) == [])
    #expect(gesture.follow(frame(0.3, 0.4), prefetch: .ready(middle)) == [.armed])
  }

  @Test func `the swipe waits for AeroSpace's answer and then catches up with the fingers`() throws
  {
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.5, 0), prefetch: .pending)
    let waiting = gesture.follow(frame(0.47, 0.1), prefetch: .pending)

    let steps = gesture.follow(frame(0.44, 0.2), prefetch: .ready(middle))

    #expect(waiting == [])
    #expect(steps.first == .began(middle))
    #expect(abs(try #require(position(steps)) - 1.2) < 1e-9)
  }

  @Test func `without AeroSpace's answer the touch is no swipe`() {
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.5, 0), prefetch: .pending)

    #expect(gesture.follow(frame(0.4, 0.1), prefetch: .unavailable) == [])
    #expect(gesture.follow(frame(0.3, 0.2), prefetch: .ready(middle)) == [])
  }

  @Test func `another trackpad's frames do not touch a swipe in progress`() {
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.5, 0), prefetch: .ready(middle))
    _ = gesture.follow(frame(0.47, 0.1), prefetch: .ready(middle))

    #expect(gesture.follow(frame(0.5, 0.2, fingers: 0, device: 8), prefetch: .ready(middle)) == [])
    #expect(gesture.isTracking)
  }

  @Test func `attaching afresh forgets the swipe in progress`() {
    var gesture = SwipeGesture()
    _ = gesture.follow(frame(0.5, 0), prefetch: .ready(middle))
    _ = gesture.follow(frame(0.47, 0.1), prefetch: .ready(middle))

    gesture.reset()

    #expect(!gesture.isTracking)
    #expect(gesture.follow(frame(0.4, 0.2), prefetch: .ready(middle)) == [.armed])
  }

  @Test func `only fingers making or holding contact count, at their middle`() {
    let frame = TouchFrame(
      device: 1, time: 0,
      contacts: [
        Contact(state: 2, x: 0.9, y: 0.9), Contact(state: 3, x: 0.2, y: 0.1),
        Contact(state: 4, x: 0.4, y: 0.2), Contact(state: 5, x: 0.6, y: 0.3),
        Contact(state: 7, x: 0.9, y: 0.9),
      ])

    #expect(frame.fingers == 3)
    #expect(abs(frame.x - 0.4) < 1e-9 && abs(frame.y - 0.2) < 1e-9)
  }
}
