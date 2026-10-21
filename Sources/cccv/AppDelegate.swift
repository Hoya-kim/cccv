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
        model.position = AppSettings.barPosition
        model.scale = AppSettings.cardScale
        purgeExpired()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeExpired() }
        }
        setUpStatusItem()
        setUpMainMenu()

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
            },
            onAction: { [weak self] action, item in
                self?.perform(action, on: item)
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
        // 템플릿 이미지라 라이트·다크 메뉴바에 맞춰 색이 바뀐다. swift run 처럼 번들 밖에서 실행하면 SF Symbol 로.
        let icon = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        icon?.isTemplate = true
        icon?.accessibilityDescription = "cccv"
        item.button?.image = icon
        let menu = NSMenu()
        menu.addItem(withTitle: "열기 (⇧⌘V)", action: #selector(showFromMenu), keyEquivalent: "").target = self
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
            model.items = try store.search(model.query, pinnedOnly: model.pinnedOnly)
            model.selection = min(model.selection, max(model.items.count - 1, 0))
        } catch {
            NSLog("cccv: 불러오기 실패 %@", String(describing: error))
        }
    }

    @objc private func showFromMenu() {
        show()
    }

    /// 보존 기간이 지난 항목을 지운다. 실행 시·1시간마다·보존 기간 변경 시.
    private func purgeExpired() {
        do {
            if try store.purge(olderThan: AppSettings.retentionCutoff()) > 0 { reloadItems() }
        } catch {
            NSLog("cccv: 보존 기간 정리 실패 %@", String(describing: error))
        }
    }

    // ponytail: 일시정지는 앱을 다시 켜면 풀린다. 기간 지정(Paste 처럼)은 필요해지면.
    @objc private func togglePause(_ sender: NSMenuItem) {
        watcher.isPaused.toggle()
        sender.title = watcher.isPaused ? "수집 재개" : "수집 일시정지"
        // 일시정지 중에는 아이콘을 흐리게 표시한다.
        statusItem?.button?.appearsDisabled = watcher.isPaused
    }

    private lazy var settingsWindow: NSWindow = {
        let controller = NSHostingController(rootView: SettingsView(
            model: model,
            store: store,
            onRetentionChange: { [weak self] in self?.purgeExpired() }
        ))
        controller.sizingOptions = [.preferredContentSize] // 탭을 바꾸면 창 높이가 따라간다
        let window = NSWindow(contentViewController: controller)
        window.title = "cccv 설정"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
        }
        return window
    }()

    @objc private func openSettings() {
        // accessory 앱은 activate 해도 앞으로 오지 않을 때가 있다 → 설정 창이 열린 동안만 일반 앱으로.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
    }

    /// 메뉴바 전용 앱은 메인 메뉴가 없어 ⌘W·⌘C·⌘V 같은 키가 동작하지 않는다.
    private func setUpMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "설정…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "창 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "cccv 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(withTitle: "cccv", action: nil, keyEquivalent: "").submenu = appMenu

        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(withTitle: "편집", action: nil, keyEquivalent: "").submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func show() {
        model.query = ""
        model.pinnedOnly = false
        model.editingItem = nil // 편집 중에 바가 닫혔다면 버린다
        model.selection = 0
        model.showCount += 1
        panel.show(at: model.position, scale: model.scale)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = Int(event.keyCode)
            let shift = event.modifierFlags.contains(.shift)
            let command = event.modifierFlags.contains(.command)
            let handled = MainActor.assumeIsolated { self?.handleKey(keyCode, shift: shift, command: command) ?? false }
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
    private func handleKey(_ keyCode: Int, shift: Bool, command: Bool) -> Bool {
        // 한글 등 조합 중이면 Return·방향키는 입력기 몫이다.
        if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }

        // 이름 변경·편집 중에는 저장/취소 키만 가로채고 나머지(방향키·줄바꿈)는 입력칸 몫이다.
        if model.editingItem != nil {
            switch keyCode {
            case kVK_Escape:
                model.editingItem = nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                // 내용 편집에서 Return 은 줄바꿈, ⌘Return 이 저장.
                guard model.editMode == .rename || command else { return false }
                saveEditing()
            default:
                return false
            }
            return true
        }

        let selected = model.items.indices.contains(model.selection) ? model.items[model.selection] : nil

        if command {
            switch keyCode {
            // 전체/고정 전환. ⌘[ ⌘] 는 물리 키 기준이라 한글 입력 중에도 동작한다.
            case kVK_LeftArrow, kVK_ANSI_LeftBracket:
                model.pinnedOnly = false
            case kVK_RightArrow, kVK_ANSI_RightBracket:
                model.pinnedOnly = true
            case kVK_ANSI_P, kVK_ANSI_R, kVK_ANSI_E:
                guard let selected else { return true }
                let actions: [Int: CardAction] = [kVK_ANSI_P: .togglePin, kVK_ANSI_R: .rename, kVK_ANSI_E: .edit]
                perform(actions[keyCode]!, on: selected)
            case kVK_ANSI_Z where model.query.isEmpty && lastDeleted != nil:
                restoreLastDeleted()
            default:
                return false // ⌘C·⌘V·⌘A 등은 검색창 편집으로
            }
            return true
        }

        // 바 방향에 맞는 방향키만 쓴다 (가로 ←→, 세로 ↑↓).
        let horizontal = model.position.isHorizontal
        switch keyCode {
        // 검색어가 있으면 ⌫ 는 글자 지우기. 비어 있을 때만 선택 항목 삭제.
        case kVK_Delete where model.query.isEmpty:
            guard let selected else { return true }
            perform(.delete, on: selected)
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

    // ponytail: 되돌리기는 마지막 삭제 1건만. 여러 단계가 필요해지면 스택으로.
    private var lastDeleted: ClipStore.DeletedClip?

    private func perform(_ action: CardAction, on item: ClipItem) {
        do {
            switch action {
            case .togglePin:
                item.isPinned.toggle()
                try store.save()
            case .delete:
                lastDeleted = try store.delete(item)
            case .rename:
                model.editMode = .rename
                model.draft = item.title ?? ""
                model.editingItem = item
                return
            case .edit:
                guard item.isEditable else { NSSound.beep(); return }
                model.editMode = .edit
                model.draft = item.text
                model.editingItem = item
                return
            }
        } catch {
            NSLog("cccv: 항목 작업 실패 %@", String(describing: error))
        }
        reloadItems()
    }

    private func saveEditing() {
        guard let item = model.editingItem else { return }
        do {
            switch model.editMode {
            case .rename:
                let title = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                item.title = title.isEmpty ? nil : title
                try store.save()
            case .edit:
                try store.edit(item, newText: model.draft)
            }
        } catch {
            NSLog("cccv: 편집 저장 실패 %@", String(describing: error))
        }
        model.editingItem = nil
        reloadItems()
    }

    private func restoreLastDeleted() {
        guard let lastDeleted else { return }
        do {
            try store.restore(lastDeleted)
            self.lastDeleted = nil
        } catch {
            NSLog("cccv: 되돌리기 실패 %@", String(describing: error))
        }
        reloadItems()
    }

    private func pick(_ index: Int, plainText: Bool = false) {
        guard model.items.indices.contains(index) else { return }
        let item = model.items[index]
        hide()
        // 붙여넣어도 순서는 그대로 둔다 (사용자 결정). 감시기는 cccv 자신의 쓰기를 무시한다.
        Paster.paste(item, plainText: plainText)
    }
}
