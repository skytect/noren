// AeroSpace's socket protocol, as its own client and server speak it: AeroSpace's
// Sources/Common/util/NWConnectionEx.swift and Sources/Common/model/clientServer.swift, at commit
// d69a64d833ca2cfe0e088cfae8e5e9751ec9eff3.
//
// A connection opens with each side writing its protocol version as a UInt32. After that every
// message, either way, is a frame: the length of its JSON as a UInt32, then the JSON. AeroSpace
// writes the integers in the machine's byte order, which is little-endian on every Mac.
import Foundation

/// Encoding and decoding of the bytes on AeroSpace's socket.
public enum AeroSpaceWire {
  /// The protocol version noren speaks. The server answers with its own; they must match.
  public static let protocolVersion: UInt32 = 1

  /// `value` as the protocol writes it.
  public static func bytes(of value: UInt32) -> Data {
    Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
  }

  /// A request to run the command `args`, as one frame.
  public static func requestFrame(args: [String]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let json = try encoder.encode(Request(args: args))
    return bytes(of: UInt32(json.count)) + json
  }

  /// AeroSpace's ClientRequest. `windowId` and `workspace` stand for the AEROSPACE_WINDOW_ID and
  /// AEROSPACE_WORKSPACE a command run from an AeroSpace callback would have; noren runs none, so
  /// both are sent as an explicit null, as the server asks (it adds a warning when either is
  /// missing).
  private struct Request: Encodable {
    let args: [String]

    enum CodingKeys: String, CodingKey {
      case args, stdin, windowId, workspace
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(args, forKey: .args)
      try container.encode("", forKey: .stdin)
      try container.encodeNil(forKey: .windowId)
      try container.encodeNil(forKey: .workspace)
    }
  }
}

/// The bytes read from AeroSpace's socket so far, taken apart as they complete.
public struct AeroSpaceReader {
  private var buffer = Data()

  public init() {}

  /// Adds the bytes just read.
  public mutating func append(_ data: Data) {
    buffer.append(data)
  }

  /// The next UInt32, such as the server's protocol version, or nil until all four bytes are in.
  public mutating func nextUInt32() -> UInt32? {
    guard let value = peekUInt32() else { return nil }
    buffer.removeFirst(4)
    return value
  }

  /// The JSON of the next frame, or nil until all of it is in.
  public mutating func nextFrame() -> Data? {
    guard let length = peekUInt32().map(Int.init), buffer.count >= 4 + length else { return nil }
    let frame = Data(buffer.dropFirst(4).prefix(length))
    buffer.removeFirst(4 + length)
    return frame
  }

  private func peekUInt32() -> UInt32? {
    guard buffer.count >= 4 else { return nil }
    return buffer.prefix(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
  }
}
