import AppKit
import CCCVCore
import SwiftUI

@MainActor
@Observable
final class BarModel {
    var items: [ClipItem] = []
    var selection = 0
}

struct BarView: View {
    let model: BarModel
    let onPick: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ClipCard(item: item, isSelected: index == model.selection)
                            .id(item.id)
                            .onTapGesture { onPick(index) }
                    }
                }
                .padding(16)
            }
            .onChange(of: model.selection) { _, selection in
                guard model.items.indices.contains(selection) else { return }
                proxy.scrollTo(model.items[selection].id, anchor: .center)
            }
        }
        .overlay {
            if model.items.isEmpty {
                Text("복사한 항목이 없습니다").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(8)
    }
}

private struct ClipCard: View {
    let item: ClipItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appName ?? "알 수 없는 앱")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(item.text)
                .font(.system(size: 12))
                .lineLimit(9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text(item.copiedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 200, height: 210)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        }
    }

    private var appName: String? {
        guard let id = item.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
