// Wi-Fi, Ethernet and Tailscale, from SystemConfiguration's dynamic store, read again whenever
// an interface's AirPort, Link or IPv4 key, or the list of interfaces, changes:
//
//   Wi-Fi      the Wi-Fi interface's AirPort (power), Link and IPv4 keys: off, on without a
//              network, or connected. Not the network's name: that needs Location Services.
//   Ethernet   a wired interface with its link up and an IPv4 address.
//   Tailscale  a utun interface holding a tailnet address (Tailnet), which the Tailscale app's
//              network extension adds on connecting and removes on disconnecting. The `tailscale`
//              command would tell the same, but only by polling a subprocess.
import Foundation
import NorenCore
import SystemConfiguration

final class Network {
  struct Reading {
    var wired = false
    var wiFi = WiFiState.none
    var tailscale = false
  }

  private static let interfaceList = "State:/Network/Interface"

  private let changed: (Reading) -> Void
  private var store: SCDynamicStore?

  /// Reads the network now, and again on every change.
  init(changed: @escaping (Reading) -> Void) {
    self.changed = changed
    var context = SCDynamicStoreContext(
      version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
      copyDescription: nil)
    store = SCDynamicStoreCreate(
      nil, "noren.bar" as CFString,
      { _, _, info in
        MainActor.assumeIsolated {
          Unmanaged<Network>.fromOpaque(info!).takeUnretainedValue().read()
        }
      }, &context)
    if let store {
      SCDynamicStoreSetNotificationKeys(
        store, [Self.interfaceList] as CFArray,
        ["State:/Network/Interface/[^/]+/(AirPort|Link|IPv4)"] as CFArray)
      SCDynamicStoreSetDispatchQueue(store, .main)
    }
    read()
  }

  private func read() {
    var reading = Reading()
    // The Wi-Fi and wired interfaces, looked up afresh each time (a USB adapter comes and goes)
    var wiFiInterface: String?
    for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
      guard let type = SCNetworkInterfaceGetInterfaceType(interface),
        let name = SCNetworkInterfaceGetBSDName(interface) as String?
      else { continue }
      if type == kSCNetworkInterfaceTypeIEEE80211, wiFiInterface == nil { wiFiInterface = name }
      if type == kSCNetworkInterfaceTypeEthernet, isUp(name) { reading.wired = true }
    }
    if let wiFiInterface {
      let airPort = value(Self.key(wiFiInterface, "AirPort"))
      let link = value(Self.key(wiFiInterface, "Link"))
      reading.wiFi = WiFiState(
        power: airPort?["Power Status"] as? Bool, isUp: isUp(wiFiInterface),
        isKnown: airPort != nil || link != nil)
    }
    let names = value(Self.interfaceList)?["Interfaces"] as? [String] ?? []
    reading.tailscale = names.contains { name in
      name.hasPrefix("utun") && addresses(name).contains(where: Tailnet.contains)
    }
    changed(reading)
  }

  /// Whether interface `name` has its link up and an IPv4 address.
  private func isUp(_ name: String) -> Bool {
    value(Self.key(name, "Link"))?["Active"] as? Bool == true && !addresses(name).isEmpty
  }

  private func addresses(_ name: String) -> [String] {
    value(Self.key(name, "IPv4"))?["Addresses"] as? [String] ?? []
  }

  private func value(_ key: String) -> [String: Any]? {
    guard let store else { return nil }
    return SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
  }

  private static func key(_ interface: String, _ entity: String) -> String {
    "State:/Network/Interface/\(interface)/\(entity)"
  }
}
