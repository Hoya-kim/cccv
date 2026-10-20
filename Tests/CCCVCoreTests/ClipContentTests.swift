import Foundation
import Testing
@testable import CCCVCore

private func classify(
    files: [URL] = [], string: String? = nil, rtf: Data? = nil, html: Data? = nil, image: Data? = nil
) -> ClipContent? {
    ClipContent.classify(fileURLs: files, string: string, rtf: rtf, html: html) {
        image.map { ($0, "public.png") }
    }
}

@Test func classifyPriority() {
    #expect(classify(files: [URL(filePath: "/tmp/a.txt")], string: "a.txt")?.kind == .file)
    #expect(classify(string: " #FF00aa\n")?.kind == .color)
    #expect(classify(string: "https://example.com/a?b=1")?.kind == .link)
    #expect(classify(string: "hello", rtf: Data([1]))?.kind == .richText)
    #expect(classify(string: "hello", html: Data([1]))?.kind == .richText)
    #expect(classify(string: "hello", image: Data([1]))?.kind == .text) // 텍스트+이미지 → 텍스트
    #expect(classify(image: Data([1]))?.kind == .image)
    #expect(classify() == nil)
}

@Test func linkAndColorAreStrict() {
    #expect(classify(string: "see https://example.com")?.kind == .text)
    #expect(classify(string: "file:///etc/hosts")?.kind == .text)
    #expect(classify(string: "facade")?.kind == .text)
    #expect(classify(string: "#ggg")?.kind == .text)
}

@Test func hexColorComponents() throws {
    let short = try #require(ClipContent.hexColor("#f00"))
    #expect(short.r == 1 && short.g == 0 && short.b == 0 && short.a == 1)
    let alpha = try #require(ClipContent.hexColor("#00000080"))
    #expect(abs(alpha.a - 128.0 / 255) < 0.0001)
}

@Test func filesJoinPaths() {
    let content = classify(files: [URL(filePath: "/tmp/a"), URL(filePath: "/tmp/b")])
    #expect(content?.text == "/tmp/a\n/tmp/b")
}
