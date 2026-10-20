import Foundation
import SwiftData

@Model
public final class ClipItem {
    public var text: String
    public var sourceBundleID: String?
    public var copiedAt: Date

    public init(text: String, sourceBundleID: String?, copiedAt: Date) {
        self.text = text
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
    }

    /// 같은 텍스트가 이미 있으면 새로 만들지 않고 맨 앞으로 올린다.
    /// sourceBundleID 가 nil 이면 (출처를 모를 때) 기존 출처를 덮어쓰지 않는다.
    public func add(text: String, sourceBundleID: String?, at date: Date = Date()) throws {
        guard !text.isEmpty else { return }
        let existing = try context.fetch(FetchDescriptor(predicate: #Predicate<ClipItem> { $0.text == text })).first
        if let existing {
            existing.copiedAt = date
            if let sourceBundleID { existing.sourceBundleID = sourceBundleID }
        } else {
            context.insert(ClipItem(text: text, sourceBundleID: sourceBundleID, copiedAt: date))
        }
        try context.save()
    }

    // ponytail: 바에는 최근 200개만 올린다. 전체 탐색은 검색(M1 4단계)에서 저장소 쿼리로.
    public func recent(limit: Int = 200) throws -> [ClipItem] {
        var descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.copiedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }
}
