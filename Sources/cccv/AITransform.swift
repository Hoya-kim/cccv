import CCCVCore
import Foundation
import FoundationModels

/// ⌘T 변환 목록의 한 줄. AI 변환은 목록에서 고를 때 결과를 만든다.
struct TransformEntry {
    let label: String
    var ai: AITransform?
    var result: TransformResult
}

enum TransformResult {
    case ready(String)
    /// AI 변환을 아직 만들지 않았다 (만들다 멈춘 것 포함).
    case pending
    /// 지금까지 받은 부분.
    case generating(String)
    case failed(String)

    /// 붙여넣을 수 있는 결과.
    var text: String? {
        if case .ready(let text) = self { text } else { nil }
    }
}

extension ClipItem {
    /// ⌘T 목록. 기존 변환 뒤에 AI 변환 (Apple Intelligence 를 쓸 수 있을 때만).
    var transformEntries: [TransformEntry] {
        guard isEditable else { return [] }
        let fixed = Transform.available(for: text).map { TransformEntry(label: $0.label, result: .ready($0.result)) }
        guard SystemLanguageModel.default.isAvailable else { return fixed }
        return fixed + AITransform.available(for: text).map { TransformEntry(label: $0.label, ai: $0, result: .pending) }
    }
}

/// 이 Mac 의 모델로 AI 변환을 만든다. 내용을 밖으로 보내지 않는다.
@MainActor
enum AITransformer {
    /// 받은 부분마다 onPartial. 취소되면 .pending (다시 고르면 처음부터).
    static func run(_ transform: AITransform, on text: String, onPartial: (String) -> Void) async -> TransformResult {
        let session = LanguageModelSession(instructions: transform.instructions(for: text))
        let options = GenerationOptions(maximumResponseTokens: transform.maxResponseTokens)
        do {
            var last = ""
            for try await snapshot in session.streamResponse(to: transform.prompt(for: text), options: options) {
                last = snapshot.content
                onPartial(last)
            }
            // 취소하면 스트림이 오류 없이 끝난다 — 받다 만 결과를 완성본으로 넘기지 않는다
            if Task.isCancelled { return .pending }
            let result = AITransform.clean(last)
            return result.isEmpty ? .failed("결과가 비어 있습니다") : .ready(result)
        } catch is CancellationError {
            return .pending
        } catch let error as LanguageModelSession.GenerationError {
            NSLog("cccv: AI 변환 실패 %@", String(describing: error))
            return switch error {
            case .exceededContextWindowSize: .failed("내용이 길어 처리할 수 없습니다")
            case .guardrailViolation, .refusal: .failed("모델이 이 내용의 처리를 거절했습니다")
            case .unsupportedLanguageOrLocale: .failed("지원하지 않는 언어입니다")
            default: .failed(error.localizedDescription)
            }
        } catch {
            NSLog("cccv: AI 변환 실패 %@", String(describing: error))
            return .failed(error.localizedDescription)
        }
    }
}
