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
    /// 이미지 속 글자 (OCR, 검색 대상). ocrProcessed 가 true 면 시도한 것 — 실패해도 다시 하지 않는다.
    public var ocrText: String?
    public var ocrProcessed: Bool = false
    /// 민감정보 패턴에 걸려 이 시각에 지워질 항목. nil 이면 보존 기간만 따른다. 고정하면 nil 로 풀린다.
    public var expiresAt: Date?

    public var kind: ClipKind { ClipKind(rawValue: kindRaw) ?? .text }

    /// 검색어가 본문·이름·링크 제목·이미지 속 글자 중 하나에 들어 있는지.
    func matches(_ query: String) -> Bool {
        [text, title, linkTitle, ocrText].contains { $0?.localizedStandardContains(query) == true }
    }

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
    /// expiresAt 이 있으면 그 시각에 지워지는 민감정보 항목으로 저장한다 (고정된 기존 항목은 제외).
    public func add(_ content: ClipContent, sourceBundleID: String?, at date: Date = Date(), expiresAt: Date? = nil) throws {
        guard !content.isEmpty else { return }
        let hash = content.contentHash
        let existing = try context.fetch(FetchDescriptor(predicate: #Predicate<ClipItem> { $0.contentHash == hash })).first
        if let existing {
            existing.copiedAt = date
            if let sourceBundleID { existing.sourceBundleID = sourceBundleID }
            if let expiresAt, !existing.isPinned { existing.expiresAt = expiresAt }
        } else {
            let item = ClipItem(content: content, sourceBundleID: sourceBundleID, copiedAt: date)
            item.expiresAt = expiresAt
            context.insert(item)
        }
        try context.save()
    }

    /// 만료 시각이 지난 민감정보 항목을 지운다 (고정 항목 제외). 지운 건수를 돌려준다.
    @discardableResult
    public func purgeExpired(now: Date = Date()) throws -> Int {
        let expired = try context.fetch(FetchDescriptor(predicate: #Predicate<ClipItem> { item in
            item.expiresAt.flatMap { $0 <= now } ?? false
        })).filter { !$0.isPinned }
        guard !expired.isEmpty else { return 0 }
        expired.forEach(context.delete)
        try context.save()
        return expired.count
    }

    /// 조회한 모델 인스턴스를 직접 고친 뒤 저장할 때.
    public func save() throws {
        try context.save()
    }

    // ponytail: 바에는 최근 200개만 올린다. 전체 탐색은 검색(M1 4단계)에서 저장소 쿼리로.
    public func recent(limit: Int = 200) throws -> [ClipItem] {
        try search("", limit: limit)
    }

    /// 아직 글자 인식을 하지 않은 이미지 하나 (최신 것부터). 원본이 없으면 처리한 것으로 표시하고 다음으로.
    public func nextImageForOCR() throws -> (id: PersistentIdentifier, data: Data)? {
        let image = ClipKind.image.rawValue
        var descriptor = FetchDescriptor<ClipItem>(
            predicate: #Predicate { $0.kindRaw == image && !$0.ocrProcessed },
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        while let item = try context.fetch(descriptor).first {
            if let data = item.payload { return (item.persistentModelID, data) }
            item.ocrProcessed = true
            try context.save()
        }
        return nil
    }

    /// 인식 결과 저장. 그 사이 항목이 지워졌으면 아무것도 하지 않는다.
    public func setOCR(_ id: PersistentIdentifier, text: String?) throws {
        let descriptor = FetchDescriptor<ClipItem>(predicate: #Predicate { $0.persistentModelID == id })
        guard let item = try context.fetch(descriptor).first else { return }
        item.ocrText = text.flatMap { $0.isEmpty ? nil : $0 }
        item.ocrProcessed = true
        try context.save()
    }

    /// 필터 드롭다운에 보여 줄 출처 앱 목록 (기록에 있는 것만).
    // ponytail: 전 레코드 스캔. 보존 기간이 있어 규모가 작다.
    public func sourceBundleIDs() throws -> [String] {
        var descriptor = FetchDescriptor<ClipItem>()
        descriptor.propertiesToFetch = [\.sourceBundleID]
        return Set(try context.fetch(descriptor).compactMap(\.sourceBundleID)).sorted()
    }

    /// 본문·링크 제목·사용자 이름·이미지 속 글자에서 대소문자·발음 기호 무시하고 찾는다. 최신순.
    /// 필터(고정·종류·앱)는 DB 에서, 검색어는 메모리에서 맞춘다 — 한 #Predicate 에 다 넣으면 컴파일러가 타입 검사를 못 끝낸다.
    // ponytail: 검색어가 있으면 필터에 걸린 전체를 읽어 스캔. 보존 기간으로 규모가 작다. 수만 건이면 SQLite FTS5 로.
    public func search(_ query: String, filter: ClipFilter = ClipFilter(), limit: Int = 200) throws -> [ClipItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        let pinnedOnly = filter.pinnedOnly
        let anyKind = filter.kind == nil
        let kindRaw = filter.kind?.rawValue ?? ""
        let anyApp = filter.sourceBundleID == nil
        let appID = filter.sourceBundleID ?? ""
        var descriptor = FetchDescriptor<ClipItem>(
            predicate: #Predicate {
                (!pinnedOnly || $0.isPinned)
                    && (anyKind || $0.kindRaw == kindRaw)
                    && (anyApp || $0.sourceBundleID == appID)
            },
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        guard !query.isEmpty else {
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor)
        }
        return Array(try context.fetch(descriptor).lazy.filter { $0.matches(query) }.prefix(limit))
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
