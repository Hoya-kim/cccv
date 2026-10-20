import AppKit
import CCCVCore
import LinkPresentation
import UniformTypeIdentifiers

/// 링크 카드가 처음 보일 때 OG 메타데이터(제목·대표 이미지)를 가져와 저장한다.
@MainActor
enum LinkPreview {
    static func fetchIfNeeded(_ item: ClipItem, store: ClipStore) {
        // 꺼져 있으면 시도 표시도 남기지 않는다 — 다시 켜면 그때 가져온다.
        guard AppSettings.linkPreviewEnabled,
              item.kind == .link, item.linkFetchedAt == nil, let url = URL(string: item.text) else { return }
        // 먼저 시도 표시를 남긴다 — 카드가 여러 번 그려져도 한 번만 요청하고, 실패하면 URL 표시로 남는다.
        item.linkFetchedAt = Date()
        try? store.save()

        Task {
            let provider = LPMetadataProvider()
            provider.timeout = 5
            guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return }
            item.linkTitle = metadata.title
            item.linkImage = await imageData(from: metadata.imageProvider ?? metadata.iconProvider)
            try? store.save()
        }
    }

    // ponytail: 원본 그대로 저장. 큰 OG 이미지가 많아 용량이 문제 되면 저장 시 축소.
    private static func imageData(from provider: NSItemProvider?) async -> Data? {
        guard let provider else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
