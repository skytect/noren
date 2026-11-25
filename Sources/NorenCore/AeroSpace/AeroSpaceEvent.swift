// The events noren follows, decoded once from AeroSpace's ServerEvent JSON
// (Sources/AppBundle/model/ServerEvent.swift at the commit AeroSpaceWire names), so no part reads
// JSON keys itself.
import Foundation

/// Something that happened in AeroSpace, or the connection to it opening.
public enum AeroSpaceEvent: Equatable, Sendable {
  /// The connection to AeroSpace opened or opened again. AeroSpace may have changed meanwhile, so
  /// each part reads what it needs afresh.
  case connected
  /// Keyboard focus moved; `windowId` is AeroSpace's id of the focused window, nil when none is.
  case focusChanged(windowId: UInt32?, workspace: String)
  case focusedWorkspaceChanged(workspace: String, previous: String)
  /// `monitorId` counts AeroSpace's monitors from 1.
  case focusedMonitorChanged(workspace: String, monitorId: Int)
  case modeChanged(mode: String?)
  case windowDetected(windowId: UInt32, workspace: String?, appBundleId: String?, appName: String?)
  /// A key AeroSpace binds was pressed: `binding` as its config writes it, such as `alt-q`.
  case bindingTriggered(mode: String, binding: String)

  /// The names `aerospace subscribe` takes for the events above.
  public static let subscriptionNames = [
    "focus-changed", "focused-workspace-changed", "focused-monitor-changed", "mode-changed",
    "window-detected", "binding-triggered",
  ]

  /// The event a frame from `aerospace subscribe` holds.
  public init(json: Data) throws(AeroSpaceError) {
    let fields: Fields
    do {
      fields = try JSONDecoder().decode(Fields.self, from: json)
    } catch {
      throw .malformed("an event that is not JSON AeroSpace sends: \(error)")
    }
    func required<T>(_ value: T?, _ name: String) throws(AeroSpaceError) -> T {
      guard let value else { throw .malformed("a \(fields.event) event without \(name)") }
      return value
    }
    switch fields.event {
    case "focus-changed":
      self = .focusChanged(
        windowId: fields.windowId, workspace: try required(fields.workspace, "workspace"))
    case "focused-workspace-changed":
      self = .focusedWorkspaceChanged(
        workspace: try required(fields.workspace, "workspace"),
        previous: try required(fields.prevWorkspace, "prevWorkspace"))
    case "focused-monitor-changed":
      self = .focusedMonitorChanged(
        workspace: try required(fields.workspace, "workspace"),
        monitorId: try required(fields.monitorId, "monitorId"))
    case "mode-changed":
      self = .modeChanged(mode: fields.mode)
    case "window-detected":
      self = .windowDetected(
        windowId: try required(fields.windowId, "windowId"), workspace: fields.workspace,
        appBundleId: fields.appBundleId, appName: fields.appName)
    case "binding-triggered":
      self = .bindingTriggered(
        mode: try required(fields.mode, "mode"), binding: try required(fields.binding, "binding"))
    default:
      throw .malformed("an event noren does not know: \(fields.event)")
    }
  }

  private struct Fields: Decodable {
    enum CodingKeys: String, CodingKey {
      case event = "_event"
      case windowId, workspace, prevWorkspace, monitorId, appBundleId, appName, mode, binding
    }

    let event: String
    let windowId: UInt32?
    let workspace: String?
    let prevWorkspace: String?
    let monitorId: Int?
    let appBundleId: String?
    let appName: String?
    let mode: String?
    let binding: String?
  }
}

/// What went wrong talking to AeroSpace.
public enum AeroSpaceError: Error, Equatable, CustomStringConvertible {
  /// AeroSpace's socket is not there or refuses the connection: AeroSpace is not running.
  case unreachable(String)
  /// The connection ended before AeroSpace answered.
  case closed
  /// AeroSpace speaks another version of its socket protocol than noren does.
  case protocolMismatch(server: UInt32)
  /// AeroSpace sent something noren cannot read.
  case malformed(String)
  /// The command failed; `stderr` is AeroSpace's reason.
  case failed(exitCode: Int32, stderr: String)
  /// The command asked about the focused window, and none is focused.
  case noWindowFocused

  public var description: String {
    switch self {
    case .unreachable(let reason): "AeroSpace is not reachable: \(reason)"
    case .closed: "AeroSpace closed the connection"
    case .protocolMismatch(let server):
      "AeroSpace speaks socket protocol \(server), noren \(AeroSpaceWire.protocolVersion)"
    case .malformed(let what): "AeroSpace sent \(what)"
    case .failed(let exitCode, let stderr): "AeroSpace failed (exit \(exitCode)): \(stderr)"
    case .noWindowFocused: "no window is focused"
    }
  }
}
