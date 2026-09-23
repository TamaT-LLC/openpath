/// 候補ソースの警告 1 件分のログ（DSN-002 §3「失敗時は警告ログのみ」）。
///
/// info 以上のメッセージは統合ログで公開扱いになるため（NFR-05）、パス（ルート・PATH）と、パスを含み得る文字列
/// （ghq の標準エラー・起動失敗の理由）はメッセージに含めず、`detail` として debugPath で別に出す。
struct CandidateSourceWarningLog: Equatable, Sendable {
    let level: LogLevel
    /// パスを含まないメッセージ
    let message: String
    /// debugPath で出すパスや詳細
    let detail: String?

    init(level: LogLevel, message: String, detail: String?) {
        self.level = level
        self.message = message
        self.detail = detail
    }

    init(warning: CandidateSourceWarning) {
        switch warning {
        case .rootUnavailable(let root, let reason):
            self.init(level: .warning, message: "候補のルートを走査できませんでした（\(Self.describe(reason))）", detail: root)
        case .rootTruncated(let root, let limit):
            self.init(level: .warning, message: "候補のルート配下が上限の \(limit) 件を超えたため、走査を打ち切りました", detail: root)
        case .ghqFailed(let error):
            self.init(ghqError: error)
        }
    }

    private init(ghqError: GhqError) {
        switch ghqError {
        case .notInstalled(let searchPath):
            // ghq を使わない利用者では再構築のたびに出るため、利用者向けの警告にはしない
            self.init(level: .debug, message: "ghq が見つからないため、ghq の候補を省きました", detail: searchPath)
        case .launchFailed(let subcommand, let reason):
            self.init(level: .warning, message: "\(Self.commandLine(subcommand)) を起動できませんでした", detail: reason)
        case .nonZeroExit(let subcommand, let exitCode, let standardError):
            self.init(
                level: .warning,
                message: "\(Self.commandLine(subcommand)) が終了コード \(exitCode) で失敗しました",
                detail: standardError
            )
        case .timedOut(let subcommand):
            self.init(level: .warning, message: "\(Self.commandLine(subcommand)) が時間内に終了しませんでした", detail: nil)
        case .emptyRoot:
            self.init(level: .warning, message: "ghq root の出力が空でした", detail: nil)
        case .cancelled:
            self.init(level: .debug, message: "ghq の実行を取り消しました", detail: nil)
        }
    }

    /// `warnings` のログ。前回の収集と同じ警告は、再構築のたびに（5 分ごとに）警告を繰り返さないよう debug に落とす
    static func logs(for warnings: [CandidateSourceWarning], previous: [CandidateSourceWarning]) -> [Self] {
        warnings.map { warning in
            let log = Self(warning: warning)
            guard previous.contains(warning) else { return log }
            return Self(level: .debug, message: log.message, detail: log.detail)
        }
    }

    /// `Log` の公開 API はレベルごとのメソッドのため、レベルを値で渡せる内部のロガーに出す
    func emit() {
        guard let detail, !detail.isEmpty else {
            Log.logger.log(level, message)
            return
        }
        // debug のメッセージは debugPath の 1 行で足りる
        if level > .debug {
            Log.logger.log(level, message)
        }
        Log.debugPath(message, path: detail)
    }

    private static func describe(_ reason: RootUnavailableReason) -> String {
        switch reason {
        case .notFound: "存在しません"
        case .notDirectory: "ディレクトリではありません"
        case .unreadable: "読み取る権限がありません"
        }
    }

    private static func commandLine(_ subcommand: GhqSubcommand) -> String {
        (["ghq"] + subcommand.arguments).joined(separator: " ")
    }
}

extension CandidateSourceKind {
    /// ログのメッセージに使うソースの種別名。ルートのパスは含めない（パスは `logPath` を debugPath で出す）
    var logLabel: String {
        switch self {
        case .history: "history"
        case .root: "roots"
        case .ghq: "ghq"
        }
    }

    /// debugPath で出すルートのパス。ルート以外は nil
    var logPath: String? {
        guard case .root(let root) = self else { return nil }
        return root
    }
}
