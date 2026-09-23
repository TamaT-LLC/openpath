/// 候補ソースの警告 1 件分のログ（DSN-002 §3「失敗時は警告ログのみ」）。
///
/// ルートの打ち切り（RootDirectoryScanner）と ghq の失敗（GhqRepositoryLister）は発生元が記録するため、
/// ここで扱うのは発生元が記録しない「ルートを走査できなかった」警告だけにする。
/// info 以上のメッセージは統合ログで公開扱いになるため（NFR-05）、ルートのパスはメッセージに含めず
/// `detail` として debugPath で別に出す。
struct CandidateSourceWarningLog: Equatable, Sendable {
    let level: LogLevel
    /// パスを含まないメッセージ
    let message: String
    /// debugPath で出すパス
    let detail: String?

    init(level: LogLevel, message: String, detail: String?) {
        self.level = level
        self.message = message
        self.detail = detail
    }

    /// 発生元が記録済みの警告なら nil
    init?(warning: CandidateSourceWarning) {
        switch warning {
        case .rootUnavailable(let root, let reason):
            self.init(level: .warning, message: "候補のルートを走査できませんでした（\(Self.describe(reason))）", detail: root)
        case .rootTruncated, .ghqFailed:
            return nil
        }
    }

    /// `warnings` のログ。前回の収集と同じ警告は、再構築のたびに（5 分ごとに）警告を繰り返さないよう debug に落とす
    static func logs(for warnings: [CandidateSourceWarning], previous: [CandidateSourceWarning]) -> [Self] {
        warnings.compactMap { warning in
            guard let log = Self(warning: warning) else { return nil }
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
