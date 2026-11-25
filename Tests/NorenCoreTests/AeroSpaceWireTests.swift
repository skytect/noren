import Foundation
import NorenCore
import Testing

@Suite struct AeroSpaceWireTests {
  @Test func `a request is its JSON's length, then the JSON AeroSpace's server decodes`() throws {
    let frame = try AeroSpaceWire.requestFrame(args: ["list-workspaces", "--focused"])

    let json = #"""
      {"args":["list-workspaces","--focused"],"stdin":"","windowId":null,"workspace":null}
      """#
    #expect(frame == Data([84, 0, 0, 0]) + Data(json.utf8))
  }

  @Test func `the protocol version is written little-endian`() {
    #expect(AeroSpaceWire.bytes(of: 0x0102_0304) == Data([4, 3, 2, 1]))
  }

  @Test func `the server's version comes before its first frame`() {
    var reader = AeroSpaceReader()

    reader.append(Data([1, 0, 0, 0, 2, 0, 0, 0]) + Data("{}".utf8))

    #expect(reader.nextUInt32() == 1)
    #expect(reader.nextFrame() == Data("{}".utf8))
  }

  @Test func `a frame split across reads comes out whole once its last byte is in`() {
    var reader = AeroSpaceReader()

    reader.append(Data([5, 0]))
    let afterTwoBytes = reader.nextFrame()
    reader.append(Data([0, 0]) + Data("[1,".utf8))
    let beforeTheEnd = reader.nextFrame()
    reader.append(Data("2]".utf8) + Data([9]))

    #expect(afterTwoBytes == nil)
    #expect(beforeTheEnd == nil)
    #expect(reader.nextFrame() == Data("[1,2]".utf8))
  }

  @Test func `two frames read at once come out in order, and nothing after them`() {
    var reader = AeroSpaceReader()

    reader.append(Data([1, 0, 0, 0]) + Data("a".utf8) + Data([2, 0, 0, 0]) + Data("bc".utf8))

    #expect(reader.nextFrame() == Data("a".utf8))
    #expect(reader.nextFrame() == Data("bc".utf8))
    #expect(reader.nextFrame() == nil)
  }

  @Test func `a frame longer than 255 bytes reads its length from all four bytes`() {
    var reader = AeroSpaceReader()
    let json = Data(repeating: UInt8(ascii: "x"), count: 0x0102)

    reader.append(Data([0x02, 0x01, 0, 0]) + json)

    #expect(reader.nextFrame() == json)
  }
}
