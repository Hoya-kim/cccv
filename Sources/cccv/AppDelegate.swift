import AppKit
import Carbon
import CCCVCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ClipStore!
    private let model = BarModel()
    private let watcher = ClipboardWatcher()
    private let panel = BarPanel()
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try ClipStore(url: ClipStore.defaultURL)
        } catch {
            // 저장소 파일은 건드리지 않고 종료한다 (기록 유실 방지).
            fatalError("cccv: 저장소를 열 수 없습니다 \(ClipStore.defaultURL.path): \(error)")
        }
        setUpStatusItem()

        panel.contentView = NSHostingView(rootView: BarView(model: model) { [weak self] index in
            self?.pick(index)
        })
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }

        watcher.onNewContent = { [weak self] content, source in
            guard let self else { return }
            do {
                try store.add(content, sourceBundleID: source)
            } catch {
                NSLog("cccv: 저장 실패 %@", String(describing: error))
            }
            reloadItems()
        }
        reloadItems()
        watcher.start()

        hotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey) { [weak self] in
            self?.toggle()
        }

        // 최초 실행 시 접근성 권한 요청. 거부해도 "선택 = 클립보드 복사"로 동작한다.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        // M0 확인용: 클립보드 프라이버시 정책 상태 (macOS 15.4+)
        NSLog("cccv: pasteboard accessBehavior=%@, accessibility=%@",
              String(describing: NSPasteboard.general.accessBehavior),
              AXIsProcessTrusted() ? "granted" : "denied")
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "cccv")
        let menu = NSMenu()
        menu.addItem(withTitle: "열기 (⇧⌘V)", action: #selector(showFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func reloadItems() {
        do {
            model.items = try store.recent()
        } catch {
            NSLog("cccv: 불러오기 실패 %@", String(describing: error))
        }
    }

    @objc private func showFromMenu() {
        show()
    }

    private func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func show() {
        model.selection = 0
        panel.showAtBottomOfMouseScreen()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = Int(event.keyCode)
            let handled = MainActor.assumeIsolated { self?.handleKey(keyCode) ?? false }
            return handled ? nil : event
        }
    }

    private func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// 처리한 키면 true (이벤트 소비).
    private func handleKey(_ keyCode: Int) -> Bool {
        switch keyCode {
        case kVK_LeftArrow:
            model.selection = max(model.selection - 1, 0)
        case kVK_RightArrow:
            model.selection = min(model.selection + 1, max(model.items.count - 1, 0))
        case kVK_Return, kVK_ANSI_KeypadEnter:
            pick(model.selection)
        case kVK_Escape:
            hide()
        default:
            return false
        }
        return true
    }

    private func pick(_ index: Int) {
        guard model.items.indices.contains(index) else { return }
        let item = model.items[index]
        hide()
        Paster.paste(item)
    }
}
