import NorenCore
import Testing

@Suite struct ChipLayoutTests {
  // "+n" is 12 points wide for any n here
  func more(_ count: Int) -> Double { 12 }

  @Test func `with room, every chip shows up to four icons`() {
    // 8 label + 5 gap + 4 icons of 16 + 3 gaps of 2 + 2 gap + 12 "+2" + 2 × 7 padding = 111
    let layout = ChipLayout(
      chips: [ChipLayout.Chip(labelWidth: 8, iconCount: 6)], room: 500, moreWidth: more)

    #expect(layout.iconLimit == 4)
    #expect(layout.widths == [111])
  }

  @Test func `a narrow chip without icons is as wide as it is high`() {
    // 4 + 2 × 7 = 18, widened to the chip's height, 22
    let layout = ChipLayout(
      chips: [ChipLayout.Chip(labelWidth: 4, iconCount: 0)], room: 500, moreWidth: more)

    #expect(layout.widths == [22])
  }

  @Test func `a chip showing all its icons has no count`() {
    // 8 + 5 + 2 icons of 16 + 2 + 2 × 7 = 61
    let layout = ChipLayout(
      chips: [ChipLayout.Chip(labelWidth: 8, iconCount: 2)], room: 500, moreWidth: more)

    #expect(layout.widths == [61])
  }

  @Test func `icons drop one at a time until the row fits`() {
    // Two chips of 3 icons: 8 + 5 + 48 + 4 + 14 = 79 each, 162 with the gap. With 2 icons:
    // 8 + 5 + 32 + 2 + 2 + 12 + 14 = 75 each, 154 with the gap.
    let chips = [
      ChipLayout.Chip(labelWidth: 8, iconCount: 3), ChipLayout.Chip(labelWidth: 8, iconCount: 3),
    ]

    let layout = ChipLayout(chips: chips, room: 160, moreWidth: more)

    #expect(layout.iconLimit == 2)
    #expect(layout.widths == [75, 75])
  }

  @Test func `with no room at all, chips show no icons and no count`() {
    let layout = ChipLayout(
      chips: [ChipLayout.Chip(labelWidth: 8, iconCount: 3)], room: 10, moreWidth: more)

    #expect(layout.iconLimit == 0)
    #expect(layout.widths == [22])
  }
}
