import AppKit
import CCCVCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// UserDefaults 에 두는 사용자 설정.
enum AppSettings {
    private static let excludedKey = "excludedBundleIDs"

    /// 이 앱이 앞에 있을 때 복사한 내용은 기록하지 않는다.
    static var excludedBundleIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: excludedKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: excludedKey) }
    }

    static var barPosition: BarPosition {
        get { UserDefaults.standard.string(forKey: "barPosition").flatMap(BarPosition.init) ?? .bottom }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "barPosition") }
    }

    /// 카드·글자 크기 배율. 화면을 넘지 않도록 정해진 단계만 쓴다.
    static let cardScaleChoices: [(scale: Double, label: String)] = [(0.85, "작게"), (1.0, "보통"), (1.2, "크게"), (1.4, "아주 크게")]
    static var cardScale: Double {
        get {
            let scale = UserDefaults.standard.double(forKey: "cardScale")
            return cardScaleChoices.contains { $0.scale == scale } ? scale : 1.0
        }
        set { UserDefaults.standard.set(newValue, forKey: "cardScale") }
    }

    /// 보존 기간(일). 무기한 옵션은 두지 않는다 (사용자 결정 — 용량 낭비).
    static let retentionChoices = [1, 7, 30, 90, 365]
    static var retentionDays: Int {
        get {
            let days = UserDefaults.standard.integer(forKey: "retentionDays")
            return retentionChoices.contains(days) ? days : 30
        }
        set { UserDefaults.standard.set(newValue, forKey: "retentionDays") }
    }

    static func retentionCutoff(days: Int = retentionDays, now: Date = Date()) -> Date {
        now.addingTimeInterval(-Double(days) * 86400)
    }

    /// 링크 카드가 보일 때 OG 미리보기를 가져올지.
    static var linkPreviewEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "linkPreviewEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "linkPreviewEnabled") }
    }

    private static let patternsKey = "excludedPatterns"
    private static let otpPattern = ExcludedPattern(pattern: #"^\d{6}$"#, memo: "OTP (숫자 6자리)")

    /// 내용 전체가 일치하면 기록하지 않는 정규식. 기본값은 숫자 6자리(OTP).
    static var excludedPatterns: [ExcludedPattern] {
        get {
            let defaults = UserDefaults.standard
            if let rules = defaults.array(forKey: patternsKey) as? [[String: String]] {
                return rules.compactMap { rule in
                    rule["pattern"].map { ExcludedPattern(pattern: $0, memo: rule["memo"] ?? "") }
                }
            }
            // 메모가 생기기 전 형식([String])에서 옮겨 온다.
            if let patterns = defaults.stringArray(forKey: patternsKey) {
                return patterns.map { $0 == otpPattern.pattern ? otpPattern : ExcludedPattern(pattern: $0, memo: "") }
            }
            return [otpPattern]
        }
        set {
            UserDefaults.standard.set(newValue.map { ["pattern": $0.pattern, "memo": $0.memo] }, forKey: patternsKey)
        }
    }
}

struct ExcludedPattern: Hashable {
    var pattern: String
    var memo: String
}

struct SettingsView: View {
    @Bindable var model: BarModel
    let store: ClipStore
    /// 보존 기간이 바뀐 뒤 정리를 돌리기 위해.
    let onRetentionChange: () -> Void

    @State private var retentionDays = AppSettings.retentionDays
    @State private var pendingRetention: (days: Int, deleteCount: Int)?
    @State private var linkPreviewEnabled = AppSettings.linkPreviewEnabled
    @State private var launchAtLogin = SMAppService.mainApp.status
    @State private var launchError: String?

    @State private var excluded = AppSettings.excludedBundleIDs
    @State private var selection: String?
    @State private var patterns = AppSettings.excludedPatterns
    @State private var patternSelection: ExcludedPattern?
    @State private var newPattern = ""
    @State private var newMemo = ""

