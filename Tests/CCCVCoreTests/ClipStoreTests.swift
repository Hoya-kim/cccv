import Foundation
import Testing
@testable import CCCVCore

private func text(_ s: String) -> ClipContent { ClipContent(kind: .text, text: s) }

@MainActor
@Test func newestFirstAndDedupe() throws {
    let store = try ClipStore(url: nil)
    let start = Date()
    try store.add(text("a"), sourceBundleID: "app.one", at: start)
    try store.add(text("b"), sourceBundleID: "app.one", at: start + 1)
    try store.add(text("a"), sourceBundleID: nil, at: start + 2)
    let items = try store.recent()
    #expect(items.map(\.text) == ["a", "b"])
    #expect(items[0].sourceBundleID == "app.one") // 출처 모름(nil)은 기존 출처를 덮어쓰지 않는다
}

@MainActor
@Test func imagesDedupeByPayloadNotText() throws {
    let store = try ClipStore(url: nil)
    try store.add(ClipContent(kind: .image, text: "", payload: Data([1]), payloadType: "public.png"), sourceBundleID: nil)
    try store.add(ClipContent(kind: .image, text: "", payload: Data([2]), payloadType: "public.png"), sourceBundleID: nil)
    #expect(try store.recent().count == 2)
}

@MainActor
@Test func ignoresEmptyAndLimitsRecent() throws {
    let store = try ClipStore(url: nil)
    try store.add(text(""), sourceBundleID: nil)
    for (i, s) in ["1", "2", "3"].enumerated() {
        try store.add(text(s), sourceBundleID: nil, at: Date(timeIntervalSince1970: Double(i)))
    }
    #expect(try store.recent(limit: 2).map(\.text) == ["3", "2"])
}

@MainActor
@Test func persistsAcrossReopen() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "cccv-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appending(path: "test.store")
    do {
        try ClipStore(url: url).add(text("kept"), sourceBundleID: nil)
    }
    // 모델 인스턴스는 컨테이너가 살아 있는 동안만 유효하다 → 저장소를 변수로 붙잡아 둔다.
    let reopened = try ClipStore(url: url)
    #expect(try reopened.recent().map(\.text) == ["kept"])
}

@MainActor
@Test func searchMatchesTextAndLinkTitle() throws {
    let store = try ClipStore(url: nil)
    let start = Date()
    try store.add(text("Hello World"), sourceBundleID: nil, at: start)
    try store.add(text("다른 내용"), sourceBundleID: nil, at: start + 1)
    try store.add(ClipContent(kind: .link, text: "https://shop.example.com"), sourceBundleID: nil, at: start + 2)
    try store.recent().first { $0.kind == .link }?.linkTitle = "예시 쇼핑몰"
    try store.save()

    #expect(try store.search("hello").map(\.text) == ["Hello World"]) // 대소문자 무시
    #expect(try store.search("쇼핑").map(\.text) == ["https://shop.example.com"]) // 링크 제목
    #expect(try store.search("  ").count == 3) // 빈 검색어 → 최근 목록
    #expect(try store.search("없는말").isEmpty)
}

@MainActor
@Test func purgeDeletesOnlyOlderItems() throws {
    let store = try ClipStore(url: nil)
    let now = Date()
    try store.add(text("old"), sourceBundleID: nil, at: now - 31 * 86400)
    try store.add(text("edge"), sourceBundleID: nil, at: now - 30 * 86400)
    try store.add(text("new"), sourceBundleID: nil, at: now)
    let cutoff = now - 30 * 86400
    #expect(try store.count(olderThan: cutoff) == 1)
    #expect(try store.purge(olderThan: cutoff) == 1)
    #expect(try store.recent().map(\.text) == ["new", "edge"])
    #expect(try store.purge(olderThan: cutoff) == 0)
}

@MainActor
@Test func pinnedItemsSurvivePurgeAndFilter() throws {
    let store = try ClipStore(url: nil)
    let now = Date()
    try store.add(text("old pinned"), sourceBundleID: nil, at: now - 40 * 86400)
    try store.add(text("old"), sourceBundleID: nil, at: now - 40 * 86400 + 1)
    try store.add(text("new"), sourceBundleID: nil, at: now)
    try store.recent().first { $0.text == "old pinned" }?.isPinned = true
    try store.save()

    let cutoff = now - 30 * 86400
    #expect(try store.count(olderThan: cutoff) == 1)
    #expect(try store.purge(olderThan: cutoff) == 1)
    #expect(try store.recent().map(\.text) == ["new", "old pinned"])
    #expect(try store.search("", filter: ClipFilter(pinnedOnly: true)).map(\.text) == ["old pinned"])
    #expect(try store.search("new", filter: ClipFilter(pinnedOnly: true)).isEmpty)
}

