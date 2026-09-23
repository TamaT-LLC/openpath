import os

/// Apple の統合ログ（Console.app / `log` コマンド）へ出力するシンク。
struct OSLogSink: LogSink {
    static let defaultCategory = "app"

    private let logger: Logger

    init(subsystem: String = AppInfo.bundleIdentifier, category: String = OSLogSink.defaultCategory) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func write(_ entry: LogEntry) {
        let type = Self.osLogType(for: entry.level)
        // メッセージは AppLogger で伏せ字処理済みのため公開扱いにする。
        // パスは統合ログが sysdiagnose 等で外部に渡り得るため、debug レベルでも private にする。
        if let path = entry.path {
            logger.log(level: type, "\(entry.message, privacy: .public): \(path, privacy: .private)")
        } else {
            logger.log(level: type, "\(entry.message, privacy: .public)")
        }
    }

    /// 統合ログは OS 側で非同期に永続化され、アプリから待つ手段がないため何もしない。
    func flush() {}

    static func osLogType(for level: LogLevel) -> OSLogType {
        switch level {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
    }
}
