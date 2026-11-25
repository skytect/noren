import NorenCore
import Testing

@Suite struct TitleMatchingTests {
  typealias Pair = TitleMatching.Pair

  @Test func `the same title wins over a title with more words in common`() {
    let matching = TitleMatching(
      windows: ["Inbox Mail Drafts", "Inbox"], recorded: ["Inbox", "Inbox Mail Drafts Sent"])

    #expect(matching.pairs == [Pair(window: 1, recorded: 0), Pair(window: 0, recorded: 1)])
  }

  @Test func `the pair with the most words in common goes first`() {
    let matching = TitleMatching(
      windows: ["notes.md - project", "readme.md - project - editor"],
      recorded: ["readme.md - project - editor (edited)"])

    #expect(matching.pairs == [Pair(window: 1, recorded: 0)])
    #expect(matching.unmatchedWindows == [0])
  }

  @Test func `words are compared without case or punctuation`() {
    let matching = TitleMatching(
      windows: ["final budget", "Budget, 2026 (Final)"], recorded: ["budget-2026-final.xlsx"])

    #expect(matching.pairs == [Pair(window: 1, recorded: 0)])
  }

  @Test func `windows with nothing in common pair in order`() {
    let matching = TitleMatching(windows: ["Alpha", "Beta"], recorded: ["Gamma", "Delta"])

    #expect(matching.pairs == [Pair(window: 0, recorded: 0), Pair(window: 1, recorded: 1)])
  }

  @Test func `recorded windows that did not open are left over`() {
    let matching = TitleMatching(windows: ["Inbox"], recorded: ["Sent", "Inbox", "Drafts"])

    #expect(matching.pairs == [Pair(window: 0, recorded: 1)])
    #expect(matching.unmatchedRecorded == [0, 2])
  }

  @Test func `with no recorded windows every window is left over`() {
    let matching = TitleMatching(windows: ["Inbox", "Sent"], recorded: [])

    #expect(matching.pairs == [])
    #expect(matching.unmatchedWindows == [0, 1])
  }
}
