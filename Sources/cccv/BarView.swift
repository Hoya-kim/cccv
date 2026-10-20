import AppKit
import CCCVCore
import SwiftUI

@MainActor
@Observable
final class BarModel {
    var items: [ClipItem] = []
    var selection = 0
    var position = BarPosition.bottom
    var query = ""
    /// 바를 열 때마다 올려서 검색창에 포커스를 준다.
    var showCount = 0
}

struct BarView: View {
    @Bindable var model: BarModel
    let onPick: (Int) -> Void
    /// 카드가 처음 보일 때 (링크 미리보기 가져오기 등).
    let onCardAppear: (ClipItem) -> Void
    let onQueryChange: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("검색", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            cardList
        }
        .onChange(of: model.query) { onQueryChange() }
        .onChange(of: model.showCount) { searchFocused = true }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(8)
    }

    private var cardList: some View {
        ScrollViewReader { proxy in
            ScrollView(model.position.isHorizontal ? .horizontal : .vertical, showsIndicators: false) {
                if model.position.isHorizontal {
                    LazyHStack(spacing: 12) { cards }.padding(16)
                } else {
                    LazyVStack(spacing: 12) { cards }.padding(16)
                }
            }
            .onChange(of: model.selection) { _, selection in
                guard model.items.indices.contains(selection) else { return }
                proxy.scrollTo(model.items[selection].persistentModelID, anchor: .center)
            }
        }
        .overlay {
            if model.items.isEmpty {
                Text(model.query.isEmpty ? "복사한 항목이 없습니다" : "검색 결과가 없습니다").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cards: some View {
        ForEach(Array(model.items.enumerated()), id: \.element.persistentModelID) { index, item in
            ClipCard(item: item, isSelected: index == model.selection)
                .id(item.persistentModelID)
                .onTapGesture { onPick(index) }
                .onAppear { onCardAppear(item) }
        }
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
            TimelineView(.everyMinute) { context in
                Text(RelativeTime.label(since: item.copiedAt, now: context.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
            // OG 미리보기가 없으면(가져오는 중·실패) 호스트 + URL 로 표시한다.
            VStack(alignment: .leading, spacing: 6) {
                if let data = item.linkImage, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 90).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if let title = item.linkTitle {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(3)
                    Text(URL(string: item.text)?.host() ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text(URL(string: item.text)?.host() ?? item.text).font(.system(size: 13, weight: .semibold))
                    Text(item.text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(6)
                }
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
