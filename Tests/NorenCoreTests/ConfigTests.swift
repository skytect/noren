import NorenCore
import Testing

@Suite struct ConfigTests {
  @Test func `an empty file runs every part with its defaults`() throws {
    let config = try Config(toml: "")

    #expect(config == Config())
    #expect(config.border.width == 2)
    #expect(config.bar.height == nil)
  }

  @Test func `kebab-case keys set their settings`() throws {
    let config = try Config(
      toml: """
        [bar]
        height = 54
        accent = "#89b4fa"
        notification-center-key = 80

        [border]
        width = 3
        color-end = "cba6f7"

        [stay]
        close-bindings = ["ctrl-q"]

        [strip]
        enable = false
        """)

    #expect(config.bar.height == 54)
    #expect(config.bar.accent == RGB(red: 0x89 / 255, green: 0xb4 / 255, blue: 0xfa / 255))
    #expect(config.bar.notificationCenterKey == 80)
    #expect(config.border.width == 3)
    #expect(config.border.colorEnd == RGB(red: 0xcb / 255, green: 0xa6 / 255, blue: 0xf7 / 255))
    #expect(config.stay.closeBindings == ["ctrl-q"])
    #expect(config.strip.enable == false)
  }

  @Test func `a drag moves windows with Alt unless another key is set`() throws {
    #expect(try Config(toml: "").drag.modifier == .alt)
    #expect(try Config(toml: "[drag]\nmodifier = \"ctrl\"").drag.modifier == .ctrl)
  }

  @Test func `a drag key noren does not know is refused, named`() {
    let error = #expect(throws: ConfigError.self) {
      try Config(toml: "[drag]\nmodifier = \"super\"")
    }

    #expect(error?.description.hasPrefix("drag.modifier:") == true)
  }

  @Test func `noren starts its AeroSpace unless told something else does`() throws {
    #expect(try Config(toml: "").aerospace.start)
    #expect(try Config(toml: "[aerospace]\nstart = false").aerospace.start == false)
  }

  @Test func `an unknown key is named with its table`() {
    #expect(throws: ConfigError("bar.colour: unknown key")) {
      try Config(toml: "[bar]\ncolour = \"ffffff\"")
    }
  }

  @Test func `an unknown table is named`() {
    #expect(throws: ConfigError("borders: unknown key")) {
      try Config(toml: "[borders]\nwidth = 3")
    }
  }

  @Test func `a malformed colour says what a colour looks like`() {
    #expect(throws: ConfigError("border.color: expected a colour as \"RRGGBB\"")) {
      try Config(toml: "[border]\ncolor = \"blue\"")
    }
  }

  @Test func `a value of the wrong type says what was expected`() {
    #expect(throws: ConfigError("border.width: expected a number")) {
      try Config(toml: "[border]\nwidth = \"wide\"")
    }
  }

  @Test func `a bar height of 0 is refused`() {
    #expect(throws: ConfigError("bar.height: must be more than 0")) {
      try Config(toml: "[bar]\nheight = 0")
    }
  }

  @Test func `a notification center key that is no key code is refused`() {
    #expect(throws: ConfigError("bar.notification-center-key: must be a key code, from 0 to 127")) {
      try Config(toml: "[bar]\nnotification-center-key = 128")
    }
  }

  @Test func `an opacity above 1 is refused`() {
    #expect(throws: ConfigError("border.opacity: must be from 0 to 1")) {
      try Config(toml: "[border]\nopacity = 1.5")
    }
  }

  @Test func `a TOML syntax error gives its line`() throws {
    let error = try #require(throws: ConfigError.self) {
      try Config(toml: "[bar]\nheight = = 3")
    }

    #expect(error.description.contains("2"))
  }

  @Test func `focus rules read their condition and commands`() throws {
    let config = try Config(
      toml: """
        [[focus-rule]]
        if = { app-id = "com.example.remote", title-regex = "^(alpha|beta)$" }
        enter = [["aerospace", "mode", "passthrough"]]
        leave = [["aerospace", "mode", "main"], ["/usr/bin/true"]]
        """)

    #expect(
      config.focusRules == [
        FocusRule(
          appId: "com.example.remote", titleRegex: "^(alpha|beta)$",
          enter: [["aerospace", "mode", "passthrough"]],
          leave: [["aerospace", "mode", "main"], ["/usr/bin/true"]])
      ])
  }

  @Test func `a focus rule without a condition is refused`() {
    #expect(throws: ConfigError("focus-rule[0].if: needs app-id, title-regex or both")) {
      try Config(toml: "[[focus-rule]]\nif = {}\nenter = [[\"true\"]]")
    }
  }

  @Test func `a focus rule's title expression must compile`() throws {
    let error = try #require(throws: ConfigError.self) {
      try Config(toml: "[[focus-rule]]\nif = { title-regex = \"(\" }")
    }

    #expect(error.description.hasPrefix("focus-rule[0].if.title-regex: not a regular expression"))
  }

  @Test func `display placements take a monitor or the iPad`() throws {
    let config = try Config(
      toml: """
        [[displays.place]]
        display = { vendor = 0x10ac, model = 41234, serial = 7 }
        position = "above"
        align = "left"

        [[displays.place]]
        display = "sidecar"
        position = "right"
        align = "top"
        """)

    #expect(
      config.displays.place == [
        DisplayPlacement(
          display: .monitor(vendor: 0x10ac, model: 41234, serial: 7), position: .above,
          align: .left),
        DisplayPlacement(display: .sidecar, position: .right, align: .top),
      ])
  }

  @Test func `an alignment that does not fit the position is refused`() {
    #expect(
      throws: ConfigError(
        "displays.place[0].align: must be one of [\"bottom\", \"center\", \"top\"] for right")
    ) {
      try Config(
        toml: "[[displays.place]]\ndisplay = \"sidecar\"\nposition = \"right\"\nalign = \"left\"")
    }
  }
}
