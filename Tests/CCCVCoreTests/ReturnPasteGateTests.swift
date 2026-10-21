import Testing
@testable import CCCVCore

@Test func returnDoesNotPasteUntilKeyUp() {
    var gate = ReturnPasteGate()
    #expect(gate.handle(.returnDown(triggersPaste: true)) == .consume)
    #expect(gate.pasteOnKeyUp)
    #expect(gate.swallowKeyUp)
    #expect(gate.handle(.returnUp) == .paste)
    #expect(gate.pasteOnKeyUp == false)
    #expect(gate.swallowKeyUp == false)
}

@Test func keyRepeatPastesOnce() {
    var gate = ReturnPasteGate()
    #expect(gate.handle(.returnDown(triggersPaste: true)) == .consume)
    #expect(gate.handle(.returnDown(triggersPaste: true)) == .consume)
    #expect(gate.handle(.returnUp) == .paste)
    // 붙여넣은 뒤 따라온 keyUp 은 대상 앱으로 보내도 되는 보통 키다.
    #expect(gate.handle(.returnUp) == .pass)
}

@Test func renameConsumesKeyUpWithoutPaste() {
    var gate = ReturnPasteGate()
    #expect(gate.handle(.returnDown(triggersPaste: false)) == .consume)
    #expect(gate.handle(.returnUp) == .consume)
}

@Test func unarmedKeyUpPasses() {
    // 내용 편집의 Return 은 줄바꿈이라 keyDown 을 게이트에 넣지 않는다.
    // keyUp 도 편집기로 가야 한다.
    var gate = ReturnPasteGate()
    #expect(gate.handle(.returnUp) == .pass)
}

@Test func cancelDropsArmedPaste() {
    var gate = ReturnPasteGate()
    #expect(gate.handle(.returnDown(triggersPaste: true)) == .consume)
    #expect(gate.handle(.cancel) == .consume)
    #expect(gate.handle(.returnUp) == .pass)
    #expect(gate.pasteOnKeyUp == false)
}

@Test func cancelThenReturnCanPasteAgain() {
    var gate = ReturnPasteGate()
    gate.handle(.returnDown(triggersPaste: true))
    gate.handle(.cancel)
    #expect(gate.handle(.returnDown(triggersPaste: true)) == .consume)
    #expect(gate.handle(.returnUp) == .paste)
}

@Test func laterReturnCanPasteAgain() {
    var gate = ReturnPasteGate()
    #expect(gate.handle(.returnDown(triggersPaste: true)) == .consume)
    #expect(gate.handle(.returnUp) == .paste)
    #expect(gate.handle(.returnDown(triggersPaste: true)) == .consume)
    #expect(gate.handle(.returnUp) == .paste)
}
