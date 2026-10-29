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
    /// 전체/고정(⌘[ / ⌘], ⌘← / ⌘→), 종류·출처 앱 필터. 바를 열 때마다 초기화.
    var filter = ClipFilter()
    /// 필터 드롭다운의 출처 앱 후보.
    var sourceApps: [String] = []
    /// 바를 열 때마다 올려서 검색창에 포커스를 준다.
    var showCount = 0
    /// 카드·글자 크기 배율 (설정 "카드 크기").
    var scale = 1.0
    /// 설정 "항상 서식 없이 붙여넣기". 우클릭 메뉴의 단축키 안내도 이에 맞춘다.
    var alwaysPlainText = false
    /// 이름 변경·편집 중인 항목. nil 이 아니면 검색 대신 입력칸이 보인다.
    var editingItem: ClipItem?
    var editMode = EditMode.rename
    var draft = ""
    /// ⌘T 로 연 변환 목록. 비어 있지 않으면 선택한 카드 옆 말풍선에 번호 목록이 보인다.
    var transforms: [(label: String, result: String)] = []
    /// 변환 목록에서 고른 줄 (↑↓·마우스). 오른쪽에 결과 전체를 보여 준다.
    var transformSelection = 0
    /// 선택한 카드의 바 안 좌표 (SwiftUI global). Space 미리보기를 이 카드 옆에 띄운다.
    var selectedCardFrame: CGRect?
}

private struct SelectedCardFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}

enum EditMode {
    case rename, edit
}

enum CardAction {
    /// 우클릭 메뉴의 붙여넣기는 설정과 상관없이 고른 그대로 (plain: 서식 없이).
    case paste(plain: Bool)
    case togglePin, delete, rename, edit, transform
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
    /// 선택한 카드가 움직였을 때 (스크롤·선택 이동) — 미리보기 위치를 따라가게.
    let onSelectedCardMove: () -> Void

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
        .onChange(of: model.filter) { onQueryChange() }
        .onChange(of: model.showCount) { focus = .search }
        .onChange(of: model.editingItem == nil) { _, done in focus = done ? .search : .editor }
        .onPreferenceChange(SelectedCardFrameKey.self) { frame in
            MainActor.assumeIsolated { model.selectedCardFrame = frame }
        }
        .onChange(of: model.selectedCardFrame) { onSelectedCardMove() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(8)
    }

