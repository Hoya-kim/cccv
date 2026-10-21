import CryptoKit
import Foundation

public enum ClipKind: String, CaseIterable, Sendable {
    case text, richText, link, color, image, file

    public var label: String {
        switch self {
        case .text: "텍스트"
        case .richText: "서식 텍스트"
        case .link: "링크"
        case .color: "색상"
        case .image: "이미지"
        case .file: "파일"
        }
    }
}

/// 바의 검색 조건 중 검색어를 뺀 나머지. nil 은 "전부".
public struct ClipFilter: Equatable, Sendable {
    public var pinnedOnly = false
    public var kind: ClipKind?
    public var sourceBundleID: String?

    public init(pinnedOnly: Bool = false, kind: ClipKind? = nil, sourceBundleID: String? = nil) {
        self.pinnedOnly = pinnedOnly
        self.kind = kind
        self.sourceBundleID = sourceBundleID
    }

    /// 전체/고정 외에 종류·앱 필터가 걸려 있는지 (드롭다운 버튼 표시용).
    public var narrowsContent: Bool { kind != nil || sourceBundleID != nil }
}

/// 클립보드에서 읽어 낸 한 건. 저장 전 단계의 값 타입.
public struct ClipContent: Equatable, Sendable {
    public var kind: ClipKind
    /// 표시·검색·일반 텍스트 붙여넣기용. 파일은 경로를 줄바꿈으로 이어 붙인다.
    public var text: String
    /// 원본 데이터 (RTF, HTML, PNG 등). 텍스트만으로 충분한 종류는 nil.
    public var payload: Data?
    public var payloadType: String?

    public init(kind: ClipKind, text: String, payload: Data? = nil, payloadType: String? = nil) {
        self.kind = kind
        self.text = text
        self.payload = payload
        self.payloadType = payloadType
    }

    public var isEmpty: Bool { text.isEmpty && payload == nil }

    /// 중복 판정 키.
    public var contentHash: String {
        Self.hash(kind: kind, text: text, payload: payload)
    }

    static func hash(kind: ClipKind, text: String, payload: Data?) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(text.utf8))
        hasher.update(data: Data([0]))
        if let payload { hasher.update(data: payload) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 우선순위: 파일 > 색상 > 링크 > 리치텍스트 > 텍스트 > 이미지.
    /// 텍스트와 이미지가 함께 오면(표 셀 복사 등) 텍스트를 택한다. image 는 필요할 때만 읽는다.
    public static func classify(
        fileURLs: [URL],
        string: String?,
        rtf: Data?,
        html: Data?,
        image: () -> (data: Data, type: String)?
    ) -> ClipContent? {
        if !fileURLs.isEmpty {
            return ClipContent(kind: .file, text: fileURLs.map(\.path).joined(separator: "\n"))
        }
        if let string, !string.isEmpty {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if hexColor(trimmed) != nil { return ClipContent(kind: .color, text: trimmed) }
            if isWebURL(trimmed) { return ClipContent(kind: .link, text: trimmed) }
            if let rtf { return ClipContent(kind: .richText, text: string, payload: rtf, payloadType: "public.rtf") }
            if let html { return ClipContent(kind: .richText, text: string, payload: html, payloadType: "public.html") }
            return ClipContent(kind: .text, text: string)
        }
        if let image = image() {
            return ClipContent(kind: .image, text: "", payload: image.data, payloadType: image.type)
        }
        return nil
    }

    /// "#rgb", "#rrggbb", "#rrggbbaa" → 0...1 성분. '#' 없는 문자열은 단어("facade")와 구분이 안 돼 받지 않는다.
    public static func hexColor(_ string: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        guard string.hasPrefix("#") else { return nil }
        var hex = String(string.dropFirst())
        guard [3, 6, 8].contains(hex.count), let value = UInt64(hex, radix: 16) else { return nil }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
            return hexColor("#" + hex)
        }
        let hasAlpha = hex.count == 8
        let rgba = hasAlpha ? value : (value << 8) | 0xFF
        return (
            Double((rgba >> 24) & 0xFF) / 255,
            Double((rgba >> 16) & 0xFF) / 255,
            Double((rgba >> 8) & 0xFF) / 255,
            Double(rgba & 0xFF) / 255
        )
    }

    static func isWebURL(_ string: String) -> Bool {
        guard !string.contains(where: \.isWhitespace),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme) && url.host() != nil
    }
}
