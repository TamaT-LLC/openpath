import Foundation

/// レベル判定とパスの伏せ字処理を行い、各シンクへログを配送する。
///
/// 呼び出し元のスレッドで行うのは時刻の取得とメッセージの組み立てだけで、
/// ファイル I/O は `FileLogSink` がバックグラウンドで行う。
final class AppLogger: Sendable {
    /// これ以上の重要度のメッセージはパスを伏せ字にする（NFR-05）。
    private static let redactionThreshold: LogLevel = .info

    let minimumLevel: LogLevel
    let sinks: [any LogSink]
    private let clock: @Sendable () -> Date

    init(minimumLevel: LogLevel, sinks: [any LogSink], clock: @escaping @Sendable () -> Date = { Date() }) {
        self.minimumLevel = minimumLevel
        self.sinks = sinks
        self.clock = clock
    }

    /// 統合ログ（`os.Logger`）とログファイルの両方に出力するロガーを作る。
    convenience init(configuration: LogConfiguration) {
        self.init(
            minimumLevel: configuration.minimumLevel,
            sinks: [OSLogSink(), FileLogSink(configuration: configuration)]
        )
    }

    func isEnabled(_ level: LogLevel) -> Bool {
        level >= minimumLevel
    }

    func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
        guard isEnabled(level) else { return }
        // レイテンシ計測の精度を保つため、メッセージの組み立てより先に時刻を取得する
        let date = clock()
        let text = level >= Self.redactionThreshold ? PathRedactor.redact(message()) : message()
        emit(LogEntry(date: date, level: level, message: text))
    }

    func debug(_ message: @autoclosure () -> String) {
        log(.debug, message())
    }

    func info(_ message: @autoclosure () -> String) {
        log(.info, message())
    }

    func warning(_ message: @autoclosure () -> String) {
        log(.warning, message())
    }

    func error(_ message: @autoclosure () -> String) {
        log(.error, message())
    }

    /// パスを debug レベルでのみ記録する。最小レベルが info 以上ならパスを評価すらしない。
    func debugPath(_ message: @autoclosure () -> String, path: @autoclosure () -> String) {
        guard isEnabled(.debug) else { return }
        let date = clock()
        emit(LogEntry(date: date, level: .debug, message: message(), path: path()))
    }

    func flush() {
        for sink in sinks {
            sink.flush()
        }
    }

    private func emit(_ entry: LogEntry) {
        for sink in sinks {
            sink.write(entry)
        }
    }
}
