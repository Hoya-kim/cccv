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
                    ForEach(Array(model.items.enumerated()), id: \.element.persistentModelID) { index, item in
                        ClipCard(item: item, isSelected: index == model.selection)
                            .id(item.persistentModelID)
                            .onTapGesture { onPick(index) }
                    }
                }
                .padding(16)
            }
            .onChange(of: model.selection) { _, selection in
                guard model.items.indices.contains(selection) else { return }
                proxy.scrollTo(model.items[selection].persistentModelID, anchor: .center)
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
            HStack {
                Text(appName ?? "알 수 없는 앱")
                Spacer()
                Text(kindLabel)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            preview
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

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text, .richText:
            Text(item.text).font(.system(size: 12)).lineLimit(9)
        case .link:
            VStack(alignment: .leading, spacing: 4) {
                Text(URL(string: item.text)?.host() ?? item.text).font(.system(size: 13, weight: .semibold))
                Text(item.text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(6)
            }
        case .color:
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(swatch)
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
                Text(item.text).font(.system(size: 12, design: .monospaced))
            }
        case .image:
            // ponytail: 렌더링마다 원본 디코딩. 느려지면 저장 시 썸네일 생성으로.
            if let data = item.payload, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .file:
            let paths = item.text.split(separator: "\n").map(String.init)
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: paths.first ?? "")).resizable().frame(width: 48, height: 48)
                Text(paths.map { ($0 as NSString).lastPathComponent }.joined(separator: "\n"))
                    .font(.system(size: 12)).lineLimit(5)
            }
        }
    }

    private var kindLabel: String {
        switch item.kind {
        case .text: "텍스트"
        case .richText: "서식 텍스트"
        case .link: "링크"
        case .color: "색상"
        case .image: "이미지"
        case .file: item.text.contains("\n") ? "파일 \(item.text.split(separator: "\n").count)개" : "파일"
        }
    }

    private var swatch: Color {
        guard let c = ClipContent.hexColor(item.text) else { return .clear }
        return Color(red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    private var appName: String? {
        guard let id = item.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
