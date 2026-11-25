import NorenCore
import Testing

@Suite struct StayHistoryTests {
  let start = ContinuousClock.now

  func at(_ milliseconds: Int) -> ContinuousClock.Instant {
    start + .milliseconds(milliseconds)
  }

  /// A history that saw workspaces 1 and 2 occupied, then workspace 2's last window close: focus
  /// changed at 1000 ms, after which only 1 is occupied
  func afterClose(closeBindings: Set<String> = []) -> StayHistory {
    var history = StayHistory(closeBindings: closeBindings)
    _ = history.follow(nil, received: at(0), occupied: ["1", "2"], lookedAt: at(10))
    _ = history.follow(nil, received: at(1000), occupied: ["1"], lookedAt: at(1010))
    return history
  }

  let leftTwo = StayHistory.Change(workspace: "1", previous: "2")

  @Test func `focus goes back to a workspace whose last window closed`() {
    var history = afterClose()

    let back = history.follow(leftTwo, received: at(1020), occupied: ["1"], lookedAt: at(1030))

    #expect(back == "2")
  }

  @Test func `a key pressed just before the change keeps focus where it went`() {
    var history = afterClose()
    history.bindingTriggered("alt-shift-1", at: at(900))

    let back = history.follow(leftTwo, received: at(1020), occupied: ["1"], lookedAt: at(1030))

    #expect(back == nil)
  }

  @Test func `a close binding counts as a close, not as a key moving focus`() {
    var history = afterClose(closeBindings: ["alt-q", "ctrl-w"])
    history.bindingTriggered("ctrl-w", at: at(900))

    let back = history.follow(leftTwo, received: at(1020), occupied: ["1"], lookedAt: at(1030))

    #expect(back == "2")
  }

  @Test func `a key pressed over half a second before the change does not count`() {
    var history = afterClose()
    history.bindingTriggered("alt-shift-1", at: at(500))

    let back = history.follow(leftTwo, received: at(1020), occupied: ["1"], lookedAt: at(1030))

    #expect(back == "2")
  }

  @Test func `focus stays when the workspace left still has windows`() {
    var history = afterClose()

    let back = history.follow(
      leftTwo, received: at(1020), occupied: ["1", "2"], lookedAt: at(1030))

    #expect(back == nil)
  }

  @Test func `focus stays when the workspace left had no windows before`() {
    var history = StayHistory(closeBindings: [])
    _ = history.follow(nil, received: at(0), occupied: ["1"], lookedAt: at(10))

    let back = history.follow(leftTwo, received: at(1020), occupied: ["1"], lookedAt: at(1030))

    #expect(back == nil)
  }

  @Test func `what was occupied before is the latest look taken over the settle time earlier`() {
    var history = StayHistory(closeBindings: [])
    _ = history.follow(nil, received: at(0), occupied: ["1"], lookedAt: at(10))
    // A window opened on workspace 2
    _ = history.follow(nil, received: at(700), occupied: ["1", "2"], lookedAt: at(710))
    // The close's own focus change, 200 ms before the workspace change
    _ = history.follow(nil, received: at(800), occupied: ["1"], lookedAt: at(810))

    let back = history.follow(leftTwo, received: at(1000), occupied: ["1"], lookedAt: at(1010))

    #expect(back == "2")
  }

  @Test func `nothing is known about before once the history is forgotten`() {
    var history = afterClose()

    history.forget()
    let back = history.follow(leftTwo, received: at(1020), occupied: ["1"], lookedAt: at(1030))

    #expect(back == nil)
  }

  @Test func `focus stays when AeroSpace does not say what is occupied`() {
    var history = afterClose()

    let back = history.follow(leftTwo, received: at(1020), occupied: nil, lookedAt: at(1030))

    #expect(back == nil)
  }
}