@MainActor
@Test func filterByKindAndSourceApp() throws {
    let store = try ClipStore(url: nil)
    let start = Date()
    try store.add(text("edge text"), sourceBundleID: "app.edge", at: start)
    try store.add(ClipContent(kind: .link, text: "https://a.com"), sourceBundleID: "app.edge", at: start + 1)
    try store.add(ClipContent(kind: .link, text: "https://b.com"), sourceBundleID: "app.slack", at: start + 2)
    try store.add(text("unknown"), sourceBundleID: nil, at: start + 3)

    #expect(try store.search("", filter: ClipFilter(kind: .link)).map(\.text) == ["https://b.com", "https://a.com"])
    #expect(try store.search("", filter: ClipFilter(sourceBundleID: "app.edge")).map(\.text) == ["https://a.com", "edge text"])
    #expect(try store.search("", filter: ClipFilter(kind: .link, sourceBundleID: "app.edge")).map(\.text) == ["https://a.com"])
    #expect(try store.search("b.com", filter: ClipFilter(kind: .text)).isEmpty) // 검색어와 함께 걸린다
    #expect(try store.sourceBundleIDs() == ["app.edge", "app.slack"]) // 출처 없는 항목은 목록에 없음
}

@MainActor
@Test func deleteAndRestoreKeepsEverything() throws {
    let store = try ClipStore(url: nil)
    let at = Date(timeIntervalSince1970: 1000)
    try store.add(ClipContent(kind: .link, text: "https://example.com"), sourceBundleID: "app.one", at: at)
    let item = try #require(try store.recent().first)
    item.isPinned = true
    item.title = "예시"
    item.linkTitle = "Example"
    try store.save()

    let deleted = try store.delete(item)
    #expect(try store.recent().isEmpty)
    try store.restore(deleted)
    let restored = try #require(try store.recent().first)
    #expect(restored.text == "https://example.com" && restored.kind == .link)
    #expect(restored.sourceBundleID == "app.one" && restored.copiedAt == at)
    #expect(restored.isPinned && restored.title == "예시" && restored.linkTitle == "Example")
    #expect(try store.search("예시").count == 1) // 이름도 검색된다
}

@MainActor
@Test func editReclassifiesAndDropsFormatting() throws {
    let store = try ClipStore(url: nil)
    try store.add(ClipContent(kind: .richText, text: "hello", payload: Data([1]), payloadType: "public.rtf"), sourceBundleID: "app.one")
    let item = try #require(try store.recent().first)
    item.title = "인사"

    try store.edit(item, newText: "https://example.com")
    #expect(item.kind == .link && item.payload == nil && item.text == "https://example.com")
    #expect(item.title == "인사" && item.sourceBundleID == "app.one") // 이름·출처는 유지

    try store.edit(item, newText: "")
    #expect(item.text == "https://example.com") // 빈 내용은 무시

    // 고친 내용을 다시 복사하면 새 항목이 아니라 이 항목이 앞으로 온다 (해시 갱신)
    try store.add(ClipContent(kind: .link, text: "https://example.com"), sourceBundleID: nil)
    #expect(try store.recent().count == 1)
}

@MainActor
@Test func imagesAndFilesAreNotEditable() throws {
    let store = try ClipStore(url: nil)
    try store.add(ClipContent(kind: .image, text: "", payload: Data([1]), payloadType: "public.png"), sourceBundleID: nil)
    let image = try #require(try store.recent().first)
    try store.edit(image, newText: "text")
    #expect(image.kind == .image && image.payload == Data([1]))
}

@Test func excludedPatternMatchesWholeTrimmedText() {
    let otp = [#"^\d{6}$"#]
    #expect(PasteboardRules.matchesExcludedPattern("123456", patterns: otp))
    #expect(PasteboardRules.matchesExcludedPattern(" 123456\n", patterns: otp))
    #expect(!PasteboardRules.matchesExcludedPattern("1234567", patterns: otp))
    #expect(!PasteboardRules.matchesExcludedPattern("code 123456", patterns: otp))
    #expect(!PasteboardRules.matchesExcludedPattern("123456", patterns: ["("])) // 잘못된 패턴은 무시
    #expect(!PasteboardRules.isValidPattern("("))
}

@Test func ignoresConcealedTypes() {
    #expect(PasteboardRules.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
    #expect(!PasteboardRules.shouldIgnore(types: ["public.utf8-plain-text"]))
}
