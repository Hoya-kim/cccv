import Testing
@testable import CCCVCore

@Test func newestFirstAndDedupe() {
    var history = History()
    history.add(text: "a", sourceBundleID: nil)
    history.add(text: "b", sourceBundleID: nil)
    history.add(text: "a", sourceBundleID: nil)
    #expect(history.items.map(\.text) == ["a", "b"])
}

@Test func ignoresEmptyAndTrimsToLimit() {
    var history = History(limit: 2)
    history.add(text: "", sourceBundleID: nil)
    ["1", "2", "3"].forEach { history.add(text: $0, sourceBundleID: nil) }
    #expect(history.items.map(\.text) == ["3", "2"])
}

@Test func ignoresConcealedTypes() {
    #expect(History.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
    #expect(!History.shouldIgnore(types: ["public.utf8-plain-text"]))
}
