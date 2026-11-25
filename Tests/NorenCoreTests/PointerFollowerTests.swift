import NorenCore
import Testing

@Suite struct PointerFollowerTests {
  @Test func `the pointer moves to a newly focused window`() {
    var follower = PointerFollower()

    #expect(follower.follow(.focusChanged(windowId: 4, workspace: "1")) == .window)
  }

  @Test func `the pointer moves to a newly focused screen`() {
    var follower = PointerFollower()

    #expect(follower.follow(.focusedMonitorChanged(workspace: "1", monitorId: 2)) == .monitor)
  }

  @Test func `a workspace picked with the pointer leaves the pointer through its switch`() {
    var follower = PointerFollower()
    follower.stay(forSwitchTo: "3")

    #expect(follower.follow(.focusedWorkspaceChanged(workspace: "3", previous: "1")) == nil)
    #expect(follower.follow(.focusedMonitorChanged(workspace: "3", monitorId: 2)) == nil)
    #expect(follower.follow(.focusChanged(windowId: 4, workspace: "3")) == nil)
  }

  @Test func `the pointer follows focus again after the picked switch's focus change`() {
    var follower = PointerFollower()
    follower.stay(forSwitchTo: "3")
    _ = follower.follow(.focusChanged(windowId: 4, workspace: "3"))

    #expect(follower.follow(.focusChanged(windowId: 5, workspace: "3")) == .window)
  }

  @Test func `a switch to another workspace than the picked one is followed`() {
    var follower = PointerFollower()
    follower.stay(forSwitchTo: "3")
    _ = follower.follow(.focusedWorkspaceChanged(workspace: "4", previous: "1"))

    #expect(follower.follow(.focusChanged(windowId: 4, workspace: "4")) == .window)
  }
}
