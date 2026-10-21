import Testing
@testable import CCCVCore

@Test func defaultIsShiftCommandV() {
    #expect(HotKeyCombo.default.display == "⇧⌘V")
    #expect(HotKeyCombo.default.tokens == ["⇧", "⌘", "V"])
}

@Test func tokensFollowMenuOrder() {
    let all = HotKeyCombo(keyCode: 49, modifiers: HotKeyCombo.command | HotKeyCombo.shift | HotKeyCombo.option | HotKeyCombo.control, keyLabel: "Space")
    #expect(all.tokens == ["⌃", "⌥", "⇧", "⌘", "Space"])
}

@Test func requiresCommandOptionOrControl() {
    #expect(HotKeyCombo(keyCode: 9, modifiers: HotKeyCombo.option, keyLabel: "V").isAcceptable)
    #expect(!HotKeyCombo(keyCode: 9, modifiers: HotKeyCombo.shift, keyLabel: "V").isAcceptable)
    #expect(!HotKeyCombo(keyCode: 9, modifiers: 0, keyLabel: "V").isAcceptable)
}
