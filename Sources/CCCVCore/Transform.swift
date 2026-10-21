import Foundation

/// 개발자 변환 액션. apply 가 nil 이면 그 입력에는 쓸 수 없는 변환이다.
public struct Transform: Sendable {
    public let label: String
    public let apply: @Sendable (String) -> String?

    /// 입력에 쓸 수 있는 변환과 결과. 결과가 입력과 같으면 뺀다.
    public static func available(for text: String) -> [(label: String, result: String)] {
        all.compactMap { transform in
            guard let result = transform.apply(text), result != text else { return nil }
            return (transform.label, result)
        }
    }

    // 순서가 곧 ⌘T 목록의 번호다.
    public static let all: [Transform] = [
        Transform(label: "URL 디코드") { $0.contains("%") ? $0.removingPercentEncoding : nil },
        Transform(label: "URL 인코드") { $0.addingPercentEncoding(withAllowedCharacters: unreserved) },
        Transform(label: "JSON 정리") { JSONText.isContainer($0) ? JSONText.reformat($0, pretty: true) : nil },
        Transform(label: "JSON 한 줄로") { JSONText.isContainer($0) ? JSONText.reformat($0, pretty: false) : nil },
        Transform(label: "Base64 디코드") { Base64.decodeText($0) },
        Transform(label: "Base64 인코드") { Data($0.utf8).base64EncodedString() },
        Transform(label: "JWT 해독 (서명 미검증)", apply: decodeJWT),
        Transform(label: "타임스탬프 → 날짜") { timestampToDate($0, timeZone: .current) },
        Transform(label: "camelCase") { Identifier.words($0).map(Identifier.camel) },
        Transform(label: "snake_case") { Identifier.words($0).map { $0.joined(separator: "_") } },
        Transform(label: "kebab-case") { Identifier.words($0).map { $0.joined(separator: "-") } },
    ]

    /// RFC 3986 unreserved — 쿼리 값 하나로 넣을 수 있게 & = / ? 까지 인코딩한다.
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func decodeJWT(_ text: String) -> String? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let header = Base64.decodeText(String(parts[0])), JSONText.isContainer(header),
              let payload = Base64.decodeText(String(parts[1])), JSONText.isContainer(payload)
        else { return nil }
        return "// header\n\(JSONText.reformat(header, pretty: true))\n\n// payload\n\(JSONText.reformat(payload, pretty: true))"
    }

    /// 10자리(초)·13자리(밀리초) 숫자만 받는다. 그 외 숫자는 타임스탬프인지 알 수 없다.
    static func timestampToDate(_ text: String, timeZone: TimeZone) -> String? {
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [10, 13].contains(digits.count), digits.allSatisfy(\.isASCII), let value = Double(digits) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        return formatter.string(from: Date(timeIntervalSince1970: digits.count == 13 ? value / 1000 : value))
    }
}

enum Base64 {
    /// base64·base64url 모두 받는다. 풀린 결과가 사람이 읽을 텍스트(UTF-8, 제어문자 없음)일 때만.
    static func decodeText(_ text: String) -> String? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard s.count >= 4, s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=".contains($0)) }) else { return nil }
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        guard let data = Data(base64Encoded: s), let decoded = String(data: data, encoding: .utf8),
              !decoded.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && !"\n\r\t".unicodeScalars.contains($0) })
        else { return nil }
        return decoded
    }
}

/// 원문의 키 순서·숫자 표기를 그대로 두고 공백만 바꾼다 (JSONSerialization 으로 다시 쓰면 둘 다 바뀐다).
enum JSONText {
    static func isContainer(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        return object is [Any] || object is [String: Any]
    }

    static func reformat(_ text: String, pretty: Bool) -> String {
        var out = ""
        var depth = 0
        var inString = false
        var escaped = false
        let chars = Array(text)
        var i = 0
        func newline() { if pretty { out += "\n" + String(repeating: "  ", count: depth) } }

        while i < chars.count {
            let c = chars[i]
            defer { i += 1 }
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"":
                inString = true
                out.append(c)
            case "{", "[":
                // 빈 컨테이너는 {} / [] 로 붙여 쓴다.
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == (c == "{" ? "}" : "]") {
                    out += c == "{" ? "{}" : "[]"
                    i = j
                } else {
                    out.append(c)
                    depth += 1
                    newline()
                }
            case "}", "]":
                depth -= 1
                newline()
                out.append(c)
            case ",":
                out.append(c)
                newline()
            case ":":
                out += pretty ? ": " : ":"
            case _ where c.isWhitespace:
                break
            default:
                out.append(c)
            }
        }
        return out
    }
}

enum Identifier {
    /// 공백 없는 식별자를 소문자 단어로 나눈다. "userId", "user_id", "user-id", "HTTPServer" → [user, id] 등.
    static func words(_ text: String) -> [String]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 80, let first = trimmed.first, first.isASCII, first.isLetter,
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { return nil }
        var words: [String] = []
        var current = ""
        let chars = Array(trimmed)
        for (i, c) in chars.enumerated() {
            if c == "_" || c == "-" {
                if !current.isEmpty { words.append(current) }
                current = ""
                continue
            }
            // aB → a|B, ABc → A|Bc (약어 뒤 단어 시작)
            let prev = i > 0 ? chars[i - 1] : nil
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            if c.isUppercase, let prev, !current.isEmpty,
               prev.isLowercase || prev.isNumber || (prev.isUppercase && next?.isLowercase == true) {
                words.append(current)
                current = ""
            }
            current.append(c)
        }
        if !current.isEmpty { words.append(current) }
        let lower = words.map { $0.lowercased() }
        return lower.count >= 2 ? lower : nil // 한 단어는 바꿀 게 없다
    }

    static func camel(_ words: [String]) -> String {
        words.enumerated().map { $0.offset == 0 ? $0.element : $0.element.prefix(1).uppercased() + $0.element.dropFirst() }.joined()
    }
}
