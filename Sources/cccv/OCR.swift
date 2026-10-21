import CCCVCore
import Foundation
import Vision

/// 이미지 속 글자 인식 (Vision). 아직 인식하지 않은 이미지를 최신 것부터 하나씩 처리한다.
@MainActor
final class OCRQueue {
    private let store: ClipStore
    private var running = false
    /// 인식 결과가 저장될 때 (검색 결과를 다시 읽게).
    var onUpdate: () -> Void = {}

    init(store: ClipStore) {
        self.store = store
    }

    /// 새 이미지가 들어왔을 때·실행 시 부른다. 이미 돌고 있으면 그 루프가 이어서 처리한다.
    func process() {
        guard !running else { return }
        running = true
        Task {
            defer { running = false }
            while let job = try? store.nextImageForOCR() {
                let text = await Self.recognize(job.data)
                do {
                    try store.setOCR(job.id, text: text) // 실패(nil)도 처리 완료로 — 다시 시도하지 않는다
                } catch {
                    NSLog("cccv: OCR 결과 저장 실패 %@", String(describing: error))
                    return // 저장이 안 되면 같은 이미지를 무한 반복하지 않게 멈춘다
                }
                onUpdate()
            }
        }
    }

    /// 메인 스레드 밖에서 인식한다. 한국어·영어.
    @concurrent
    nonisolated private static func recognize(_ data: Data) async -> String? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "ko-KR"), Locale.Language(identifier: "en-US")]
        do {
            let observations = try await request.perform(on: data)
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        } catch {
            NSLog("cccv: OCR 실패 %@", String(describing: error))
            return nil
        }
    }
}
