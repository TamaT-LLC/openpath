import Foundation

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

    /// 設定値（`defaults write jp.tamat.openpath logLevel debug` など）の文字列から読む。
    /// 大文字小文字と前後の空白は区別しない。どのレベルにも当たらなければ nil。
    public init?(preferenceValue: String) {
        let normalized = preferenceValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let level = Self.allCases.first(where: { $0.preferenceValue == normalized }) else { return nil }
        self = level
    }

    /// 設定値として書く文字列（`debug` / `info` / `warning` / `error`）。
    public var preferenceValue: String {
        label.lowercased()
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
