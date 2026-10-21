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
        firstMatchingPattern(text, patterns: patterns) != nil
    }

    /// 처음으로 일치한 패턴의 위치. 패턴마다 처리(기록 안 함 / N분 뒤 삭제)가 달라서 어느 것인지 알아야 한다.
    public static func firstMatchingPattern(_ text: String, patterns: [String]) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return patterns.firstIndex { pattern in
            (try? Regex(pattern)).flatMap { try? $0.wholeMatch(in: trimmed) } != nil
        }
    }

    /// 자주 쓰는 토큰 형식. 설정의 "추천 패턴" 메뉴에서 추가한다.
    public static let sensitivePresets: [(memo: String, pattern: String)] = [
        ("JWT", #"^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$"#),
        ("GitHub 토큰", #"^(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})$"#),
        ("AWS 액세스 키", #"^(AKIA|ASIA)[0-9A-Z]{16}$"#),
        ("Slack 토큰", #"^xox[abprs]-[A-Za-z0-9-]{10,}$"#),
    ]

    public static func isValidPattern(_ pattern: String) -> Bool {
        !pattern.isEmpty && (try? Regex(pattern)) != nil
    }
}
