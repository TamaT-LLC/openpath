/// ログの重要度。宣言順に重要度が高くなり、`Comparable` は宣言順で合成される。
public enum LogLevel: Sendable, CaseIterable, Comparable {
    case debug
    case info
    case warning
    case error

    /// このレベルのメッセージはパスを伏せ字にしてから出力する（NFR-05）。
    /// 統合ログでメッセージを公開扱いにできるかの判定にも使うため、基準をここに一本化する。
    var redactsPaths: Bool {
        self >= .info
    }

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
