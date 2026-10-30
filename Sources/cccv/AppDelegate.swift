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
    private let quickLook = QuickLook()
    private lazy var transformBubble: CardBubble = {
        let content = NSHostingView(rootView: TransformList(
            model: model,
            onPaste: { [weak self] text in
                self?.hide()
                Paster.paste(text: text)
            },
            onSelectionChange: { [weak self] in self?.generateSelectedTransform() }
        ))
        content.sizingOptions = [] // 크기는 말풍선이 정한다
        return CardBubble(size: NSSize(width: 560, height: 340), content: content)
    }()
    /// 지금 만들고 있는 AI 변환. 한 번에 하나만.
    private var aiTask: Task<Void, Never>?
    private var ocr: OCRQueue!
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
        model.alwaysPlainText = AppSettings.alwaysPlainText
        purgeExpired()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeExpired() }
        }
        // 민감정보 항목은 분 단위로 만료되므로 더 자주 본다.
        purgeSensitive()
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeSensitive() }
        }
        setUpStatusItem()
        setUpMainMenu()
        for bubble in [quickLook.bubble, transformBubble] {
            bubble.parent = panel
            bubble.position = { [weak self] in self?.model.position ?? .bottom }
            bubble.anchor = { [weak self] in
                // SwiftUI global 좌표(뒤집힌 hosting view 기준) → 창 좌표 → 화면 좌표
                guard let self, let frame = model.selectedCardFrame, let content = panel.contentView else { return nil }
                return panel.convertToScreen(content.convert(frame, to: nil))
            }
        }

        panel.contentView = NSHostingView(rootView: BarView(
            model: model,
            onPick: { [weak self] index in self?.pick(index) },
            onCardAppear: { [weak self] item in
                guard let self else { return }
                LinkPreview.fetchIfNeeded(item, store: store)
            },
            onQueryChange: { [weak self] in
                self?.model.selection = 0
                self?.browsingResults = false // 다시 입력 중 → Space 는 띄어쓰기
                self?.reloadItems()
            },
            onAction: { [weak self] action, item in
                self?.perform(action, on: item)
            },
            onSelectedCardMove: { [weak self] in
                guard let self else { return }
                if quickLook.isVisible { quickLook.bubble.reposition() }
                if transformBubble.isVisible { transformBubble.reposition() }
            }
        ))
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }

        watcher.onNewContent = { [weak self] content, source, expiresAt in
            guard let self else { return }
            do {
                try store.add(content, sourceBundleID: source, expiresAt: expiresAt)
            } catch {
                NSLog("cccv: 저장 실패 %@", String(describing: error))
            }
            reloadItems()
            if content.kind == .image { ocr.process() }
        }
        ocr = OCRQueue(store: store)
        ocr.onUpdate = { [weak self] in
            // 검색 중일 때만 결과가 바뀔 수 있다
            guard let self, !model.query.isEmpty else { return }
            reloadItems()
        }
        ocr.process() // 예전에 저장된 이미지도 한 번씩
        reloadItems()
        watcher.start()

        hotKey = HotKey { [weak self] in self?.toggle() }
        if hotKey?.register(AppSettings.hotKey) != true {
            NSLog("cccv: 저장된 단축키 %@ 등록 실패 → 기본값", AppSettings.hotKey.display)
            AppSettings.hotKey = .default
            hotKey?.register(.default)
        }
        updateOpenMenuTitle()

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
        icon?.accessibilityDescription = "CCCV"
        item.button?.image = icon
        let menu = NSMenu()
        openMenuItem = menu.addItem(withTitle: "열기", action: #selector(showFromMenu), keyEquivalent: "")
        openMenuItem?.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "수집 일시정지", action: #selector(togglePause(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "설정…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private var openMenuItem: NSMenuItem?

    private func updateOpenMenuTitle() {
        openMenuItem?.title = "열기 (\(AppSettings.hotKey.display))"
    }

    /// 설정에서 새 단축키를 고르면 호출된다. 등록에 실패하면 이전 조합으로 되돌리고 false.
    private func applyHotKey(_ combo: HotKeyCombo) -> Bool {
        guard hotKey?.register(combo) == true else {
            hotKey?.register(AppSettings.hotKey)
            return false
        }
        AppSettings.hotKey = combo
        updateOpenMenuTitle()
        return true
    }

    private func reloadItems() {
        let currentID = model.items.indices.contains(model.selection) ? model.items[model.selection].persistentModelID : nil
        do {
            model.items = try store.search(model.query, filter: model.filter)
            model.selection = min(model.selection, max(model.items.count - 1, 0))
        } catch {
            NSLog("cccv: 불러오기 실패 %@", String(describing: error))
        }
        // 변환 목록·미리보기는 선택 번호 자리의 카드 옆에 뜬다. 새 항목·정리로 그 자리 카드가 바뀌면
        // 다른 카드 옆에 이전 카드의 내용이 남으므로 닫는다.
        let newID = model.items.indices.contains(model.selection) ? model.items[model.selection].persistentModelID : nil
        if currentID != newID {
            closeTransforms()
            quickLook.close()
        }
    }

    @objc private func showFromMenu() {
        show()
    }

    /// 민감정보 패턴으로 만료 시각이 정해진 항목을 지운다. 실행 시·20초마다.
    private func purgeSensitive() {
        do {
            guard try store.purgeExpired() > 0 else { return }
            reloadItems()
            quickLook.close() // 미리보던 항목이 지워졌을 수 있다
        } catch {
            NSLog("cccv: 민감정보 정리 실패 %@", String(describing: error))
        }
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
            onRetentionChange: { [weak self] in self?.purgeExpired() },
            onHotKeyRecording: { [weak self] recording in
                // 기록 중에는 현재 단축키를 풀어 둬야 같은 조합을 눌러도 바가 열리지 않는다.
                if recording { self?.hotKey?.unregister() } else { self?.hotKey?.register(AppSettings.hotKey) }
            },
            onHotKeyChange: { [weak self] combo in self?.applyHotKey(combo) ?? false }
        ))
        controller.sizingOptions = [.preferredContentSize] // 탭을 바꾸면 창 높이가 따라간다
        let window = NSWindow(contentViewController: controller)
        window.title = "CCCV 설정"
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
        appMenu.addItem(withTitle: "CCCV 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(withTitle: "CCCV", action: nil, keyEquivalent: "").submenu = appMenu

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
        browsingResults = false
        model.filter = ClipFilter()
        model.sourceApps = (try? store.sourceBundleIDs()) ?? []
        model.editingItem = nil // 편집 중에 바가 닫혔다면 버린다
        closeTransforms() // 바가 떠 있는 채 메뉴바 "열기"로 다시 열 수도 있다 — 만들던 AI 변환도 멈춘다
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
        quickLook.close()
        closeTransforms()
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

        // ⌘T 변환 목록이 떠 있으면 ←→·↑↓·Return·1–9·Esc·⌘T 만 받고 나머지 키는 삼킨다 (검색창으로 새지 않게).
        let digits = Self.digitKeys
        if !model.transforms.isEmpty {
            let count = model.transforms.count
            var pasteIndex: Int?
            switch keyCode {
            case kVK_Escape:
                closeTransforms()
            case kVK_ANSI_T where command: // 연 키로 다시 닫는다
                closeTransforms()
            case kVK_LeftArrow, kVK_RightArrow:
                // ↑↓ 는 변환 목록 몫이라 세로 바에서도 카드 이동은 ←→ 로 한다.
                moveTransformTarget(by: keyCode == kVK_LeftArrow ? -1 : 1)
            case kVK_UpArrow:
                model.transformSelection = max(model.transformSelection - 1, 0)
            case kVK_DownArrow:
                model.transformSelection = min(model.transformSelection + 1, count - 1)
            case kVK_Return, kVK_ANSI_KeypadEnter:
                pasteIndex = model.transformSelection
            default:
                pasteIndex = digits.firstIndex(of: keyCode)
            }
            if let pasteIndex, pasteIndex < count {
                // AI 변환은 다 만든 뒤에만. 아직이면 그 줄을 골라 만들기를 시작한다 (실패했으면 다시).
                let entry = model.transforms[pasteIndex]
                guard let text = entry.result.text else {
                    if case .generating = entry.result { NSSound.beep() } // 만드는 중 — 기다린다
                    model.transformSelection = pasteIndex
                    generateSelectedTransform()
                    return true
                }
                hide()
                Paster.paste(text: text)
            }
            return true
        }

        let selected = model.items.indices.contains(model.selection) ? model.items[model.selection] : nil

        if command {
            switch keyCode {
            // 전체/고정 전환. ⌘[ ⌘] 는 물리 키 기준이라 한글 입력 중에도 동작한다.
            case kVK_LeftArrow, kVK_ANSI_LeftBracket:
                model.filter.pinnedOnly = false
            case kVK_RightArrow, kVK_ANSI_RightBracket:
                model.filter.pinnedOnly = true
            case kVK_ANSI_P, kVK_ANSI_R, kVK_ANSI_E, kVK_ANSI_T:
                guard let selected else { return true }
                let actions: [Int: CardAction] = [kVK_ANSI_P: .togglePin, kVK_ANSI_R: .rename, kVK_ANSI_E: .edit, kVK_ANSI_T: .transform]
                perform(actions[keyCode]!, on: selected)
            case kVK_ANSI_Z where model.query.isEmpty && lastDeleted != nil:
                restoreLastDeleted()
            case kVK_ANSI_Y:
                // ⌘Y (Finder 의 Quick Look 과 같은 키) — 검색 중에도 미리보기를 열고 닫는다.
                if quickLook.isVisible {
                    quickLook.close()
                } else if let selected {
                    quickLook.show(selected)
                }
            case _ where digits.contains(keyCode):
                // ⌘1–9 번호 붙여넣기 (⇧⌘1–9 는 서식 없이). 보이는 순서 기준.
                pick(digits.firstIndex(of: keyCode)!, plainText: shift)
            default:
                return false // ⌘C·⌘V·⌘A 등은 검색창 편집으로
            }
            return true
        }

        // 미리보기가 열려 있으면 Space·Esc 는 미리보기만 닫는다.
        if quickLook.isVisible, keyCode == kVK_Space || keyCode == kVK_Escape {
            quickLook.close()
            return true
        }

        // 바 방향에 맞는 방향키만 쓴다 (가로 ←→, 세로 ↑↓).
        let horizontal = model.position.isHorizontal
        switch keyCode {
        // 검색어가 있으면 ⌫ 는 글자 지우기. 비어 있을 때만 선택 항목 삭제.
        case kVK_Delete where model.query.isEmpty:
            guard let selected else { return true }
            perform(.delete, on: selected)
        // Space: 검색어가 없거나, 방향키로 카드를 고르는 중이면 미리보기. 검색어를 입력하는 중이면 띄어쓰기.
        case kVK_Space where model.query.isEmpty || browsingResults:
            guard let selected else { return true }
            quickLook.show(selected)
        case horizontal ? kVK_LeftArrow : kVK_UpArrow:
            browsingResults = true
            model.selection = max(model.selection - 1, 0)
            quickLook.follow(model.items.indices.contains(model.selection) ? model.items[model.selection] : nil)
        case horizontal ? kVK_RightArrow : kVK_DownArrow:
            browsingResults = true
            model.selection = min(model.selection + 1, max(model.items.count - 1, 0))
            quickLook.follow(model.items.indices.contains(model.selection) ? model.items[model.selection] : nil)
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

    /// 검색어를 입력한 뒤 방향키로 카드를 고르기 시작했는지. 그동안 Space 는 미리보기, 글자를 치면 다시 false.
    private var browsingResults = false

    private static let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    // ponytail: 되돌리기는 마지막 삭제 1건만. 여러 단계가 필요해지면 스택으로.
    private var lastDeleted: ClipStore.DeletedClip?

    private func perform(_ action: CardAction, on item: ClipItem) {
        do {
            switch action {
            case .paste(let plain):
                paste(item, plain: plain)
                return
            case .togglePin:
                item.isPinned.toggle()
                if item.isPinned { item.expiresAt = nil } // 고정하면 민감정보 자동 삭제가 풀린다
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
            case .transform:
                let transforms = item.transformEntries
                guard !transforms.isEmpty else { NSSound.beep(); return }
                // 우클릭 메뉴로 다른 카드에서 열 수도 있다 → 그 카드를 선택해 말풍선이 그 옆에 뜨게.
                if let index = model.items.firstIndex(of: item) { model.selection = index }
                quickLook.close() // 같은 카드에 붙으므로 둘 중 하나만
                cancelAITransform()
                model.transformSelection = 0
                model.transforms = transforms
                model.transformSource = item.text
                transformBubble.show()
                generateSelectedTransform()
                return
            }
        } catch {
            NSLog("cccv: 항목 작업 실패 %@", String(describing: error))
        }
        reloadItems()
    }

    /// 변환 목록을 연 채로 옆 카드로 옮긴다. 변환할 수 없는 카드(이미지 등)는 건너뛰고, 고르던 변환은 이어서 고른다.
    private func moveTransformTarget(by step: Int) {
        let label = model.transforms.indices.contains(model.transformSelection) ? model.transforms[model.transformSelection].label : nil
        var index = model.selection + step
        while model.items.indices.contains(index) {
            let item = model.items[index]
            let transforms = item.transformEntries
            if !transforms.isEmpty {
                cancelAITransform()
                model.selection = index
                model.transforms = transforms
                model.transformSource = item.text
                model.transformSelection = transforms.firstIndex { $0.label == label } ?? 0
                generateSelectedTransform()
                return
            }
            index += step
        }
        NSSound.beep() // 그쪽에 변환할 수 있는 카드가 없다
    }

    private func closeTransforms() {
        cancelAITransform()
        model.transforms = []
        transformBubble.close()
    }

    /// 고른 줄이 아직 만들지 않았거나 실패한 AI 변환이면 만든다. 다른 AI 변환을 만들던 중이면 그건 멈춘다 (다시 고르면 처음부터).
    /// 기존 변환 줄로 옮기는 것만으로는 멈추지 않는다 — 결과를 기다리며 다른 줄을 볼 수 있게.
    private func generateSelectedTransform() {
        let index = model.transformSelection
        guard model.transforms.indices.contains(index), let ai = model.transforms[index].ai else { return }
        switch model.transforms[index].result {
        case .pending, .failed: break
        case .generating, .ready: return
        }
        cancelAITransform()
        let text = model.transformSource
        model.transforms[index].result = .generating("")
        // 목록을 바꾸는 곳은 먼저 취소하지만, 놓친 경로가 있어도 다른 카드의 목록·빈 목록에 쓰지 않게 확인하고 쓴다.
        let write = { [weak self] (result: TransformResult) in
            guard !Task.isCancelled, let self, model.transformSource == text,
                  model.transforms.indices.contains(index), model.transforms[index].ai == ai else { return }
            model.transforms[index].result = result
        }
        aiTask = Task { [weak self] in
            let result = await AITransformer.run(ai, on: text) { write(.generating($0)) }
            write(result)
            if !Task.isCancelled { self?.aiTask = nil }
        }
    }

    private func cancelAITransform() {
        aiTask?.cancel()
        aiTask = nil
        for index in model.transforms.indices {
            if case .generating = model.transforms[index].result { model.transforms[index].result = .pending }
        }
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

    /// 키·클릭 붙여넣기. 기본값은 "항상 서식 없이" 설정 또는 대상 앱 규칙, ⇧(invert) 는 그걸 뒤집는다.
    private func pick(_ index: Int, plainText invert: Bool = false) {
        guard model.items.indices.contains(index) else { return }
        // 바는 앱을 활성화하지 않으므로 지금 앞에 있는 앱이 붙여넣을 대상이다.
        let target = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let plainByDefault = AppSettings.alwaysPlainText || target.map(AppSettings.plainTextBundleIDs.contains) == true
        paste(model.items[index], plain: invert != plainByDefault)
    }

    private func paste(_ item: ClipItem, plain: Bool) {
        hide()
        // 붙여넣어도 순서는 그대로 둔다 (사용자 결정). 감시기는 cccv 자신의 쓰기를 무시한다.
        Paster.paste(item, plainText: plain)
    }
}
