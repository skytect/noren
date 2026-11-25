// One connection to AeroSpace's socket, as AeroSpace's own command-line client opens it
// (NWConnectionEx.swift in AeroSpace's sources): a Unix socket in /tmp, the protocol versions
// exchanged, then frames both ways (AeroSpaceWire).
import Foundation
import Network
import NorenCore

/// An open connection to AeroSpace's server.
nonisolated final class AeroSpaceSocket: Sendable {
  /// Where AeroSpace listens for the current user.
  static var path: String { "/tmp/bobko.aerospace-\(NSUserName()).sock" }

  private let connection: NWConnection
  private let queue = DispatchQueue(label: "local.noren.aerospace")

  private init(connection: NWConnection) {
    self.connection = connection
  }

  /// A connection to AeroSpace that has agreed on the protocol version.
  static func open() async throws(AeroSpaceError) -> AeroSpaceSocket {
    let socket = AeroSpaceSocket(connection: NWConnection(to: .unix(path: path), using: .tcp))
    do {
      try await socket.start()
    } catch {
      throw .unreachable(String(describing: error))
    }
    try await socket.send(AeroSpaceWire.bytes(of: AeroSpaceWire.protocolVersion))
    var reader = AeroSpaceReader()
    while true {
      if let version = reader.nextUInt32() {
        guard version == AeroSpaceWire.protocolVersion else {
          socket.close()
          throw .protocolMismatch(server: version)
        }
        return socket
      }
      reader.append(try await socket.receive())
    }
  }

  func send(_ data: Data) async throws(AeroSpaceError) {
    let failure: NWError? = await withCheckedContinuation { continuation in
      connection.send(
        content: data,
        completion: .contentProcessed { error in continuation.resume(returning: error) })
    }
    if let failure { throw .unreachable(String(describing: failure)) }
  }

  /// The bytes that arrive next; throws `.closed` once the server has closed the connection.
  func receive() async throws(AeroSpaceError) -> Data {
    let result: Result<Data, AeroSpaceError> = await withCheckedContinuation { continuation in
      connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) {
        data, _, _, error in
        if let error {
          continuation.resume(returning: .failure(.unreachable(String(describing: error))))
        } else if let data, !data.isEmpty {
          continuation.resume(returning: .success(data))
        } else {
          continuation.resume(returning: .failure(.closed))
        }
      }
    }
    return try result.get()
  }

  func close() {
    connection.cancel()
  }

  private func start() async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      // Called on `queue`, one state after another; unset once the connection is ready or not, so
      // the continuation resumes once
      connection.stateUpdateHandler = { [connection] state in
        switch state {
        case .ready:
          connection.stateUpdateHandler = nil
          continuation.resume()
        case .failed(let error), .waiting(let error):
          connection.stateUpdateHandler = nil
          connection.cancel()
          continuation.resume(throwing: error)
        default:
          break
        }
      }
      connection.start(queue: queue)
    }
  }
}

/// An AeroSpaceSocket with the bytes read from it so far, read a frame at a time.
nonisolated final class AeroSpaceFrames {
  private let socket: AeroSpaceSocket
  private var reader = AeroSpaceReader()

  init(_ socket: AeroSpaceSocket) {
    self.socket = socket
  }

  func next() async throws(AeroSpaceError) -> Data {
    while true {
      if let frame = reader.nextFrame() { return frame }
      reader.append(try await socket.receive())
    }
  }
}
