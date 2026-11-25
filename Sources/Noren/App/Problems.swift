import Foundation
import UserNotifications
import os

/// Problems the person running noren has to fix, such as a mistake in the config: logged, and
/// shown as a notification so they are seen without reading the log.
enum Problems {
  private static let log = Logger(subsystem: "local.noren", category: "problems")

  static func report(_ message: String) {
    log.error("\(message, privacy: .public)")
    // Notifications need an app bundle; `swift run` has none
    guard Bundle.main.bundleIdentifier != nil else { return }
    Task {
      let center = UNUserNotificationCenter.current()
      do {
        guard try await center.requestAuthorization(options: [.alert]) else {
          log.notice("notifications are off for noren; the problem is only in the log")
          return
        }
        let content = UNMutableNotificationContent()
        content.title = "noren"
        content.body = message
        try await center.add(
          UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
      } catch {
        log.error("could not show the problem as a notification: \(error, privacy: .public)")
      }
    }
  }
}
