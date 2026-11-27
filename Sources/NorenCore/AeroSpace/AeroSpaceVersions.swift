// `aerospace -v`: the version of the command, and of the AeroSpace app it reached, each a version
// and a commit. They differ when the app running is not the build beside the command: noren was
// updated and AeroSpace not yet restarted.
import Foundation

/// The command's and the running app's versions, as `aerospace -v` prints them.
public struct AeroSpaceVersions: Equatable, Sendable {
  public let command: String
  /// nil when no AeroSpace app answered
  public let app: String?

  /// The versions in `output`, nil when it names none for the command.
  public init?(output: String) {
    var command: String?
    var app: String?
    for line in output.split(separator: "\n") {
      if let value = Self.value(of: "aerospace CLI client version:", in: line) { command = value }
      // "Unknown. The server is not responding" while none answers
      if let value = Self.value(of: "AeroSpace.app server version:", in: line),
        !value.hasPrefix("Unknown")
      {
        app = value
      }
    }
    guard let command else { return nil }
    self.command = command
    self.app = app
  }

  /// Whether the AeroSpace running is another build than the command's
  public var appIsOtherBuild: Bool {
    app.map { $0 != command } ?? false
  }

  private static func value(of label: String, in line: Substring) -> String? {
    guard line.hasPrefix(label) else { return nil }
    return line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
  }
}
