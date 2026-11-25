// The bar's status items (StatusReadings): the microphone and the camera while something uses
// them, Tailscale, Ethernet, Wi-Fi, the output volume and the battery. The bar draws them beside
// the clock and runs an item's action on a click: Tailscale's opens its app, the rest open their
// settings pane.
//
// Every one is read without a privacy permission, and each changes on a notification, not a poll:
//   battery     IOKit's power sources (Battery)
//   volume      CoreAudio: the default output device's volume and mute (Audio)
//   microphone  CoreAudio: an input device running somewhere (Audio)
//   camera      CoreMediaIO: a camera running somewhere (Camera)
//   network     SystemConfiguration's dynamic store: Wi-Fi, Ethernet and Tailscale (Network)
import AppKit
import NorenCore

/// The status items as they stand, read afresh whenever macOS says one may have changed.
final class Status {
  /// The Tailscale app, from its own site (macsys) or the App Store (macos).
  private static let tailscaleApps = ["io.tailscale.ipn.macsys", "io.tailscale.ipn.macos"]

  /// The items as they stand, left to right.
  private(set) var items: [StatusItem] = []
  private var readings = StatusReadings()
  private var changed: () -> Void = {}
  private var battery: Battery?
  private var audio: Audio?
  private var camera: Camera?
  private var network: Network?

  /// Starts following the items; `changed` runs whenever they look different.
  func start(changed: @escaping () -> Void) {
    self.changed = changed
    readings.tailscaleApp = Self.tailscaleApps.last {
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
    }
    battery = Battery { [unowned self] in
      readings.battery = $0
      publish()
    }
    audio = Audio { [unowned self] output, microphone in
      readings.output = output
      readings.microphone = microphone
      publish()
    }
    camera = Camera { [unowned self] in
      readings.camera = $0
      publish()
    }
    network = Network { [unowned self] in
      readings.wired = $0.wired
      readings.wiFi = $0.wiFi
      readings.tailscaleConnected = $0.tailscale
      publish()
    }
  }

  /// Runs `action`, an item's click.
  func perform(_ action: StatusAction) {
    let workspace = NSWorkspace.shared
    switch action {
    case .open(let url):
      guard let url = URL(string: url) else { return }
      workspace.open(url)
    case .launch(let bundleId):
      guard let url = workspace.urlForApplication(withBundleIdentifier: bundleId) else { return }
      workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
  }

  /// Tells the bar when the items, from the readings as they stand, look different.
  private func publish() {
    let items = readings.items
    guard !items.looksLike(self.items) else { return }
    self.items = items
    changed()
  }
}
