import NorenCore
import Testing

@Suite struct FocusRuleTrackerTests {
  let remote = FocusRule(
    appId: "com.example.remote", titleRegex: "^(alpha|beta)$",
    enter: [["aerospace", "mode", "passthrough"]], leave: [["aerospace", "mode", "main"]])
  let session = FocusedWindow(appId: "com.example.remote", title: "alpha")
  let otherSession = FocusedWindow(appId: "com.example.remote", title: "beta")
  let remoteSettings = FocusedWindow(appId: "com.example.remote", title: "Settings")
  let editor = FocusedWindow(appId: "com.example.editor", title: "alpha")

  @Test func `focusing a matching window runs its enter commands`() {
    var tracker = FocusRuleTracker(rules: [remote])

    #expect(tracker.focus(session) == [["aerospace", "mode", "passthrough"]])
  }

  @Test func `moving between matching windows runs nothing`() {
    var tracker = FocusRuleTracker(rules: [remote])
    _ = tracker.focus(session)

    #expect(tracker.focus(otherSession) == [])
  }

  @Test func `leaving for a window of the same app with another title runs the leave commands`() {
    var tracker = FocusRuleTracker(rules: [remote])
    _ = tracker.focus(session)

    #expect(tracker.focus(remoteSettings) == [["aerospace", "mode", "main"]])
  }

  @Test func `the same title in another app does not match`() {
    var tracker = FocusRuleTracker(rules: [remote])

    #expect(tracker.focus(editor) == [])
  }

  @Test func `focus moving to no window leaves`() {
    var tracker = FocusRuleTracker(rules: [remote])
    _ = tracker.focus(session)

    #expect(tracker.focus(nil) == [["aerospace", "mode", "main"]])
  }

  @Test func `leaves run before enters`() {
    let browser = FocusRule(
      appId: "com.example.editor", titleRegex: nil, enter: [["enter-editor"]],
      leave: [["leave-editor"]])
    var tracker = FocusRuleTracker(rules: [remote, browser])
    _ = tracker.focus(session)

    #expect(tracker.focus(editor) == [["aerospace", "mode", "main"], ["enter-editor"]])
  }

  @Test func `a reset outside every rule runs every leave`() {
    var tracker = FocusRuleTracker(rules: [remote])

    #expect(tracker.reset(editor) == [["aerospace", "mode", "main"]])
  }

  @Test func `a reset inside a rule runs its enter, and later moves are transitions again`() {
    var tracker = FocusRuleTracker(rules: [remote])

    #expect(tracker.reset(session) == [["aerospace", "mode", "passthrough"]])
    #expect(tracker.focus(otherSession) == [])
  }
}
