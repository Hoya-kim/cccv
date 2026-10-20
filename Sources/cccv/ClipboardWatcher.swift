import AppKit
import CCCVCore

/// NSPasteboard 에는 변경 알림이 없어서 changeCount 를 폴링한다.
@MainActor
final class ClipboardWatcher {
    var onNewText: (@MainActor (String, String?) -> Void)?

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
        guard !PasteboardRules.shouldIgnore(types: types),
              let text = pasteboard.string(forType: .string) else { return }
        // 실행 전 복사분과 cccv 자신이 쓴 항목은 출처를 알 수 없다 (frontmost 는 엉뚱한 앱).
        let knowsSource = !isFirstRead && !types.contains(PasteboardRules.ownType)
        onNewText?(text, knowsSource ? NSWorkspace.shared.frontmostApplication?.bundleIdentifier : nil)
    }
}
