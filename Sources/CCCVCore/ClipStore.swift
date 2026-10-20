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
    public func recent(limit: Int = 200) throws -> [ClipItem] {
        var descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.copiedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
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
