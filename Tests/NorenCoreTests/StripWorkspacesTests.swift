import NorenCore
import Testing

@Suite struct StripWorkspacesTests {
  func listed(_ names: [String], focused: String, monitorId: Int = 1) -> [ListedWorkspace] {
    names.map {
      ListedWorkspace(
        name: $0, monitorId: monitorId, isVisible: $0 == focused, isFocused: $0 == focused)
    }
  }

  @Test func `the strip holds the used workspaces and the focused one, on the focused screen`() {
    let strip = StripWorkspaces(
      listed: listed(["1", "2", "3", "4", "5"], focused: "2", monitorId: 2), used: ["1", "4"],
      withSpare: false)

    #expect(strip == StripWorkspaces(names: ["1", "2", "4"], focused: 1, monitorId: 2))
  }

  @Test func `a swipe's strip ends with the first empty workspace after the last used one`() {
    let strip = StripWorkspaces(
      listed: listed(["1", "2", "3", "4", "5", "6"], focused: "1"), used: ["1", "4"],
      withSpare: true)

    #expect(strip == StripWorkspaces(names: ["1", "4", "5"], focused: 0, monitorId: 1))
  }

  @Test func `a swipe's strip has no spare when the last workspace is used`() {
    let strip = StripWorkspaces(
      listed: listed(["1", "2", "3"], focused: "1"), used: ["1", "3"], withSpare: true)

    #expect(strip == StripWorkspaces(names: ["1", "3"], focused: 0, monitorId: 1))
  }

  @Test func `there is no strip when no workspace is focused`() {
    let strip = StripWorkspaces(
      listed: listed(["1", "2"], focused: "none"), used: ["1"], withSpare: true)

    #expect(strip == nil)
  }
}
