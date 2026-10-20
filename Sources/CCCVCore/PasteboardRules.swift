public enum PasteboardRules {
    /// nspasteboard.org 관례: 비밀번호 관리자 등은 이 타입을 붙여 "저장하지 말 것"을 표시한다.
    public static let ignoredTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
    ]

    /// cccv 가 붙여넣기 위해 직접 쓴 항목 표시. 출처를 대상 앱으로 덮어쓰지 않으려고 쓴다.
    public static let ownType = "local.cccv.own"

    public static func shouldIgnore(types: [String]) -> Bool {
        types.contains(where: ignoredTypes.contains)
    }
}
