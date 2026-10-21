/// Return/키패드 Enter 로 히스토리 항목을 고를 때의 키 처리 순서.
///
/// 바는 비활성화되지 않는 패널이라, 키 윈도우가 되는 순간 앞 앱의 키 포커스를 훔친다.
/// WindowServer 는 눌려 있는 키의 keyUp 이 오기 전에는 그 포커스를 되돌리지 않는다.
/// 그래서 Return keyDown 안에서 패널을 닫고 합성 ⌘V 를 보내면, 이벤트는 키 윈도우가
/// 없는 곳으로 사라지고 클립보드에만 내용이 남는다. keyUp 을 삼킨 다음에 닫고 붙여넣는다.
public struct ReturnPasteGate: Equatable {
    public enum Event: Equatable {
        /// `triggersPaste` 가 false 면 keyDown 에서 저장처럼 다른 일을 이미 끝냈다.
        /// keyUp 은 대상 앱으로 새지 않게 삼키기만 한다.
        case returnDown(triggersPaste: Bool)
        case returnUp
        /// 바가 닫히거나 Esc 로 선택을 취소하면 대기 중인 붙여넣기를 버린다.
        case cancel
    }

    public enum Effect: Equatable {
        /// 이 키는 게이트 몫이 아니다 (편집기의 줄바꿈 keyUp 등).
        case pass
        /// 이벤트만 삼킨다. 붙여넣지 않는다.
        case consume
        /// keyUp 이다. 지금 대기 중인 붙여넣기를 실행한다.
        case paste
    }

    public private(set) var swallowKeyUp = false
    public private(set) var pasteOnKeyUp = false

    public init() {}

    @discardableResult
    public mutating func handle(_ event: Event) -> Effect {
        switch event {
        case .returnDown(let triggersPaste):
            swallowKeyUp = true
            pasteOnKeyUp = triggersPaste
            return .consume
        case .returnUp:
            guard swallowKeyUp else { return .pass }
            let paste = pasteOnKeyUp
            swallowKeyUp = false
            pasteOnKeyUp = false
            return paste ? .paste : .consume
        case .cancel:
            swallowKeyUp = false
            pasteOnKeyUp = false
            return .consume
        }
    }
}
