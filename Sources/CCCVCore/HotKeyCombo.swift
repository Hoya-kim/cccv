/// 글로벌 단축키 조합. modifiers 는 Carbon 값 (RegisterEventHotKey 에 그대로 넘긴다).
public struct HotKeyCombo: Equatable, Sendable {
    // Carbon.HIToolbox 의 cmdKey·shiftKey·optionKey·controlKey 와 같은 값 (Core 는 Carbon 을 import 하지 않는다).
    public static let command = 1 << 8
    public static let shift = 1 << 9
    public static let option = 1 << 11
    public static let control = 1 << 12

    /// 기본값 ⇧⌘V (kVK_ANSI_V = 9).
    public static let `default` = HotKeyCombo(keyCode: 9, modifiers: command | shift, keyLabel: "V")

    public var keyCode: Int
    public var modifiers: Int
    /// 기록할 때 눌린 키의 표시 이름 ("V", "Space" 등).
    public var keyLabel: String

    public init(keyCode: Int, modifiers: Int, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// 키캡으로 나눠 그릴 토큰. macOS 메뉴와 같은 ⌃⌥⇧⌘ 순서.
    public var tokens: [String] {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1) + [keyLabel]
    }

    public var display: String { tokens.joined() }

    /// ⌘·⌥·⌃ 중 하나는 있어야 한다. ⇧ 만 있거나 수식키가 없으면 모든 앱에서 그 글자를 칠 수 없게 된다.
    public var isAcceptable: Bool {
        modifiers & (Self.command | Self.option | Self.control) != 0
    }
}
