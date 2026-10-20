import AppKit
import CCCVCore
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
    @State private var excluded = AppSettings.excludedBundleIDs
    @State private var selection: String?
    @State private var patterns = AppSettings.excludedPatterns
    @State private var patternSelection: ExcludedPattern?
    @State private var newPattern = ""
    @State private var newMemo = ""

    var body: some View {
        Form {
            Section {
                List(excluded, id: \.self, selection: $selection) { bundleID in
                    AppRow(bundleID: bundleID)
                }
                .frame(minHeight: 160)
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
                .frame(minHeight: 120)
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
        .frame(width: 460, height: 620)
        .onChange(of: excluded) { AppSettings.excludedBundleIDs = excluded }
        .onChange(of: patterns) { AppSettings.excludedPatterns = patterns }
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
