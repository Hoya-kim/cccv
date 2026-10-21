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
    /// true 면 고정 항목만 보여 준다 (⌘← / ⌘→, ⌘[ / ⌘] 로 전환).
    var pinnedOnly = false
    /// 바를 열 때마다 올려서 검색창에 포커스를 준다.
    var showCount = 0
    /// 카드·글자 크기 배율 (설정 "카드 크기").
    var scale = 1.0
    /// 이름 변경·편집 중인 항목. nil 이 아니면 검색 대신 입력칸이 보인다.
    var editingItem: ClipItem?
    var editMode = EditMode.rename
    var draft = ""
}

enum EditMode {
    case rename, edit
}

enum CardAction {
    case togglePin, delete, rename, edit
}

/// 카드 기본 크기. 실제 크기는 BarModel.scale 을 곱한다.
enum CardMetrics {
    static let width: CGFloat = 200
    static let height: CGFloat = 210
}

struct BarView: View {
    @Bindable var model: BarModel
    let onPick: (Int) -> Void
    /// 카드가 처음 보일 때 (링크 미리보기 가져오기 등).
    let onCardAppear: (ClipItem) -> Void
    /// 검색어나 전체/고정 탭이 바뀌었을 때.
    let onQueryChange: () -> Void
    let onAction: (CardAction, ClipItem) -> Void

    private enum Field { case search, editor }
    @FocusState private var focus: Field?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.editingItem == nil { searchRow } else { editorHeader }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            cardList
                .overlay {
                    if model.editingItem != nil, model.editMode == .edit { contentEditor }
                }
        }
        .onChange(of: model.query) { onQueryChange() }
        .onChange(of: model.pinnedOnly) { onQueryChange() }
        .onChange(of: model.showCount) { focus = .search }
        .onChange(of: model.editingItem == nil) { _, done in focus = done ? .search : .editor }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(8)
    }

    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("검색", text: $model.query)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
            Picker("보기", selection: $model.pinnedOnly) {
                Text("전체").tag(false)
                Text("고정").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    /// 이름 변경은 이 줄의 입력칸에서, 편집은 아래 큰 편집기에서 한다.
    private var editorHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: model.editMode == .rename ? "character.cursor.ibeam" : "pencil")
                .foregroundStyle(.secondary)
            if model.editMode == .rename {
                TextField("이름", text: $model.draft, prompt: Text("이름 (비우면 이름 없음)"))
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .editor)
                Text("Return 저장 · Esc 취소").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("내용 편집").bold()
                Spacer()
                Text("⌘Return 저장 · Esc 취소").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var contentEditor: some View {
        TextEditor(text: $model.draft)
            .font(.system(size: 13, design: .monospaced))
            .focused($focus, equals: .editor)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .padding(16)
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
                Text(!model.query.isEmpty ? "검색 결과가 없습니다" : model.pinnedOnly ? "고정한 항목이 없습니다" : "복사한 항목이 없습니다")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cards: some View {
        ForEach(Array(model.items.enumerated()), id: \.element.persistentModelID) { index, item in
            ClipCard(item: item, isSelected: index == model.selection, scale: model.scale)
                .id(item.persistentModelID)
                .onTapGesture { onPick(index) }
                .onAppear { onCardAppear(item) }
                .contextMenu {
                    Button(item.isPinned ? "고정 해제 (⌘P)" : "고정 (⌘P)") { onAction(.togglePin, item) }
                    Button("이름 변경 (⌘R)") { onAction(.rename, item) }
                    if item.isEditable {
                        Button("내용 편집 (⌘E)") { onAction(.edit, item) }
                    }
                    Divider()
                    Button("삭제 (⌫)", role: .destructive) { onAction(.delete, item) }
                }
        }
    }
}

extension ClipItem {
    /// 이미지·파일은 텍스트로 고칠 수 없다.
    var isEditable: Bool { kind != .image && kind != .file }
}

private struct ClipCard: View {
    let item: ClipItem
    let isSelected: Bool
    let scale: Double

    private func size(_ base: CGFloat) -> CGFloat { base * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: size(8)) {
            HStack(spacing: size(4)) {
                if item.isPinned {
                    Image(systemName: "pin.fill").foregroundStyle(.orange)
                }
                if let app = sourceApp {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable().frame(width: size(14), height: size(14))
                }
                Text(sourceApp?.name ?? "알 수 없는 앱").lineLimit(1)
                Spacer()
                Text(kindLabel)
            }
            .font(.system(size: size(11), weight: .bold))
            .foregroundStyle(.secondary)
            if let title = item.title {
                Text(title).font(.system(size: size(13), weight: .bold)).lineLimit(2)
            }
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            TimelineView(.everyMinute) { context in
                Text(RelativeTime.label(since: item.copiedAt, now: context.date))
                    .font(.system(size: size(10)))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(size(12))
        .frame(width: size(CardMetrics.width), height: size(CardMetrics.height))
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
            Text(item.text).font(.system(size: size(12))).lineLimit(9)
        case .link:
            // OG 미리보기가 없으면(가져오는 중·실패) 호스트 + URL 로 표시한다.
            VStack(alignment: .leading, spacing: size(6)) {
                if let data = item.linkImage, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: size(90)).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if let title = item.linkTitle {
                    Text(title).font(.system(size: size(12), weight: .semibold)).lineLimit(3)
                    Text(URL(string: item.text)?.host() ?? "").font(.system(size: size(11))).foregroundStyle(.secondary)
                } else {
                    Text(URL(string: item.text)?.host() ?? item.text).font(.system(size: size(13), weight: .semibold))
                    Text(item.text).font(.system(size: size(11))).foregroundStyle(.secondary).lineLimit(6)
                }
            }
        case .color:
            VStack(alignment: .leading, spacing: size(8)) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(swatch)
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator) }
                Text(item.text).font(.system(size: size(12), design: .monospaced))
            }
        case .image:
            // ponytail: 렌더링마다 원본 디코딩. 느려지면 저장 시 썸네일 생성으로.
            if let data = item.payload, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .file:
            let paths = item.text.split(separator: "\n").map(String.init)
            VStack(alignment: .leading, spacing: size(6)) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: paths.first ?? ""))
                    .resizable().frame(width: size(48), height: size(48))
                Text(paths.map { ($0 as NSString).lastPathComponent }.joined(separator: "\n"))
                    .font(.system(size: size(12))).lineLimit(5)
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

    private var sourceApp: (name: String, path: String)? {
        guard let id = item.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return (FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), url.path)
    }
}
