/// 外部コマンドの実行。テストで実プロセスを起動せずに済むよう抽象化する。
public protocol CommandRunning: Sendable {
    /// コマンドを実行し、終了まで待って結果を返す。
    ///
    /// 非ゼロ終了はエラーにせず `CommandResult.exitCode` で返す。
    /// - Parameters:
    ///   - executable: 実行ファイルの絶対パス。
    ///   - arguments: 引数。シェルを介さずにそのまま渡す。
    ///   - environment: 環境変数。nil なら呼び出し元プロセスの環境を引き継ぐ。
    ///   - timeout: この時間内に終わらなければプロセスを止めて `CommandRunnerError.timedOut` を投げる。
    /// - Throws: `CommandRunnerError`。呼び出し元がキャンセルされたら `CancellationError`。
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        timeout: Duration
    ) async throws -> CommandResult
}

/// 終了したコマンドの結果。
public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    /// 標準出力。UTF-8 として解釈できないバイトは置換文字にする。
    public let standardOutput: String
    /// 標準エラー。UTF-8 として解釈できないバイトは置換文字にする。
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// コマンドが終了コードを返すところまで到達できなかったことを表す。
public enum CommandRunnerError: Error, Equatable, Sendable {
    /// プロセスを起動できなかった（実行ファイルが無い、実行権限が無い等）。
    case launchFailed(executable: String, reason: String)
    /// タイムアウトまでに終了しなかったため止めた。
    case timedOut(executable: String, timeout: Duration)
}
