import Foundation
import Testing
@testable import CCCVCore

@MainActor
@Test func expiredItemsArePurgedExceptPinned() throws {
    let store = try ClipStore(url: nil)
    let now = Date()
    try store.add(ClipContent(kind: .text, text: "token-a"), sourceBundleID: nil, at: now, expiresAt: now + 60)
    try store.add(ClipContent(kind: .text, text: "token-b"), sourceBundleID: nil, at: now + 1, expiresAt: now + 60)
    try store.add(ClipContent(kind: .text, text: "normal"), sourceBundleID: nil, at: now + 2)
    try store.recent().first { $0.text == "token-b" }?.isPinned = true
    try store.save()

    #expect(try store.purgeExpired(now: now + 59) == 0) // 아직 안 됨
    #expect(try store.purgeExpired(now: now + 60) == 1) // token-a 만 (token-b 는 고정)
    #expect(Set(try store.recent().map(\.text)) == ["token-b", "normal"])
}

@MainActor
@Test func recopyingPinnedItemDoesNotReArmExpiry() throws {
    let store = try ClipStore(url: nil)
    let now = Date()
    try store.add(ClipContent(kind: .text, text: "token"), sourceBundleID: nil, at: now)
    let item = try #require(try store.recent().first)
    item.isPinned = true
    try store.add(ClipContent(kind: .text, text: "token"), sourceBundleID: nil, at: now + 1, expiresAt: now + 60)
    #expect(item.expiresAt == nil)
}

@Test func firstMatchingPatternIndex() {
    let patterns = [#"^\d{6}$"#, #"^eyJ.+$"#]
    #expect(PasteboardRules.firstMatchingPattern("123456", patterns: patterns) == 0)
    #expect(PasteboardRules.firstMatchingPattern("eyJabc", patterns: patterns) == 1)
    #expect(PasteboardRules.firstMatchingPattern("hello", patterns: patterns) == nil)
}

@Test func presetsMatchTypicalTokens() {
    let presets = PasteboardRules.sensitivePresets.map(\.pattern)
    let samples = [
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln",
        "ghp_" + String(repeating: "a", count: 36),
        "AKIA" + String(repeating: "A", count: 16),
        "xoxb-1234567890-abcdef",
    ]
    for (i, sample) in samples.enumerated() {
        #expect(PasteboardRules.firstMatchingPattern(sample, patterns: presets) == i)
    }
    #expect(PasteboardRules.firstMatchingPattern("just a sentence", patterns: presets) == nil)
}
