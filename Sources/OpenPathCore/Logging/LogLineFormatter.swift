import Foundation

/// ログファイル 1 行分の文字列を組み立てる。
/// 形式: `2026-09-23T12:34:56.789+09:00 [INFO] message`（パス付きは `message: /path`）
struct LogLineFormatter: Sendable {
    private static let pathSeparator = ": "
    private static let escapedNewline = "\\n"

    private let timestampStyle: Date.ISO8601FormatStyle

    init(timeZone: TimeZone) {
        // レイテンシ計測に使うためミリ秒まで出力する
        timestampStyle = Date.ISO8601FormatStyle(
            timeZoneSeparator: .colon,
            includingFractionalSeconds: true,
            timeZone: timeZone
        )
    }

    func format(_ entry: LogEntry) -> String {
        var body = Self.escapingNewlines(entry.message)
        if let path = entry.path {
            body += Self.pathSeparator + Self.escapingNewlines(path)
        }
        return "\(entry.date.formatted(timestampStyle)) [\(entry.level.label)] \(body)\n"
    }

    /// 1 エントリ 1 行を保ち、行単位での集計（レイテンシ計測等）を壊さないためにエスケープする。
    private static func escapingNewlines(_ text: String) -> String {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: escapedNewline)
    }
}
