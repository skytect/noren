import NorenCore
import Testing

@Suite struct AeroSpaceConfigFactsTests {
  let toml = """
    [[on-window-detected]]
    if.app-id = 'com.example.calculator'
    run = 'layout floating'

    [[on-window-detected]]
    if.app-id = 'com.example.settings'
    run = ['layout floating']

    [[on-window-detected]]
    if.app-id = 'com.example.browser'
    if.window-title-regex-substring = 'Picture in Picture'
    run = 'layout floating'

    [[on-window-detected]]
    if.app-id = 'com.example.terminal'
    run = 'move-node-to-workspace 1'

    [mode.main.binding]
    alt-q = 'close'
    alt-shift-q = ['close --quit-if-last-window', 'workspace-back-and-forth']
    alt-enter = 'exec-and-forget open -a Terminal'

    [mode.service.binding]
    q = ['close', 'mode main']
    """

  @Test func `apps floated by app id alone float`() throws {
    let facts = try AeroSpaceConfigFacts(toml: toml)

    #expect(facts.floatingApps == ["com.example.calculator", "com.example.settings"])
  }

  @Test func `bindings that close a window, in any mode, close`() throws {
    let facts = try AeroSpaceConfigFacts(toml: toml)

    #expect(facts.closeBindings == ["alt-q", "alt-shift-q", "q"])
  }

  @Test func `a config without rules or modes has no facts`() throws {
    let facts = try AeroSpaceConfigFacts(toml: "start-at-login = true")

    #expect(facts.floatingApps.isEmpty)
    #expect(facts.closeBindings.isEmpty)
  }
}
