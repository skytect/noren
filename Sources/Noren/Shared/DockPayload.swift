// The Dock payload's port (Dock/payload.m, NorenPrivate/DockProtocol.h): noren's messages about
// windows, each an array of window server ids. Drag sends its moves itself, on its own queue.
import CoreGraphics
import Foundation
import NorenPrivate

enum DockPayload {
  /// How long noren waits to hand the payload a message, in seconds
  private nonisolated static let timeout: CFTimeInterval = 0.25

  /// Hands the payload `message` about `windows`; false when the payload is not in the Dock or
  /// did not take it. Off the main thread: sending may wait up to `timeout`.
  @concurrent
  nonisolated static func send(_ message: NORMessage, _ windows: [CGWindowID]) async -> Bool {
    guard !windows.isEmpty else { return true }
    guard let port = CFMessagePortCreateRemote(nil, NOR_DOCK_PORT as CFString) else { return false }
    let data = windows.withUnsafeBytes { Data($0) }
    return CFMessagePortSendRequest(port, message.rawValue, data as CFData, timeout, 0, nil, nil)
      == kCFMessagePortSuccess
  }
}
