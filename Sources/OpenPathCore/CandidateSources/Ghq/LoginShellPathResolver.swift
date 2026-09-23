import Foundation

/// 実行ファイルを探すための検索パス（PATH 形式）を提供する。
public protocol SearchPathProviding: Sendable {
    func searchPath() async -> String
}

/// login shell から PATH を取得する SearchPathProviding。
///
/// GUI アプリは launchd の最小限の PATH で起動し Homebrew 等が通っていないため、
/// シェルの設定を反映した login shell に PATH を問い合わせる。login shell は設定次第で重く、
/// 固まることもあるため、タイムアウトを設けて失敗時は既定 PATH を使う。
/// 結果はフォールバックも含めて初回に 1 度だけ取得してキャッシュする。複数の利用者で共有すること。
public actor LoginShellPathResolver: SearchPathProviding {
    public static let defaultShellPath = "/bin/zsh"
    /// login shell に PATH を出力させる引数。
    public static let printPathArguments = ["-lc", "echo $PATH"]
    public static let defaultTimeout: Duration = .seconds(3)
    /// login shell から取得できないときの PATH。Homebrew（Apple Silicon / Intel）とシステムのディレクトリ。
    public static let defaultFallbackSearchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    private let runner: any CommandRunning
    private let shellPath: String
    private let timeout: Duration
    private let fallbackSearchPath: String
    /// 同時に呼ばれても login shell を 1 度だけ起動するよう、取得処理を Task ごと保持する。
    private var resolution: Task<String, Never>?

    /// - Parameters:
    ///   - runner: login shell の実行に使う。
    ///   - shellPath: login shell の実行ファイル。
    ///   - timeout: login shell の応答を待つ上限。
    ///   - fallbackSearchPath: login shell から取得できないときの PATH。取得できたときも不足分を末尾に補う。
    public init(
        runner: any CommandRunning = ProcessCommandRunner(),
        shellPath: String = defaultShellPath,
        timeout: Duration = defaultTimeout,
        fallbackSearchPath: String = defaultFallbackSearchPath
    ) {
        self.runner = runner
        self.shellPath = shellPath
        self.timeout = timeout
        self.fallbackSearchPath = fallbackSearchPath
    }

    public func searchPath() async -> String {
        if let resolution {
            return await resolution.value
        }
        let task = Task { [runner, shellPath, timeout, fallbackSearchPath] in
            await Self.resolve(
                runner: runner,
                shellPath: shellPath,
                timeout: timeout,
                fallbackSearchPath: fallbackSearchPath
            )
        }
        resolution = task
        return await task.value
    }

    private static func resolve(
        runner: any CommandRunning,
        shellPath: String,
        timeout: Duration,
        fallbackSearchPath: String
    ) async -> String {
        let fallbackEntries = ShellSearchPath.absoluteEntries(of: fallbackSearchPath)
        guard let loginEntries = await loginShellEntries(runner: runner, shellPath: shellPath, timeout: timeout) else {
            // TODO(#3): Log が main に入ったら、フォールバックしたことを警告ログに出す
            return ShellSearchPath.join(fallbackEntries)
        }
        // login shell の設定が zsh 以外（bash / fish 等）にある環境でも Homebrew 等を見つけられるよう、既定 PATH の不足分を補う
        return ShellSearchPath.join((loginEntries + fallbackEntries).removingDuplicates())
    }

    /// login shell が出力した PATH の絶対パスのエントリ。取得できなければ nil。
    private static func loginShellEntries(
        runner: any CommandRunning,
        shellPath: String,
        timeout: Duration
    ) async -> [String]? {
        let result: CommandResult
        do {
            result = try await runner.run(
                executable: shellPath,
                arguments: printPathArguments,
                environment: nil,
                timeout: timeout
            )
        } catch {
            return nil
        }
        guard result.exitCode == 0 else { return nil }
        // シェルの設定ファイルがメッセージを出力することがあるため、最後の行を PATH とみなす
        let lastLine = result.standardOutput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        guard let lastLine else { return nil }
        let entries = ShellSearchPath.absoluteEntries(of: lastLine)
        return entries.isEmpty ? nil : entries
    }
}
