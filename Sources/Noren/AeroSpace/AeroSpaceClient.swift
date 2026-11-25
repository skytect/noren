import Foundation
import NorenCore
import os

/// noren's way to AeroSpace: its commands, and the events every part follows.
final class AeroSpaceClient {
  private let log = Logger(subsystem: "local.noren", category: "aerospace")

  /// How long to wait before connecting again after AeroSpace went away (quit or restarted).
  private let reconnectDelay = Duration.seconds(1)

  /// Runs the aerospace command `args` and returns its output. Each command has a connection of
  /// its own, as with AeroSpace's command-line client, so commands from different parts do not
  /// wait for each other.
  nonisolated func run(_ args: [String]) async throws(AeroSpaceError) -> String {
    let socket = try await AeroSpaceSocket.open()
    defer { socket.close() }
    try await socket.send(try Self.request(args))
    return try AeroSpaceWire.output(ofAnswer: try await AeroSpaceFrames(socket).next())
  }

  /// Runs the aerospace command `args`, which prints JSON (`--json`), and decodes its output.
  nonisolated func run<T: Decodable>(_ args: [String], as type: T.Type) async throws -> T {
    try JSONDecoder().decode(type, from: Data(try await run(args).utf8))
  }

  /// What AeroSpace's config says about floating apps and closing keys.
  nonisolated func configFacts() async throws -> AeroSpaceConfigFacts {
    let path = try await run(["config", "--config-path"])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return try AeroSpaceConfigFacts(toml: try String(contentsOfFile: path, encoding: .utf8))
  }

  /// AeroSpace's events from now on, with `.connected` each time the connection to it opens. It
  /// connects again whenever AeroSpace goes away, and ends only when AeroSpace answers in a way
  /// noren cannot follow (another protocol version, a refused subscription), which it reports.
  func events() -> AsyncStream<AeroSpaceEvent> {
    AsyncStream { continuation in
      let task = Task {
        await follow(continuation)
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func follow(_ continuation: AsyncStream<AeroSpaceEvent>.Continuation) async {
    var waiting = false  // whether AeroSpace being away has been logged since it was last there
    while !Task.isCancelled {
      do {
        let socket = try await AeroSpaceSocket.open()
        defer { socket.close() }
        try await socket.send(
          try Self.request(["subscribe", "--no-send-initial"] + AeroSpaceEvent.subscriptionNames))
        log.info("connected to AeroSpace")
        waiting = false
        continuation.yield(.connected)
        let frames = AeroSpaceFrames(socket)
        while true {
          continuation.yield(try event(in: try await frames.next()))
        }
      } catch .unreachable(let reason) {
        if !waiting { log.info("waiting for AeroSpace: \(reason, privacy: .public)") }
        waiting = true
      } catch .closed {
        log.info("AeroSpace closed the connection; connecting again")
      } catch {
        Problems.report("noren stopped following AeroSpace: \(error)")
        return
      }
      try? await Task.sleep(for: reconnectDelay)
    }
  }

  /// The event in the subscription's frame `json`. A frame that is an answer instead is AeroSpace
  /// refusing the subscription.
  private func event(in json: Data) throws(AeroSpaceError) -> AeroSpaceEvent {
    do {
      return try AeroSpaceEvent(json: json)
    } catch {
      _ = try AeroSpaceWire.output(ofAnswer: json)
      throw error
    }
  }

  private nonisolated static func request(_ args: [String]) throws(AeroSpaceError) -> Data {
    do {
      return try AeroSpaceWire.requestFrame(args: args)
    } catch {
      throw .malformed("a request noren could not encode: \(error)")
    }
  }
}
