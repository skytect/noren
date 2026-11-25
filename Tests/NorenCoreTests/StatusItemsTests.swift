import NorenCore
import Testing

@Suite struct StatusItemsTests {
  @Test func `items run left to right from microphone to battery`() {
    var readings = StatusReadings()
    readings.microphone = true
    readings.camera = true
    readings.tailscaleApp = "io.tailscale.ipn.macos"
    readings.wiFi = .connected
    readings.output = .init(volume: 0.5, muted: false)
    readings.battery = .init(percent: 80, onPower: false)

    #expect(
      readings.items.map(\.symbol) == [
        "mic.fill", "video.fill", "circle.grid.3x3", "wifi", "speaker.wave.3.fill",
        "battery.75percent",
      ])
  }

  @Test func `on Ethernet, Wi-Fi without a network is hidden`() {
    var readings = StatusReadings()
    readings.wired = true
    readings.wiFi = .disconnected

    #expect(readings.items.map(\.symbol) == ["cable.connector"])
  }

  @Test func `without Ethernet, Wi-Fi without a network warns`() {
    var readings = StatusReadings()
    readings.wiFi = .disconnected

    #expect(readings.items.first?.symbol == "wifi.exclamationmark")
    #expect(readings.items.first?.tone == .warn)
  }

  @Test func `Tailscale connected is a filled grid that opens its app`() {
    var readings = StatusReadings()
    readings.tailscaleApp = "io.tailscale.ipn.macsys"
    readings.tailscaleConnected = true

    #expect(
      readings.items == [
        StatusItem(
          symbol: "circle.grid.3x3.fill", action: .launch(bundleId: "io.tailscale.ipn.macsys"))
      ])
  }

  @Test func `a muted output is dim and has no level`() {
    var readings = StatusReadings()
    readings.output = .init(volume: 0.5, muted: true)

    #expect(
      readings.items == [
        StatusItem(
          symbol: "speaker.slash.fill", tone: .dim,
          action: .open(url: "x-apple.systempreferences:com.apple.Sound-Settings.extension"))
      ])
  }

  @Test func `a volume of zero is silent`() {
    var readings = StatusReadings()
    readings.output = .init(volume: 0, muted: false)

    #expect(readings.items.first?.symbol == "speaker.slash.fill")
  }

  @Test func `an output without a volume control shows no level`() {
    var readings = StatusReadings()
    readings.output = .init(volume: nil, muted: false)

    #expect(readings.items.first?.symbol == "speaker.wave.3.fill")
    #expect(readings.items.first?.level == nil)
  }

  @Test func `a battery at 20 percent off power warns, with its percentage`() {
    var readings = StatusReadings()
    readings.battery = .init(percent: 20, onPower: false)

    #expect(readings.items.first?.symbol == "battery.25percent")
    #expect(readings.items.first?.tone == .warn)
    #expect(readings.items.first?.text == "20%")
  }

  @Test func `a battery on power shows the bolt and does not warn`() {
    var readings = StatusReadings()
    readings.battery = .init(percent: 5, onPower: true)

    #expect(readings.items.first?.symbol == "battery.100percent.bolt")
    #expect(readings.items.first?.tone == .normal)
  }

  @Test(arguments: [
    (88, "battery.100percent"), (87, "battery.75percent"), (63, "battery.75percent"),
    (62, "battery.50percent"), (38, "battery.50percent"), (37, "battery.25percent"),
    (13, "battery.25percent"), (12, "battery.0percent"),
  ])
  func `the battery symbol steps at 13, 38, 63 and 88 percent`(percent: Int, symbol: String) {
    var readings = StatusReadings()
    readings.battery = .init(percent: percent, onPower: false)

    #expect(readings.items.first?.symbol == symbol)
  }

  @Test func `the battery percentage rounds the capacity's share`() {
    #expect(StatusReadings.Battery.percent(current: 4_321, max: 5_000) == 86)
    #expect(StatusReadings.Battery.percent(current: 1, max: 200) == 1)
  }

  @Test func `a battery without a maximum reports its percentage directly`() {
    #expect(StatusReadings.Battery.percent(current: 57, max: 0) == 57)
  }

  @Test func `levels closer than half a percent look alike`() {
    let a = StatusItem(symbol: "speaker.wave.3.fill", level: 0.500)
    let b = StatusItem(symbol: "speaker.wave.3.fill", level: 0.504)
    let c = StatusItem(symbol: "speaker.wave.3.fill", level: 0.51)

    #expect([a].looksLike([b]))
    #expect(![a].looksLike([c]))
  }

  @Test func `a level appearing changes the look`() {
    let a = StatusItem(symbol: "speaker.wave.3.fill", level: nil)
    let b = StatusItem(symbol: "speaker.wave.3.fill", level: 0.5)

    #expect(![a].looksLike([b]))
  }

  @Test func `Wi-Fi powered off is off even with a link`() {
    #expect(WiFiState(power: false, isUp: true, isKnown: true) == .off)
  }

  @Test func `Wi-Fi up is connected`() {
    #expect(WiFiState(power: nil, isUp: true, isKnown: true) == .connected)
  }

  @Test func `Wi-Fi on but down is without a network`() {
    #expect(WiFiState(power: true, isUp: false, isKnown: true) == .disconnected)
  }

  @Test func `Wi-Fi macOS knows nothing of is not shown`() {
    #expect(WiFiState(power: nil, isUp: false, isKnown: false) == .none)
  }

  @Test(arguments: ["100.64.0.1", "100.101.102.103", "100.127.255.255"])
  func `addresses in 100.64.0.0/10 are on the tailnet`(address: String) {
    #expect(Tailnet.contains(address))
  }

  @Test(arguments: ["100.63.255.255", "100.128.0.0", "10.64.0.1", "100.64.0", "100.64.0.+1", ""])
  func `other addresses and malformed ones are not`(address: String) {
    #expect(!Tailnet.contains(address))
  }
}
