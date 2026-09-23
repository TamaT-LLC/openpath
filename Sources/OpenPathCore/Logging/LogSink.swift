import Foundation

/// 1 件のログ。レベル判定とパスの伏せ字処理を終えた状態でシンクに渡される。
struct LogEntry: Sendable, Equatable {
    /// 呼び出し時点の時刻。レイテンシ計測に使うため、書き込み時ではなく呼び出し時に取得する。
    let date: Date
    let level: LogLevel
    let message: String
    /// `debugPath` で記録したパス。debug レベル以外では常に nil。
    let path: String?

    init(date: Date, level: LogLevel, message: String, path: String? = nil) {
        self.date = date
        self.level = level
        self.message = message
        self.path = path
    }
}

/// ログの出力先。どのスレッドから呼ばれてもよく、呼び出し元を長くブロックしないこと。
protocol LogSink: Sendable {
    func write(_ entry: LogEntry)
    /// 受け付け済みのログを出力し終えるまで待つ。
    func flush()
}
