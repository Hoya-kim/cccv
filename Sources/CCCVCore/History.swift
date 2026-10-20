import Foundation

public struct ClipItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let sourceBundleID: String?
    public let copiedAt: Date

    public init(id: UUID = UUID(), text: String, sourceBundleID: String?, copiedAt: Date) {
        self.id = id
        self.text = text
        self.sourceBundleID = sourceBundleID
        self.copiedAt = copiedAt
    }
}

/// 최신 항목이 앞에 오는 클립보드 히스토리.
public struct History: Sendable {
    // ponytail: M0 는 메모리 보관 + 개수 제한만. 영속화·보존 기간은 M1 저장소에서.
    public private(set) var items: [ClipItem] = []
    public let limit: Int

    public init(limit: Int = 500) {
        self.limit = limit
    }

    /// 같은 텍스트가 이미 있으면 맨 앞으로 옮긴다. 빈 문자열은 무시한다.
    public mutating func add(text: String, sourceBundleID: String?, at date: Date = Date()) {
        guard !text.isEmpty else { return }
        items.removeAll { $0.text == text }
        items.insert(ClipItem(text: text, sourceBundleID: sourceBundleID, copiedAt: date), at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
    }

    /// nspasteboard.org 관례: 비밀번호 관리자 등은 이 타입을 붙여 "저장하지 말 것"을 표시한다.
    public static let ignoredTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
    ]

    public static func shouldIgnore(types: [String]) -> Bool {
        types.contains(where: ignoredTypes.contains)
    }
}
