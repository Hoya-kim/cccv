import Foundation
import Testing
@testable import CCCVCore

@MainActor
@Test func newestFirstAndDedupe() throws {
    let store = try ClipStore(url: nil)
    let start = Date()
    try store.add(text: "a", sourceBundleID: "app.one", at: start)
    try store.add(text: "b", sourceBundleID: "app.one", at: start + 1)
    try store.add(text: "a", sourceBundleID: nil, at: start + 2)
    let items = try store.recent()
    #expect(items.map(\.text) == ["a", "b"])
    #expect(items[0].sourceBundleID == "app.one") // 출처 모름(nil)은 기존 출처를 덮어쓰지 않는다
}

@MainActor
@Test func ignoresEmptyAndLimitsRecent() throws {
    let store = try ClipStore(url: nil)
    try store.add(text: "", sourceBundleID: nil)
    for (i, text) in ["1", "2", "3"].enumerated() {
        try store.add(text: text, sourceBundleID: nil, at: Date(timeIntervalSince1970: Double(i)))
    }
    #expect(try store.recent(limit: 2).map(\.text) == ["3", "2"])
}

@MainActor
@Test func persistsAcrossReopen() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cccv-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "test.store")
    do {
        try ClipStore(url: url).add(text: "kept", sourceBundleID: nil)
    }
    // 모델 인스턴스는 컨테이너가 살아 있는 동안만 유효하다 → 저장소를 변수로 붙잡아 둔다.
    let reopened = try ClipStore(url: url)
    #expect(try reopened.recent().map(\.text) == ["kept"])
}

@Test func ignoresConcealedTypes() {
    #expect(PasteboardRules.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
    #expect(!PasteboardRules.shouldIgnore(types: ["public.utf8-plain-text"]))
}
