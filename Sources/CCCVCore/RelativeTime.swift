import Foundation

public enum RelativeTime {
    /// 분 단위에서 절삭한 "x분 전". 1분 미만은 "방금 전", 60분 이상은 시간·일 단위.
    public static func label(since date: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "방금 전" }
        if minutes < 60 { return "\(minutes)분 전" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)시간 전" }
        return "\(hours / 24)일 전"
    }
}
