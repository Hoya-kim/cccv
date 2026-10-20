import Foundation
import Testing
@testable import CCCVCore

@Test func truncatesToMinutes() {
    let now = Date(timeIntervalSince1970: 100_000)
    let label = { (seconds: Double) in RelativeTime.label(since: now - seconds, now: now) }
    #expect(label(59) == "방금 전")
    #expect(label(-5) == "방금 전") // 시계가 어긋나 미래 시각이어도
    #expect(label(60) == "1분 전")
    #expect(label(119) == "1분 전")
    #expect(label(59 * 60 + 59) == "59분 전")
    #expect(label(60 * 60) == "1시간 전")
    #expect(label(25 * 60 * 60) == "1일 전")
}
