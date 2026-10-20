import AppKit
import CCCVCore

/// NSPasteboard 에는 변경 알림이 없어서 changeCount 를 폴링한다.
@MainActor
final class ClipboardWatcher {
    var onNewContent: (@MainActor (ClipContent, String?) -> Void)?

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

        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !PasteboardRules.shouldIgnore(types: types), let content = readContent() else { return }
        // 실행 전 복사분과 cccv 자신이 쓴 항목은 출처를 알 수 없다 (frontmost 는 엉뚱한 앱).
        let knowsSource = !isFirstRead && !types.contains(PasteboardRules.ownType)
        onNewContent?(content, knowsSource ? NSWorkspace.shared.frontmostApplication?.bundleIdentifier : nil)
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
