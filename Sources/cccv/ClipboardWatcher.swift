import AppKit
import CCCVCore

/// NSPasteboard 에는 변경 알림이 없어서 changeCount 를 폴링한다.
@MainActor
final class ClipboardWatcher {
    var onNewText: (@MainActor (String, String?) -> Void)?

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !History.shouldIgnore(types: types),
              let text = pasteboard.string(forType: .string) else { return }
        onNewText?(text, NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
}