    var body: some View {
        TabView {
            generalTab.tabItem { Label("일반", systemImage: "gearshape") }
            privacyTab.tabItem { Label("개인정보 보호", systemImage: "hand.raised") }
        }
        .frame(width: 480)
        .onChange(of: model.position) { AppSettings.barPosition = model.position }
        .onChange(of: model.scale) { AppSettings.cardScale = model.scale }
        .onChange(of: linkPreviewEnabled) { AppSettings.linkPreviewEnabled = linkPreviewEnabled }
        .onChange(of: excluded) { AppSettings.excludedBundleIDs = excluded }
        .onChange(of: patterns) { AppSettings.excludedPatterns = patterns }
        .onAppear { launchAtLogin = SMAppService.mainApp.status }
        .confirmationDialog(
            "보존 기간을 줄이면 \(pendingRetention?.deleteCount ?? 0)개 항목이 바로 삭제됩니다.",
            isPresented: Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } })
        ) {
            Button("삭제하고 변경", role: .destructive) {
                if let days = pendingRetention?.days { applyRetention(days) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제한 항목은 되돌릴 수 없습니다.")
        }
    }

    // 탭마다 높이를 고정해 두면 창이 탭에 맞춰 커지고 줄어든다 (NSHostingController.sizingOptions).
    private var generalTab: some View {
        Form {
            Section {
                Picker("바 위치", selection: $model.position) {
                    ForEach(BarPosition.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("카드 크기", selection: $model.scale) {
                    ForEach(AppSettings.cardScaleChoices, id: \.scale) { Text($0.label).tag($0.scale) }
                }
                .pickerStyle(.segmented)

                // setter 에 메서드 참조를 그대로 넘기면 Swift 6.2 컴파일러가 IRGen 에서 크래시한다 → 클로저로 감싼다.
                Picker("보존 기간", selection: Binding(get: { retentionDays }, set: { requestRetention($0) })) {
                    ForEach(AppSettings.retentionChoices, id: \.self) { days in
                        Text(days == 365 ? "1년" : "\(days)일").tag(days)
                    }
                }

                Toggle("로그인 시 자동 실행", isOn: Binding(get: { launchAtLogin == .enabled }, set: { setLaunchAtLogin($0) }))
                if launchAtLogin == .requiresApproval {
                    HStack {
                        Text("시스템 설정 → 로그인 항목에서 허용해야 합니다.").font(.caption).foregroundStyle(.secondary)
                        Button("열기") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 260)
    }

    private var privacyTab: some View {
        Form {
            Section {
                Toggle("링크 미리보기 불러오기", isOn: $linkPreviewEnabled)
            } footer: {
                Text("링크 카드가 처음 보일 때 그 주소로 요청을 보내 제목·이미지를 가져옵니다. 1회용 링크(로그인·비밀번호 재설정)는 요청만으로 만료될 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                List(excluded, id: \.self, selection: $selection) { bundleID in
                    AppRow(bundleID: bundleID)
                }
                .frame(minHeight: 100)
                HStack {
                    Button("앱 추가…", action: addApp)
                    Button("삭제") {
                        excluded.removeAll { $0 == selection }
                        selection = nil
                    }
                    .disabled(selection == nil)
                }
            } header: {
                Text("제외 앱")
            } footer: {
                Text("이 앱이 앞에 있을 때 복사한 내용은 기록하지 않습니다. 메뉴바 앱은 앞에 나오지 않아 여기서 막히지 않으니 아래 패턴을 쓰세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                List(patterns, id: \.self, selection: $patternSelection) { rule in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.memo.isEmpty ? "메모 없음" : rule.memo)
                            .foregroundStyle(rule.memo.isEmpty ? .secondary : .primary)
                        Text(rule.pattern).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 100)
                // Form 안의 TextField 제목은 왼쪽 라벨로 빠져 입력칸이 안 보인다 → prompt 로 넣고 라벨은 숨긴다.
                HStack {
                    TextField("정규식", text: $newPattern, prompt: Text("정규식 (예: ^\\d{6}$)"))
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(addPattern)
                    TextField("메모", text: $newMemo, prompt: Text("메모 (예: OTP)"))
                        .onSubmit(addPattern)
                }
                .labelsHidden()
                HStack {
                    Button("패턴 추가", action: addPattern)
                        .disabled(!PasteboardRules.isValidPattern(newPattern))
                    Button("삭제") {
                        patterns.removeAll { $0 == patternSelection }
                        patternSelection = nil
                    }
                    .disabled(patternSelection == nil)
                }
                if !newPattern.isEmpty, !PasteboardRules.isValidPattern(newPattern) {
                    Text("올바른 정규식이 아닙니다.").font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("제외 패턴")
            } footer: {
                Text("복사한 내용 전체(앞뒤 공백 제외)가 패턴과 일치하면 기록하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 720)
    }

    /// 지워질 항목이 있으면 건수를 보여 주고 확인받는다.
    private func requestRetention(_ days: Int) {
        let count = (try? store.count(olderThan: AppSettings.retentionCutoff(days: days))) ?? 0
        if count > 0 {
            pendingRetention = (days, count)
        } else {
            applyRetention(days)
        }
    }

    private func applyRetention(_ days: Int) {
        retentionDays = days
        AppSettings.retentionDays = days
        pendingRetention = nil
        onRetentionChange()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = "자동 실행 설정 실패: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status
    }

    private func addPattern() {
        guard PasteboardRules.isValidPattern(newPattern), !patterns.contains(where: { $0.pattern == newPattern }) else { return }
        patterns.append(ExcludedPattern(pattern: newPattern, memo: newMemo.trimmingCharacters(in: .whitespaces)))
        newPattern = ""
        newMemo = ""
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: "/Applications")
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        excluded.append(contentsOf: ids.filter { !excluded.contains($0) })
    }
}

private struct AppRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
            Spacer()
            Text(bundleID).font(.caption).foregroundStyle(.secondary)
        }
    }
}
