import CoreGraphics
import NorenCore
import Testing

@Suite struct StillnessTests {
  let editor = WindowFrame(window: 208, bounds: CGRect(x: 8, y: 62, width: 852, height: 1050))
  let chat = WindowFrame(window: 73, bounds: CGRect(x: 868, y: 62, width: 852, height: 1050))
  let chatMoving = WindowFrame(window: 73, bounds: CGRect(x: 868, y: 590, width: 852, height: 522))

  /// Whether the last of `looks`, taken in turn, finds the windows still
  func stillAfter(_ looks: [[WindowFrame]]) -> Bool {
    var stillness = Stillness()
    return looks.map { stillness.look($0) }.last ?? false
  }

  @Test func `the first look never finds the windows still`() {
    #expect(!stillAfter([[editor, chat]]))
  }

  @Test func `five looks unchanged since the first are not enough`() {
    #expect(!stillAfter(Array(repeating: [editor, chat], count: 5)))
  }

  @Test func `windows are still on the fifth unchanged look after the first`() {
    #expect(stillAfter(Array(repeating: [editor, chat], count: 6)))
  }

  @Test func `a window moving starts the count again`() {
    let looks =
      Array(repeating: [editor, chatMoving], count: 5)
      + Array(repeating: [editor, chat], count: 5)

    #expect(!stillAfter(looks))
  }

  @Test func `windows changing places front to back count as a change`() {
    let looks = Array(repeating: [editor, chat], count: 5) + [[chat, editor]]

    #expect(!stillAfter(looks))
  }

  @Test func `a screen with no windows is still too`() {
    #expect(stillAfter(Array(repeating: [], count: 6)))
  }
}
