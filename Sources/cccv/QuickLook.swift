import AppKit
import CCCVCore
import Quartz
import UniformTypeIdentifiers

/// Space 미리보기. 시스템 Quick Look 창(QLPreviewPanel)은 뜨면서 키 창이 돼 바가 닫히고 위치도 화면 가운데라,
/// Quick Look 의 보기(QLPreviewView)만 키를 받지 않는 작은 창에 넣어 선택한 카드 옆에 띄운다.
/// 파일이 아닌 항목은 임시 파일로 만든다 — 클립보드 내용이 들어 있으니 다음 미리보기·닫기 때 지운다.
@MainActor
final class QuickLook {
    /// 바 창. 미리보기 창을 자식 창으로 붙여 함께 움직이게 한다.
    weak var parent: NSWindow?
    /// 선택한 카드의 화면 좌표.
    var anchor: () -> NSRect? = { nil }
    var position: () -> BarPosition = { .bottom }

    private(set) var isVisible = false
    private let window = PreviewWindow()
    private let previewView: QLPreviewView = QLPreviewView(frame: .zero, style: .normal)
    /// 텍스트·서식 텍스트는 직접 그린다 — QL 의 .txt 보기는 작은 창에서 위가 잘리고, HTML 은 원본 페이지 스타일까지 그린다.
    private let textScroll = NSTextView.scrollableTextView()
    private var textView: NSTextView { textScroll.documentView as! NSTextView }
    private let directory = FileManager.default.temporaryDirectory.appending(path: "cccv-preview")
    private static let size = NSSize(width: 520, height: 380)
    private static let gap: CGFloat = 8

    init() {
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        previewView.frame = background.bounds.insetBy(dx: 8, dy: 8)
        previewView.autoresizingMask = [.width, .height]
        previewView.shouldCloseWithWindow = false
        background.addSubview(previewView)

        textScroll.frame = background.bounds.insetBy(dx: 8, dy: 8)
        textScroll.autoresizingMask = [.width, .height]
        textScroll.drawsBackground = false
        textView.isEditable = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textScroll.wantsLayer = true
        textScroll.layer?.cornerRadius = 8
        background.addSubview(textScroll)

        window.contentView = background
        window.setContentSize(Self.size)
    }

    func show(_ item: ClipItem) {
        if let text = attributedText(for: item) {
            textView.textStorage?.setAttributedString(text.string)
            textView.drawsBackground = text.paper
            textView.backgroundColor = .white
            textView.scroll(.zero)
            textScroll.isHidden = false
            previewView.isHidden = true
            try? FileManager.default.removeItem(at: directory)
        } else {
            guard let url = makeFile(for: item) else { NSSound.beep(); return }
            previewView.previewItem = url as NSURL
            textScroll.isHidden = true
            previewView.isHidden = false
        }
        reposition()
        if !isVisible {
            parent?.addChildWindow(window, ordered: .above)
            window.orderFront(nil)
            isVisible = true
        }
    }

    /// 미리보기가 열려 있을 때 선택이 바뀌면 따라간다.
    func follow(_ item: ClipItem?) {
        guard isVisible, let item else { return }
        show(item)
    }

