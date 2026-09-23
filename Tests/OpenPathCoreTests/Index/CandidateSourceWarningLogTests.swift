import Testing

@testable import OpenPathCore

/// 候補ソースの警告のログ出力（レベルと、info 以上にパスを含めないこと。NFR-05）。
@Suite("CandidateSourceWarningLog")
struct CandidateSourceWarningLogTests {
    private static let root = "/Users/me/repos"
    private static let searchPath = "/opt/homebrew/bin:/usr/bin:/bin"
    private static let standardError = "fatal: /Users/me/.gitconfig is broken"
    static let launchReason = "The file /usr/local/bin/ghq could not be opened"
    private static let exitCode: Int32 = 128
    private static let limit = 20_000

    /// パスを持つ警告すべて
    static let warningsWithPaths: [CandidateSourceWarning] = [
        .rootUnavailable(root: root, reason: .notFound),
        .rootUnavailable(root: root, reason: .notDirectory),
        .rootUnavailable(root: root, reason: .unreadable),
        .rootTruncated(root: root, limit: limit),
        .ghqFailed(.notInstalled(searchPath: searchPath)),
        .ghqFailed(.launchFailed(.root, reason: launchReason)),
        .ghqFailed(.nonZeroExit(.list, exitCode: exitCode, standardError: standardError)),
    ]

    @Test("ルートの警告は warning で出し、ルートのパスはメッセージに含めず debugPath に回す", arguments: [
        RootUnavailableReason.notFound, .notDirectory, .unreadable,
    ])
    func rootUnavailableIsWarning(reason: RootUnavailableReason) {
        let log = CandidateSourceWarningLog(warning: .rootUnavailable(root: Self.root, reason: reason))

        #expect(log.level == .warning)
        #expect(log.detail == Self.root)
        #expect(!log.message.contains(Self.root))
    }

    @Test("ルートを走査できなかった理由ごとに別のメッセージにする")
    func rootUnavailableReasonsAreDistinguished() {
        let messages = [RootUnavailableReason.notFound, .notDirectory, .unreadable].map {
            CandidateSourceWarningLog(warning: .rootUnavailable(root: Self.root, reason: $0)).message
        }

        #expect(Set(messages).count == messages.count)
    }

    @Test("打ち切りは warning で上限の件数を含める")
    func rootTruncatedIsWarningWithLimit() {
        let log = CandidateSourceWarningLog(warning: .rootTruncated(root: Self.root, limit: Self.limit))

        #expect(log.level == .warning)
        #expect(log.message.contains(String(Self.limit)))
        #expect(log.detail == Self.root)
    }

    @Test("ghq の未インストールは ghq を使わない利用者でも毎回出るため debug に落とす")
    func ghqNotInstalledIsDebug() {
        let log = CandidateSourceWarningLog(warning: .ghqFailed(.notInstalled(searchPath: Self.searchPath)))

        #expect(log.level == .debug)
        #expect(log.detail == Self.searchPath)
    }

    @Test("ghq の取り消しは debug")
    func ghqCancelledIsDebug() {
        let log = CandidateSourceWarningLog(warning: .ghqFailed(.cancelled))

        #expect(log.level == .debug)
    }

    @Test("ghq の異常終了は warning で終了コードを含め、標準エラーは debugPath に回す")
    func ghqNonZeroExitIsWarning() {
        let log = CandidateSourceWarningLog(
            warning: .ghqFailed(.nonZeroExit(.list, exitCode: Self.exitCode, standardError: Self.standardError))
        )

        #expect(log.level == .warning)
        #expect(log.message.contains(String(Self.exitCode)))
        #expect(log.message.contains("ghq list"))
        #expect(log.detail == Self.standardError)
    }

    @Test("ghq の起動失敗・タイムアウト・空の root は warning", arguments: [
        GhqError.launchFailed(.root, reason: CandidateSourceWarningLogTests.launchReason),
        .timedOut(.list),
        .emptyRoot,
    ])
    func otherGhqFailuresAreWarnings(error: GhqError) {
        let log = CandidateSourceWarningLog(warning: .ghqFailed(error))

        #expect(log.level == .warning)
    }

    @Test("debug より上のメッセージにはパスを含めない（NFR-05）", arguments: CandidateSourceWarningLogTests.warningsWithPaths)
    func messagesAboveDebugContainNoPath(warning: CandidateSourceWarning) {
        let log = CandidateSourceWarningLog(warning: warning)

        #expect(log.level == .debug || !log.message.contains("/"))
    }

    @Test("前回の収集と同じ警告は、5 分ごとに警告を繰り返さないよう debug に落とす")
    func repeatedWarningsAreLoweredToDebug() {
        let repeated = CandidateSourceWarning.rootUnavailable(root: Self.root, reason: .notFound)
        let fresh = CandidateSourceWarning.rootTruncated(root: Self.root, limit: Self.limit)

        let logs = CandidateSourceWarningLog.logs(for: [repeated, fresh], previous: [repeated])

        #expect(logs.map(\.level) == [.debug, .warning])
        #expect(logs.map(\.message) == [
            CandidateSourceWarningLog(warning: repeated).message,
            CandidateSourceWarningLog(warning: fresh).message,
        ])
    }
}
