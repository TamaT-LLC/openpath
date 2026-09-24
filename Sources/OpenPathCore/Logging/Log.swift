import os

/// アプリ全体で使うロギングの窓口。
///
/// 統合ログ（`os.Logger`）に出力し、`configure(_:)` を呼んだ後はログファイルにも出力する。
/// どのスレッドからも呼び出せ、ファイルへの書き込みはバックグラウンドで行う。
///
/// ## 初期化
///
/// - アプリは起動直後に `configure(_:)` を呼ぶこと。呼ぶまではファイルに出力されず、ログは統合ログにのみ残る。
///   既定の設定 `Log.configure(LogConfiguration())` では `~/Library/Logs/openpath/openpath.log` に出力し、
///   最小レベルは DEBUG ビルドで debug、リリースビルドで info になる。
///   アプリは UserDefaults の `logLevel`（`LogConfiguration.minimumLevelPreferenceKey`）で最小レベルを変えられる（QA 用）。
/// - Core のコードからも `Log` を使ってよい。ユニットテストは `configure(_:)` を呼ばないため、
///   テスト中のログが実ユーザーのログディレクトリに書き込まれることはない。
///
/// ## パスの扱い（NFR-05）
///
/// - パス（ファイル・ディレクトリの場所や file URL）は必ず `debugPath(_:path:)` で記録する。
/// - `info` / `warning` / `error` のメッセージにはパスを含めない。これらのメッセージは統合ログで公開扱いになる。
///   ファイル名や、それを含み得る文字列（`Error.localizedDescription` など）も含めない。
/// - 契約違反への安全網として、info 以上のメッセージでパスの開始を検出すると、その位置からメッセージの末尾までを
///   `<path>` に置き換える。パスの終端は判別できないため、引用符や括弧で囲んでいても後続の文脈は失われる。
///   検出はヒューリスティックで相対パスやファイル名は拾えないため、この安全網を前提にしないこと。
public enum Log {
    /// `configure(_:)` が呼ばれるまでは統合ログにのみ出力し、ファイルは作らない。
    /// Swift Testing にはテスト実行全体の前処理を差し込む仕組みがなく、既定でファイルに書くと
    /// Core のコードを通るテストが実ユーザーの `~/Library/Logs` に書き込んでしまうため。
    private static let current = OSAllocatedUnfairLock(
        initialState: AppLogger(minimumLevel: LogConfiguration.defaultMinimumLevel, sinks: [OSLogSink()])
    )

    static var logger: AppLogger {
        current.withLock { $0 }
    }

    /// ログファイルへの出力を有効にし、出力先と最小レベルを設定する。以降のログは新しい設定で出力される。
    ///
    /// アプリは起動直後に呼ぶこと。呼ぶ前に出したログはファイルに残らない。
    /// 再度呼ぶと設定を差し替える。
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

    /// debug ログを出力する設定か。debug ログのためだけの重い処理（AX の読み取り等）を、出力しない設定では省くために使う。
    public static var isDebugEnabled: Bool {
        logger.isEnabled(.debug)
    }

    /// 開発時の詳細を記録する。統合ログではメッセージを private として扱う。
    public static func debug(_ message: @autoclosure () -> String) {
        logger.debug(message())
    }

    /// 運用上の出来事を記録する。
    /// - Important: パスやファイル名を含めないこと。パスは `debugPath(_:path:)` で記録する。
    public static func info(_ message: @autoclosure () -> String) {
        logger.info(message())
    }

    /// 回復可能な問題を記録する。
    /// - Important: パスやファイル名を含めないこと。パスは `debugPath(_:path:)` で記録する。
    public static func warning(_ message: @autoclosure () -> String) {
        logger.warning(message())
    }

    /// 失敗を記録する。
    /// - Important: パスやファイル名を含めないこと。エラーはドメインとコードなどパスを含まない情報で記録し、
    ///   詳細が必要なら `debugPath(_:path:)` を併用する。
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