    /// 카드 위치가 바뀌면(스크롤·선택 이동) 말풍선도 옮긴다.
    func reposition() {
        guard let parent, let card = anchor(), let screen = parent.screen else { return }
        let size = Self.size
        let bar = parent.frame
        var origin: NSPoint = switch position() {
        case .bottom: NSPoint(x: card.midX - size.width / 2, y: bar.maxY + Self.gap)
        case .top: NSPoint(x: card.midX - size.width / 2, y: bar.minY - Self.gap - size.height)
        case .left: NSPoint(x: bar.maxX + Self.gap, y: card.midY - size.height / 2)
        case .right: NSPoint(x: bar.minX - Self.gap - size.width, y: card.midY - size.height / 2)
        }
        // 화면 밖으로 나가지 않게
        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX + Self.gap), visible.maxX - size.width - Self.gap)
        origin.y = min(max(origin.y, visible.minY + Self.gap), visible.maxY - size.height - Self.gap)
        window.setFrameOrigin(origin)
    }

    func close() {
        guard isVisible else { return }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
        previewView.previewItem = nil
        isVisible = false
        try? FileManager.default.removeItem(at: directory)
    }

    /// 텍스트는 읽기 좋은 글꼴로, 서식 텍스트는 서식을 살려 흰 종이(paper) 위에.
    /// 웹에서 복사한 서식은 글자색이 검정으로 박혀 있어 어두운 배경에선 안 보이기 때문이다.
    private func attributedText(for item: ClipItem) -> (string: NSAttributedString, paper: Bool)? {
        switch item.kind {
        case .text:
            return (NSAttributedString(string: item.text, attributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor,
            ]), false)
        case .richText:
            let rich = item.payload.flatMap { data in
                item.payloadType == "public.html"
                    ? NSAttributedString(html: data, documentAttributes: nil)
                    : NSAttributedString(rtf: data, documentAttributes: nil)
            }
            return rich.map { ($0, true) }
                ?? (NSAttributedString(string: item.text, attributes: [.font: NSFont.systemFont(ofSize: 14)]), true)
        case .file:
            // 텍스트 파일(md·txt·코드)도 QL 로 그리면 위가 잘린다 → 직접 읽는다. 이미지·PDF 등은 QL 에 맡긴다.
            return item.text.split(separator: "\n").first.flatMap { textFile(at: URL(filePath: String($0))) }.map { ($0, false) }
        default:
            return nil
        }
    }

    /// 텍스트 계열 파일(md·txt·코드·json·yml·csv·log 등)이면 앞부분을 고정폭 글꼴로. 너무 크면 잘라서 보여 준다.
    /// RTF·HTML 은 원문 그대로면 태그가 보이므로 QL 에 맡긴다.
    private func textFile(at url: URL) -> NSAttributedString? {
        guard let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .text), !type.conforms(to: .rtf), !type.conforms(to: .html),
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let limit = 512 * 1024
        guard let data = try? handle.read(upToCount: limit + 1) else { return nil }
        // 잘린 끝에서 멀티바이트 글자가 깨지지 않도록 lossy 디코딩
        var text = String(decoding: data.prefix(limit), as: UTF8.self)
        if data.count > limit { text += "\n\n… (512KB 이후 생략)" }
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.labelColor,
        ])
    }

    private func makeFile(for item: ClipItem) -> URL? {
        if item.kind == .file {
            // ponytail: 여러 파일이면 첫 파일만 미리본다.
            return item.text.split(separator: "\n").first.map { URL(filePath: String($0)) }
        }
        try? FileManager.default.removeItem(at: directory) // 이전 임시 파일은 바로 지운다
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let (data, ext): (Data?, String) = switch item.kind {
        case .image: (item.payload, item.payloadType == "public.tiff" ? "tiff" : "png")
        case .link: (Data(linkHTML(item).utf8), "html")
        case .color: (Data(colorHTML(item.text).utf8), "html")
        case .text, .richText, .file: (nil, "") // 텍스트는 attributedText, 파일은 원본 경로
        }
        guard let data else { return nil }
        let url = directory.appending(path: "\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url)
            return url
        } catch {
            NSLog("cccv: 미리보기 파일 생성 실패 %@", String(describing: error))
            return nil
        }
    }

    /// 링크: OG 이미지·제목·주소. 이미지는 저장해 둔 것이라 네트워크 요청이 없다.
    private func linkHTML(_ item: ClipItem) -> String {
        let image = item.linkImage.map { #"<img src="data:image/png;base64,\#($0.base64EncodedString())">"# } ?? ""
        return page("""
        \(image)
        <h1>\(escape(item.linkTitle ?? URL(string: item.text)?.host() ?? ""))</h1>
        <p class="url">\(escape(item.text))</p>
        """)
    }

    private func colorHTML(_ hex: String) -> String {
        page(#"<div class="swatch" style="background:\#(escape(hex))"></div><h1>\#(escape(hex))</h1>"#)
    }

    private func page(_ body: String) -> String {
        """
        <!doctype html><meta charset="utf-8">
        <style>
          body { font: 15px -apple-system; margin: 24px; color: #222; background: #fff; }
          @media (prefers-color-scheme: dark) { body { color: #eee; background: #1e1e1e; } }
          img { max-width: 100%; border-radius: 10px; }
          h1 { font-size: 20px; }
          .url { font: 13px ui-monospace; word-break: break-all; opacity: .7; }
          .swatch { height: 220px; border-radius: 14px; border: 1px solid #8884; }
        </style>
        <body>\(body)</body>
        """
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// 키 창이 될 수 없는 창 — 떠 있어도 바가 키 입력을 계속 받고, 포커스를 잃어 닫히지 않는다.
private final class PreviewWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
