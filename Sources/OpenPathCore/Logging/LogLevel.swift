/// ログの重要度。宣言順に重要度が高くなり、`Comparable` は宣言順で合成される。
public enum LogLevel: Sendable, CaseIterable, Comparable {
    case debug
    case info
    case warning
    case error

    /// ファイル出力で使うラベル。
    var label: String {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warning: "WARNING"
        case .error: "ERROR"
        }
    }
}
