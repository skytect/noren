import CoreGraphics
import NorenCore
import Testing

@Suite struct EdgeResizeTests {
  // Two windows side by side, 10 points apart, and two stacked
  let left = CGRect(x: 0, y: 0, width: 500, height: 800)
  let right = CGRect(x: 510, y: 0, width: 500, height: 800)
  let top = CGRect(x: 0, y: 0, width: 1000, height: 400)
  let bottom = CGRect(x: 0, y: 410, width: 1000, height: 400)

  @Test func `left on the right-hand window widens it, moving the divider left`() {
    let resize = EdgeResize(.left, by: 20, focused: right, others: [left])

    #expect(resize.arguments == ["resize", "width", "+20"])
  }

  @Test func `left on the left-hand window narrows it, moving the divider left`() {
    let resize = EdgeResize(.left, by: 20, focused: left, others: [right])

    #expect(resize.arguments == ["resize", "width", "-20"])
  }

  @Test func `right on the right-hand window narrows it, moving the divider right`() {
    let resize = EdgeResize(.right, by: 20, focused: right, others: [left])

    #expect(resize.arguments == ["resize", "width", "-20"])
  }

  @Test func `up on the lower window grows it, moving the divider up`() {
    let resize = EdgeResize(.up, by: 30, focused: bottom, others: [top])

    #expect(resize.arguments == ["resize", "height", "+30"])
  }

  @Test func `down on the upper window grows it, moving the divider down`() {
    let resize = EdgeResize(.down, by: 30, focused: top, others: [bottom])

    #expect(resize.arguments == ["resize", "height", "+30"])
  }

  @Test func `a window beside but not alongside is no neighbour`() {
    let elsewhere = CGRect(x: 510, y: 900, width: 500, height: 200)

    let resize = EdgeResize(.right, by: 20, focused: left, others: [elsewhere])

    #expect(resize.arguments == ["resize", "width", "-20"])
  }
}
