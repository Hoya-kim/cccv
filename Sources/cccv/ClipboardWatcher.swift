import AppKit
import CCCVCore

/// NSPasteboard 에는 변경 알림이 없어서 changeCount 를 폴링한다.
@MainActor
final class ClipboardWatcher {
    var onNewContent: (@MainActor (ClipContent, String?) -> Void)?
    /// 일시정지 중 복사한 내용은 재개 후에도 기록하지 않는다 (changeCount 는 계속 따라간다).
    var isPaused = false

    private let pasteboard = NSPasteboard.general
    /// nil 이면 아직 한 번도 읽지 않은 상태 → 첫 poll 에서 실행 전부터 있던 클립보드를 받는다.
    private var lastChangeCount: Int?
    private var timer: Timer?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        let isFirstRead = lastChangeCount == nil
        lastChangeCount = pasteboard.changeCount
        guard !isPaused else { return }

        let types = pasteboard.types?.map(\.rawValue) ?? []
        // cccv 가 붙여넣으려고 쓴 내용은 새 복사가 아니다 (⇧Return 텍스트가 새 항목으로 쌓이는 것 방지).
        guard !PasteboardRules.shouldIgnore(types: types), !types.contains(PasteboardRules.ownType) else { return }
        // 실행 전 복사분은 출처를 알 수 없다 (frontmost 는 엉뚱한 앱).
        let source = isFirstRead ? nil : NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // 내용을 읽기 전에 거른다 — 제외 앱의 데이터는 메모리에도 올리지 않는다.
        if let source, AppSettings.excludedBundleIDs.contains(source) { return }
        guard let content = readContent(),
              !PasteboardRules.matchesExcludedPattern(content.text, patterns: AppSettings.excludedPatterns.map(\.pattern))
        else { return }
        onNewContent?(content, source)
    }

    private func readContent() -> ClipContent? {
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return ClipContent.classify(
            fileURLs: fileURLs ?? [],
            string: pasteboard.string(forType: .string),
            rtf: pasteboard.data(forType: .rtf),
            html: pasteboard.data(forType: .html),
            image: readImage
        )
    }

    /// PNG 가 있으면 그대로, TIFF 만 있으면 PNG 로 줄여 저장한다 (스크린샷 TIFF 는 수십 MB).
    private func readImage() -> (data: Data, type: String)? {
        if let png = pasteboard.data(forType: .png) { return (png, NSPasteboard.PasteboardType.png.rawValue) }
        guard let tiff = pasteboard.data(forType: .tiff) else { return nil }
        if let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return (png, NSPasteboard.PasteboardType.png.rawValue)
        }
        return (tiff, NSPasteboard.PasteboardType.tiff.rawValue)
    }
}
