import AppKit
import Carbon
import CCCVCore

@MainActor
enum Paster {
    /// 클립보드에 쓰고 ⌘V 를 합성한다. 접근성 권한이 없으면 클립보드 복사까지만 한다.
    /// plainText 면 서식 없이 텍스트만 쓴다 (파일은 경로 텍스트). 텍스트가 없는 이미지는 그대로 붙여넣는다.
    static func paste(_ item: ClipItem, plainText: Bool = false) {
        if plainText, !item.text.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(item.text, forType: .string)
            pasteboard.setData(Data(), forType: .init(PasteboardRules.ownType))
        } else {
            write(item, to: .general)
        }

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

    private static func write(_ item: ClipItem, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        switch item.kind {
        case .file:
            let urls = item.text.split(separator: "\n").map { NSURL(fileURLWithPath: String($0)) }
            pasteboard.writeObjects(urls)
        case .image:
            if let payload = item.payload, let type = item.payloadType {
                pasteboard.setData(payload, forType: .init(type))
            }
        case .richText:
            if let payload = item.payload, let type = item.payloadType {
                pasteboard.setData(payload, forType: .init(type))
            }
            pasteboard.setString(item.text, forType: .string)
        case .text, .link, .color:
            pasteboard.setString(item.text, forType: .string)
        }
        pasteboard.setData(Data(), forType: .init(PasteboardRules.ownType))
    }
}
