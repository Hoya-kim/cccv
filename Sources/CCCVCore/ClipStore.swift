import Foundation
import SwiftData

@Model
public final class ClipItem {
    public var text: String
    // 기본값은 M1 ① 스키마(text 만 있던 레코드)에서 경량 마이그레이션하기 위해 필요하다.
    public var kindRaw: String = ClipKind.text.rawValue
    @Attribute(.externalStorage) public var payload: Data?
    public var payloadType: String?
    public var contentHash: String = ""
    public var sourceBundleID: String?
    public var copiedAt: Date
    // 링크 미리보기 (OG). linkFetchedAt 이 있으면 시도한 것 — 실패해도 다시 가져오지 않는다.
    public var linkTitle: String?
    @Attribute(.externalStorage) public var linkImage: Data?
    public var linkFetchedAt: Date?
    /// 고정 항목은 보존 기간이 지나도 지우지 않는다.
    public var isPinned: Bool = false
    /// 사용자가 붙인 이름 (검색 대상).
    public var title: String?

    public var kind: ClipKind { ClipKind(rawValue: kindRaw) ?? .text }

    public init(content: ClipContent, sourceBundleID: String?, copiedAt: Date) {
        text = content.text
        kindRaw = content.kind.rawValue
        payload = content.payload
        payloadType = content.payloadType
        contentHash = content.contentHash
        self.sourceBundleID = sourceBundleID
        self.copiedAt = copiedAt
    }
}

