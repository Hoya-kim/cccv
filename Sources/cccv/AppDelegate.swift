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
        model.position = UserDefaults.standard.string(forKey: Self.positionKey).flatMap(BarPosition.init) ?? .bottom
        setUpStatusItem()

        panel.contentView = NSHostingView(rootView: BarView(
            model: model,
            onPick: { [weak self] index in self?.pick(index) },
            onCardAppear: { [weak self] item in
                guard let self else { return }
                LinkPreview.fetchIfNeeded(item, store: store)
            },
            onQueryChange: { [weak self] in
                self?.model.selection = 0
                self?.reloadItems()
            }
        ))
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

        // ponytail: 설정 창(M1 ⑥)이 생기기 전까지 위치 선택은 메뉴에서.
        let positionMenu = NSMenu()
        for position in BarPosition.allCases {
            let positionItem = positionMenu.addItem(withTitle: position.label, action: #selector(selectPosition(_:)), keyEquivalent: "")
            positionItem.target = self
            positionItem.representedObject = position.rawValue
            positionItem.state = position == model.position ? .on : .off
        }
        menu.addItem(withTitle: "바 위치", action: nil, keyEquivalent: "").submenu = positionMenu

        menu.addItem(.separator())
        menu.addItem(withTitle: "수집 일시정지", action: #selector(togglePause(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "설정…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func reloadItems() {
        do {
            model.items = try store.search(model.query)
        } catch {
            NSLog("cccv: 불러오기 실패 %@", String(describing: error))
        }
    }

    @objc private func showFromMenu() {
        show()
    }

    @objc private func selectPosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let position = BarPosition(rawValue: raw) else { return }
        model.position = position
        UserDefaults.standard.set(raw, forKey: Self.positionKey)
        // 열린 상태에서 바꾸면 내용만 가로/세로로 바뀌고 창 크기는 그대로 남는다 → 다시 배치.
        if panel.isVisible { panel.show(at: position) }
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }

    private static let positionKey = "barPosition"

    // ponytail: 일시정지는 앱을 다시 켜면 풀린다. 기간 지정(Paste 처럼)은 필요해지면.
    @objc private func togglePause(_ sender: NSMenuItem) {
        watcher.isPaused.toggle()
        sender.title = watcher.isPaused ? "수집 재개" : "수집 일시정지"
        statusItem?.button?.image = NSImage(
            systemSymbolName: watcher.isPaused ? "pause.circle" : "doc.on.clipboard",
            accessibilityDescription: watcher.isPaused ? "cccv (일시정지)" : "cccv"
        )
    }

    private lazy var settingsWindow: NSWindow = {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "cccv 설정"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        return window
    }()

    @objc private func openSettings() {
        // 메뉴바 전용 앱이라 먼저 활성화해야 창이 앞으로 온다.
        NSApp.activate()
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func show() {
        model.query = ""
        model.selection = 0
        model.showCount += 1
        panel.show(at: model.position)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = Int(event.keyCode)
            let shift = event.modifierFlags.contains(.shift)
            let handled = MainActor.assumeIsolated { self?.handleKey(keyCode, shift: shift) ?? false }
            return handled ? nil : event
        }
    }

    private func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// 처리한 키면 true (이벤트 소비). 그 외 키는 검색창으로 간다.
    private func handleKey(_ keyCode: Int, shift: Bool) -> Bool {
        // 한글 등 조합 중이면 Return·방향키는 입력기 몫이다.
        if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
        // 바 방향에 맞는 방향키만 쓴다 (가로 ←→, 세로 ↑↓).
        let horizontal = model.position.isHorizontal
        switch keyCode {
        case horizontal ? kVK_LeftArrow : kVK_UpArrow:
            model.selection = max(model.selection - 1, 0)
        case horizontal ? kVK_RightArrow : kVK_DownArrow:
            model.selection = min(model.selection + 1, max(model.items.count - 1, 0))
        case kVK_Return, kVK_ANSI_KeypadEnter:
            pick(model.selection, plainText: shift)
        case kVK_Escape:
            // 검색 중이면 검색어부터 지운다.
            if model.query.isEmpty { hide() } else { model.query = "" }
        default:
            return false
        }
        return true
    }

    private func pick(_ index: Int, plainText: Bool = false) {
        guard model.items.indices.contains(index) else { return }
        let item = model.items[index]
        hide()
        Paster.paste(item, plainText: plainText)
    }
}
