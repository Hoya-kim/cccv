public enum PasteboardRules {
    /// nspasteboard.org 관례: 비밀번호 관리자 등은 이 타입을 붙여 "저장하지 말 것"을 표시한다.
    public static let ignoredTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
    ]

    /// cccv 가 붙여넣기 위해 직접 쓴 항목 표시. 감시기는 이 표시가 있으면 새 복사로 보지 않는다.
    public static let ownType = "local.cccv.own"

    public static func shouldIgnore(types: [String]) -> Bool {
        types.contains(where: ignoredTypes.contains)
    }

    /// 앞뒤 공백을 뺀 내용 전체가 패턴 중 하나와 일치하면 true. 잘못된 패턴은 건너뛴다.
    /// 출처를 알 수 없는 메뉴바 앱(OTP 등)의 복사를 내용으로 거르기 위한 것.
    public static func matchesExcludedPattern(_ text: String, patterns: [String]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return patterns.contains { pattern in
            (try? Regex(pattern)).flatMap { try? $0.wholeMatch(in: trimmed) } != nil
        }
    }

    public static func isValidPattern(_ pattern: String) -> Bool {
        !pattern.isEmpty && (try? Regex(pattern)) != nil
    }
}
