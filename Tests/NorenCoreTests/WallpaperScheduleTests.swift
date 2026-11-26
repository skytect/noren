import NorenCore
import Testing

@Suite struct WallpaperScheduleTests {
  /// The apple_desktop:h24 tag of a dynamic wallpaper with six frames: 06:30, 08:00, 11:00,
  /// 17:00, 19:00 and 20:00
  static let sixFrames =
    "YnBsaXN0MDDSAQIDGFJ0aVJhcKYECQwPEhXSBQYHCFF0UWkjP9FVVVVVVVUQANIFBgoLIz/VVVVVVVVVEAHSBQYNDiM/3VVVVVVVVRAC0gUGEBEjP+aqqqqqqqsQA9IFBhMUIz/pVVVVVVVVEATSBQYWFyM/6qqqqqqqqxAF0hkaDhdRbFFkCA0QExofISMsLjM8PkNMTlNcXmNsbnN8foOFAAAAAAAAAQEAAAAAAAAAGwAAAAAAAAAAAAAAAAAAAIc="
  let schedule = WallpaperSchedule(h24: Self.sixFrames)!

  /// `hour`:`minute` as a fraction of the day
  func at(_ hour: Double, _ minute: Double = 0) -> Double { (hour * 60 + minute) / 1440 }

  @Test func `a frame shows from its start`() {
    #expect(schedule.frame(at: at(11)) == 2)
  }

  @Test func `a frame shows until the next starts`() {
    #expect(schedule.frame(at: at(16, 59)) == 2)
  }

  @Test func `after midnight the evening's last frame still shows`() {
    #expect(schedule.frame(at: at(3)) == 5)
  }

  @Test func `the next change is the next frame's start`() {
    #expect(schedule.nextChange(after: at(9)) == at(11))
  }

  @Test func `after the last frame starts, the next change is tomorrow's first`() {
    #expect(schedule.nextChange(after: at(21)) == 1 + at(6, 30))
  }

  @Test func `a value that is no schedule gives none`() {
    #expect(WallpaperSchedule(h24: "not base64 at all") == nil)
  }
}
