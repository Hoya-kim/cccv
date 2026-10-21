import Carbon
import CCCVCore

/// Carbon RegisterEventHotKey 기반 글로벌 단축키. 앱에 하나만 등록한다.
@MainActor
final class HotKey {
    private static var action: (() -> Void)?
    private var ref: EventHotKeyRef?

    init(action: @escaping () -> Void) {
        HotKey.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// 기존 등록을 풀고 새 조합으로 등록한다. 실패하면 false.
    @discardableResult
    func register(_ combo: HotKeyCombo) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x6363_6376), id: 1) // 'cccv'
        let status = RegisterEventHotKey(UInt32(combo.keyCode), UInt32(combo.modifiers), id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    /// 설정에서 새 조합을 기록하는 동안 현재 단축키가 가로채지 않도록 잠시 푼다.
    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
