import Foundation
import Testing
@testable import CCCVCore

private func labels(_ text: String) -> [String] { Transform.available(for: text).map(\.label) }
private func result(_ text: String, _ label: String) -> String? {
    Transform.available(for: text).first { $0.label == label }?.result
}

@Test func urlDecodeAndEncode() {
    #expect(result("https://a.com/%EB%A0%88%EA%B1%B0%EC%8B%9C", "URL 디코드") == "https://a.com/레거시")
    #expect(result("a b&c=d", "URL 인코드") == "a%20b%26c%3Dd")
    #expect(!labels("plain").contains("URL 디코드"))
}

@Test func jsonKeepsKeyOrderAndNumbers() {
    let raw = #"{"z":1.0,"a":[1,2,{}],"s":"x, y: {z}"}"#
    #expect(result(raw, "JSON 정리") == """
    {
      "z": 1.0,
      "a": [
        1,
        2,
        {}
      ],
      "s": "x, y: {z}"
    }
    """)
    #expect(result(result(raw, "JSON 정리")!, "JSON 한 줄로") == raw)
    #expect(!labels("123").contains("JSON 정리")) // 숫자 하나는 JSON 이지만 정리할 게 없다
    #expect(!labels("{broken").contains("JSON 정리"))
}

@Test func base64OnlyWhenReadable() {
    #expect(result("aGVsbG8gd29ybGQ=", "Base64 디코드") == "hello world")
    #expect(result("aGVsbG8gd29ybGQ", "Base64 디코드") == "hello world") // 패딩 없어도
    #expect(!labels("test").contains("Base64 디코드")) // 풀리긴 하지만 읽을 수 없는 바이트
    #expect(result("hi", "Base64 인코드") == "aGk=")
}

@Test func jwtShowsHeaderAndPayload() {
    let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln"
    #expect(result(jwt, "JWT 해독 (서명 미검증)") == """
    // header
    {
      "alg": "HS256"
    }

    // payload
    {
      "sub": "1"
    }
    """)
    #expect(!labels("a.b.c").contains("JWT 해독 (서명 미검증)"))
}

@Test func timestampSecondsAndMillis() {
    let utc = TimeZone(identifier: "UTC")!
    #expect(Transform.timestampToDate("1700000000", timeZone: utc) == "2023-11-14 22:13:20 Z")
    #expect(Transform.timestampToDate("1700000000123", timeZone: utc) == "2023-11-14 22:13:20 Z")
    #expect(Transform.timestampToDate("123456", timeZone: utc) == nil)
}

@Test func identifierCases() {
    #expect(result("userId", "snake_case") == "user_id")
    #expect(result("user_id", "camelCase") == "userId")
    #expect(result("user-id", "camelCase") == "userId")
    #expect(result("HTTPServerError", "kebab-case") == "http-server-error")
    #expect(!labels("userId").contains("camelCase")) // 이미 camelCase 면 목록에서 빠진다
    #expect(!labels("hello world").contains("snake_case")) // 공백이 있으면 식별자가 아니다
    #expect(!labels("user").contains("snake_case")) // 한 단어
}

@Test func aiTransformsOnlyForProse() {
    #expect(AITransform.available(for: "안녕하세요 반갑습니다") == [.polish, .toEnglish])
    #expect(AITransform.available(for: "hello there") == [.polish, .toKorean])
    #expect(AITransform.available(for: String(repeating: "긴 글 ", count: 70)).first == .summarize)
    #expect(AITransform.available(for: "https://example.com/a").isEmpty)
    #expect(AITransform.available(for: #"{"a": 1, "b": 2}"#).isEmpty)
}
