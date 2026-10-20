import AppKit
import Carbon
import CCCVCore

@MainActor
enum Paster {
    /// 클립보드에 쓰고 ⌘V 를 합성한다. 접근성 권한이 없으면 클립보드 복사까지만 한다.
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: .init(PasteboardRules.ownType))

        guard AXIsProcessTrusted() else { return }

        // 패널이 내려간 뒤 대상 앱 창이 키 입력을 받을 시간을 둔다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: keyDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
