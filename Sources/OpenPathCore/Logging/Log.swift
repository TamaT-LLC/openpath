import os

/// アプリ全体で使うロギングの窓口。
///
/// 統合ログ（`os.Logger`）と `~/Library/Logs/openpath/openpath.log` の両方に出力する。
/// どのスレッドからも呼び出せ、ファイルへの書き込みはバックグラウンドで行う。
///
/// パスは NFR-05 に従い `debugPath(_:path:)` で記録すること。
/// info 以上のメッセージに紛れ込んだパスは `<path>` に置き換えて出力する。
public enum Log {
    private static let current = OSAllocatedUnfairLock(initialState: AppLogger(configuration: LogConfiguration()))

    static var logger: AppLogger {
        current.withLock { $0 }
    }

    /// 出力先や最小レベルを変更する。以降のログは新しい設定で出力される。
    public static func configure(_ configuration: LogConfiguration) {
        install(AppLogger(configuration: configuration))
    }

    /// 共有ロガーを差し替え、以前のロガーを返す。
    @discardableResult
    static func install(_ logger: AppLogger) -> AppLogger {
        let previous = current.withLock { state in
            let previous = state
            state = logger
            return previous
        }
        // 差し替え前に受け付けたログを書き終えてから戻る。
        // 差し替え後に旧ロガーへ届いた書き込みも、FileLogSink の共有キューにより受け付け順で書き込まれる。
        previous.flush()
        return previous
    }

    public static func debug(_ message: @autoclosure () -> String) {
        logger.debug(message())
    }

    public static func info(_ message: @autoclosure () -> String) {
        logger.info(message())
    }

    public static func warning(_ message: @autoclosure () -> String) {
        logger.warning(message())
    }

    public static func error(_ message: @autoclosure () -> String) {
        logger.error(message())
    }

    /// パスを含むログを debug レベルで記録する。最小レベルが info 以上なら何も出力しない。
    ///
    /// ファイルには `メッセージ: パス` の形で出力し、統合ログではパスを private として扱う。
    public static func debugPath(_ message: @autoclosure () -> String, path: @autoclosure () -> String) {
        logger.debugPath(message(), path: path())
    }

    /// 受け付け済みのログをファイルへ書き出し終えるまで待つ。アプリ終了時などに呼ぶ。
    public static func flush() {
        logger.flush()
    }
}
