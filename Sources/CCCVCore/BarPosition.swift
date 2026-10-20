public enum BarPosition: String, CaseIterable, Sendable {
    case bottom, top, left, right

    public var isHorizontal: Bool { self == .bottom || self == .top }

    public var label: String {
        switch self {
        case .bottom: "아래"
        case .top: "위"
        case .left: "왼쪽"
        case .right: "오른쪽"
        }
    }
}