    /// 한 줄에 안 들어가면(좁은 세로 바) 검색·필터 / 전체·고정 두 줄로 나눈다.
    private var searchRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                searchField
                filterMenu
                pinnedToggle
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    searchField
                    filterMenu
                }
                pinnedToggle.frame(maxWidth: .infinity) // 둘째 줄은 가운데 정렬
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("검색", text: $model.query)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .frame(minWidth: 120) // 이보다 좁아지면 두 줄로
        }
    }

    private var pinnedToggle: some View {
        HStack(spacing: 6) {
            Picker("보기", selection: $model.filter.pinnedOnly) {
                Text("전체").tag(false)
                Text("고정").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text("⌘[ ⌘]").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("종류", selection: $model.filter.kind) {
                Text("모든 종류").tag(ClipKind?.none)
                ForEach(ClipKind.allCases, id: \.self) { Text($0.label).tag(ClipKind?.some($0)) }
            }
            .pickerStyle(.inline)
            Picker("출처 앱", selection: $model.filter.sourceBundleID) {
                Text("모든 앱").tag(String?.none)
                ForEach(model.sourceApps, id: \.self) { id in
                    Text(AppInfo.name(of: id) ?? id).tag(String?.some(id))
                }
            }
            .pickerStyle(.inline)
            if model.filter.narrowsContent {
                Divider()
                Button("필터 해제") {
                    model.filter.kind = nil
                    model.filter.sourceBundleID = nil
                }
            }
        } label: {
            Image(systemName: model.filter.narrowsContent
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("종류·출처 앱 필터")
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
                Text(!model.query.isEmpty || model.filter.narrowsContent ? "조건에 맞는 항목이 없습니다"
                    : model.filter.pinnedOnly ? "고정한 항목이 없습니다" : "복사한 항목이 없습니다")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cards: some View {
        ForEach(Array(model.items.enumerated()), id: \.element.persistentModelID) { index, item in
            ClipCard(item: item, isSelected: index == model.selection, scale: model.scale, number: index < 9 ? index + 1 : nil)
                .id(item.persistentModelID)
                .background {
                    if index == model.selection {
                        GeometryReader { Color.clear.preference(key: SelectedCardFrameKey.self, value: $0.frame(in: .global)) }
                    }
                }
                .onTapGesture { onPick(index) }
                .onAppear { onCardAppear(item) }
                .contextMenu {
                    let plainKey = model.alwaysPlainText ? "Return" : "⇧Return"
                    let formattedKey = model.alwaysPlainText ? "⇧Return" : "Return"
                    Button("붙여넣기 (\(formattedKey))") { onAction(.paste(plain: false), item) }
                    // 서식이 있는 종류만 — 일반 텍스트·링크·색상은 결과가 같고, 이미지는 텍스트가 없다.
                    if item.kind == .richText || item.kind == .file {
                        Button("서식 없이 붙여넣기 (\(plainKey))") { onAction(.paste(plain: true), item) }
                    }
                    Divider()
                    Button(item.isPinned ? "고정 해제 (⌘P)" : "고정 (⌘P)") { onAction(.togglePin, item) }
                    Button("이름 변경 (⌘R)") { onAction(.rename, item) }
                    if item.isEditable {
                        Button("내용 편집 (⌘E)") { onAction(.edit, item) }
                        // 하위 메뉴 대신 ⌘T 와 같은 미리보기 화면을 연다 (결과를 보고 고를 수 있게).
                        if !Transform.available(for: item.text).isEmpty {
                            Button("변환해서 붙여넣기 (⌘T)") { onAction(.transform, item) }
                        }
                    }
                    Divider()
                    Button("삭제 (⌫)", role: .destructive) { onAction(.delete, item) }
                }
        }
    }
}

/// ⌘T 변환 목록 (선택한 카드 옆 말풍선). 왼쪽 목록에서 고르고(↑↓·마우스), 오른쪽에 결과 전체를 보여 준다. ←→ 로 옆 카드.
/// 키 입력은 바가 받는다 (AppDelegate.handleKey).
struct TransformList: View {
    let model: BarModel
    let onPaste: (String) -> Void

    var body: some View {
        let transforms = Array(model.transforms.prefix(9))
        let selected = transforms.indices.contains(model.transformSelection) ? transforms[model.transformSelection] : nil
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("변환해서 붙여넣기").font(.system(size: 14, weight: .bold))
                Spacer()
                Text("←→ 카드 · ↑↓ 선택 · Return / 1–9 붙여넣기 · Esc·⌘T 닫기").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(transforms.enumerated()), id: \.offset) { index, transform in
                            Button { onPaste(transform.result) } label: {
                                HStack(spacing: 8) {
                                    Text("\(index + 1)").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                                    Text(transform.label).font(.system(size: 14))
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(index == model.transformSelection ? Color.accentColor.opacity(0.25) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { if $0 { model.transformSelection = index } }
                        }
                    }
                }
                .frame(width: 200)
                Divider()
                ScrollView {
                    Text(selected?.result ?? "")
                        .font(.system(size: 13, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(8)
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
    /// ⌘1–9 번호 (앞 9개만).
    let number: Int?

    private func size(_ base: CGFloat) -> CGFloat { base * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: size(8)) {
            HStack(spacing: size(4)) {
                if item.isPinned {
                    Image(systemName: "pin.fill").foregroundStyle(.orange)
                }
                if let icon = item.sourceBundleID.flatMap(AppInfo.icon) {
                    Image(nsImage: icon).resizable().frame(width: size(14), height: size(14))
                }
                Text(item.sourceBundleID.flatMap(AppInfo.name) ?? "알 수 없는 앱").lineLimit(1)
                Spacer()
                Text(kindLabel)
            }
            .font(.system(size: size(11), weight: .bold))
            .foregroundStyle(.secondary)
            if let title = item.title {
                Text(title).font(.system(size: size(13), weight: .bold)).lineLimit(2)
            }
            Group {
                if let expiresAt = item.expiresAt { masked(until: expiresAt) } else { preview }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                TimelineView(.everyMinute) { context in
                    Text(RelativeTime.label(since: item.copiedAt, now: context.date))
                }
                Spacer()
                if let number { Text("⌘\(number)") }
            }
            .font(.system(size: size(10)))
            .foregroundStyle(.tertiary)
        }
        .padding(size(12))
        .frame(width: size(CardMetrics.width), height: size(CardMetrics.height))
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        }
    }

    /// 민감정보 패턴에 걸린 항목은 내용을 가린다. 붙여넣기·Space 미리보기는 그대로 된다.
    private func masked(until expiresAt: Date) -> some View {
        VStack(alignment: .leading, spacing: size(6)) {
            Label("민감정보", systemImage: "lock.fill").font(.system(size: size(12), weight: .semibold))
            Text("••••••••••••").font(.system(size: size(14), design: .monospaced)).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 10)) { context in
                let minutes = Int((expiresAt.timeIntervalSince(context.date) / 60).rounded(.up))
                Text(minutes <= 1 ? "곧 삭제됩니다" : "\(minutes)분 뒤 삭제")
                    .font(.system(size: size(11))).foregroundStyle(.orange)
            }
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

}

/// 번들 ID → 앱 이름·아이콘. 지금 설치된 앱 기준이라 지운 앱은 nil.
enum AppInfo {
    static func name(of bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")
        }
    }

    static func icon(of bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            NSWorkspace.shared.icon(forFile: $0.path)
        }
    }
}
