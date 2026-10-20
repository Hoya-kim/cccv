import AppKit

/// 대상 앱을 비활성화하지 않고 키 입력을 받는 패널.
final class BarPanel: NSPanel {
    static let height: CGFloat = 260

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }

    /// 마우스 커서가 있는 화면의 하단에 붙인다.
    func showAtBottomOfMouseScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        setFrame(NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: Self.height), display: true)
        makeKeyAndOrderFront(nil)
    }
}
