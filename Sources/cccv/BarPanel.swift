import AppKit
import CCCVCore

/// 대상 앱을 비활성화하지 않고 키 입력을 받는 패널.
final class BarPanel: NSPanel {
    /// 가로 바의 높이 = 세로 바의 너비.
    static let thickness: CGFloat = 300

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

    /// 마우스 커서가 있는 화면의 지정한 가장자리에 붙인다.
    func show(at position: BarPosition) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        let t = Self.thickness
        let frame = switch position {
        case .bottom: NSRect(x: v.minX, y: v.minY, width: v.width, height: t)
        case .top: NSRect(x: v.minX, y: v.maxY - t, width: v.width, height: t)
        case .left: NSRect(x: v.minX, y: v.minY, width: t, height: v.height)
        case .right: NSRect(x: v.maxX - t, y: v.minY, width: t, height: v.height)
        }
        setFrame(frame, display: true)
        makeKeyAndOrderFront(nil)
    }
}
