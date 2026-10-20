import AppKit
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
}

struct SettingsView: View {
    @State private var excluded = AppSettings.excludedBundleIDs
    @State private var selection: String?

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
                Text("이 앱이 앞에 있을 때 복사한 내용은 기록하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 340)
        .onChange(of: excluded) { AppSettings.excludedBundleIDs = excluded }
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