/// 클립보드 히스토리 저장소. 최신 항목이 앞에 온다.
@MainActor
public final class ClipStore {
    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "cccv/cccv.store")
    }

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// url 이 nil 이면 메모리 전용 (테스트용).
    public init(url: URL?) throws {
        let config: ModelConfiguration
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            config = ModelConfiguration(url: url)
        } else {
            config = ModelConfiguration(isStoredInMemoryOnly: true)
        }
        container = try ModelContainer(for: ClipItem.self, configurations: config)
        try backfillHashes()
    }

    /// 같은 내용이 이미 있으면 새로 만들지 않고 맨 앞으로 올린다.
    /// sourceBundleID 가 nil 이면 (출처를 모를 때) 기존 출처를 덮어쓰지 않는다.
    public func add(_ content: ClipContent, sourceBundleID: String?, at date: Date = Date()) throws {
        guard !content.isEmpty else { return }
        let hash = content.contentHash
        let existing = try context.fetch(FetchDescriptor(predicate: #Predicate<ClipItem> { $0.contentHash == hash })).first
        if let existing {
            existing.copiedAt = date
            if let sourceBundleID { existing.sourceBundleID = sourceBundleID }
        } else {
            context.insert(ClipItem(content: content, sourceBundleID: sourceBundleID, copiedAt: date))
        }
        try context.save()
    }

    /// 조회한 모델 인스턴스를 직접 고친 뒤 저장할 때.
    public func save() throws {
        try context.save()
    }

    // ponytail: 바에는 최근 200개만 올린다. 전체 탐색은 검색(M1 4단계)에서 저장소 쿼리로.
    public func recent(limit: Int = 200, pinnedOnly: Bool = false) throws -> [ClipItem] {
        var descriptor = FetchDescriptor<ClipItem>(
            predicate: #Predicate { !pinnedOnly || $0.isPinned },
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// 본문·링크 제목·사용자 이름에서 대소문자·발음 기호 무시하고 찾는다. 최신순.
    // ponytail: 키 입력마다 LIKE 스캔. 수만 건에서 느려지면 SQLite FTS5 로.
    public func search(_ query: String, pinnedOnly: Bool = false, limit: Int = 200) throws -> [ClipItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return try recent(limit: limit, pinnedOnly: pinnedOnly) }
        var descriptor = FetchDescriptor<ClipItem>(
            predicate: #Predicate {
                (!pinnedOnly || $0.isPinned) && (
                    $0.text.localizedStandardContains(query)
                        || ($0.linkTitle.flatMap { $0.localizedStandardContains(query) } ?? false)
                        || ($0.title.flatMap { $0.localizedStandardContains(query) } ?? false)
                )
            },
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// 보존 기간 정리 전에 삭제 대상 건수를 보여 주기 위한 것. 고정 항목은 세지 않는다.
    public func count(olderThan date: Date) throws -> Int {
        try context.fetchCount(FetchDescriptor(predicate: #Predicate<ClipItem> { $0.copiedAt < date && !$0.isPinned }))
    }

    /// date 이전에 복사한 항목을 지운다 (고정 항목 제외). 지운 건수를 돌려준다.
    // ponytail: SQLite 파일은 줄지 않고 빈 페이지를 재사용한다 (원본 파일은 externalStorage 라 함께 지워진다). 필요하면 VACUUM.
    @discardableResult
    public func purge(olderThan date: Date) throws -> Int {
        let old = try context.fetch(FetchDescriptor(predicate: #Predicate<ClipItem> { $0.copiedAt < date && !$0.isPinned }))
        guard !old.isEmpty else { return 0 }
        old.forEach(context.delete)
        try context.save()
        return old.count
    }

    /// 텍스트 계열 항목의 내용을 덮어쓴다. 종류는 새 내용으로 다시 판정한다
    /// (서식은 버려져 일반 텍스트가 되고, URL 로 고치면 링크가 된다). 빈 내용이면 무시한다.
    public func edit(_ item: ClipItem, newText: String) throws {
        guard item.kind != .image, item.kind != .file,
              let content = ClipContent.classify(fileURLs: [], string: newText, rtf: nil, html: nil, image: { nil })
        else { return }
        item.text = content.text
        item.kindRaw = content.kind.rawValue
        item.payload = nil
        item.payloadType = nil
        item.contentHash = content.contentHash
        // 링크가 바뀌었을 수 있으니 미리보기는 다시 가져오게 한다.
        item.linkTitle = nil
        item.linkImage = nil
        item.linkFetchedAt = nil
        try context.save()
    }

    /// 사용자가 지운 항목. 되돌리기(⌘Z)를 위해 필드를 전부 값으로 들고 있는다.
    public struct DeletedClip: Sendable {
        let content: ClipContent
        let sourceBundleID: String?
        let copiedAt: Date
        let linkTitle: String?
        let linkImage: Data?
        let linkFetchedAt: Date?
        let isPinned: Bool
        let title: String?
    }

    public func delete(_ item: ClipItem) throws -> DeletedClip {
        let deleted = DeletedClip(
            content: ClipContent(kind: item.kind, text: item.text, payload: item.payload, payloadType: item.payloadType),
            sourceBundleID: item.sourceBundleID, copiedAt: item.copiedAt,
            linkTitle: item.linkTitle, linkImage: item.linkImage, linkFetchedAt: item.linkFetchedAt,
            isPinned: item.isPinned, title: item.title
        )
        context.delete(item)
        try context.save()
        return deleted
    }

    public func restore(_ deleted: DeletedClip) throws {
        let item = ClipItem(content: deleted.content, sourceBundleID: deleted.sourceBundleID, copiedAt: deleted.copiedAt)
        item.linkTitle = deleted.linkTitle
        item.linkImage = deleted.linkImage
        item.linkFetchedAt = deleted.linkFetchedAt
        item.isPinned = deleted.isPinned
        item.title = deleted.title
        context.insert(item)
        try context.save()
    }

    /// 해시 컬럼이 생기기 전에 저장된 레코드를 채운다. 없으면 아무것도 하지 않는다.
    private func backfillHashes() throws {
        let missing = try context.fetch(FetchDescriptor(predicate: #Predicate<ClipItem> { $0.contentHash == "" }))
        guard !missing.isEmpty else { return }
        for item in missing {
            item.contentHash = ClipContent.hash(kind: item.kind, text: item.text, payload: item.payload)
        }
        try context.save()
    }
}
