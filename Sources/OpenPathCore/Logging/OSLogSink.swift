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
        // privacy は定数で渡す必要があるため、公開・非公開で呼び出しを分ける。
        // 統合ログは sysdiagnose 等で外部に渡り得るため、パスはどのレベルでも private にする。
        // パス付きエントリは debugPath 由来の debug なので、メッセージも非公開にする。
        if let path = entry.path {
            logger.log(level: type, "\(entry.message, privacy: .private): \(path, privacy: .private)")
        } else if Self.isMessagePublic(for: entry.level) {
            logger.log(level: type, "\(entry.message, privacy: .public)")
        } else {
            logger.log(level: type, "\(entry.message, privacy: .private)")
        }
    }

    /// 統合ログは OS 側で非同期に永続化され、アプリから待つ手段がないため何もしない。
    func flush() {}

    /// メッセージを統合ログで公開扱いにするか。
    ///
    /// info 以上は AppLogger でパスを伏せ字にした後の、運用上の出来事を表す文言に限られるため公開する。
    /// 同じ文言はログファイルにもそのまま出るので、統合ログだけ非公開にしても露出は減らず、Console.app での調査性を優先する。
    /// debug は伏せ字にせずパス等の機微情報を含み得るため、非公開にする（CWE-532）。
    static func isMessagePublic(for level: LogLevel) -> Bool {
        level.redactsPaths
    }

    static func osLogType(for level: LogLevel) -> OSLogType {
        switch level {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
    }
}
