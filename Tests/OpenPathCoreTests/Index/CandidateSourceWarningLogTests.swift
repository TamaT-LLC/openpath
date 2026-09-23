import Testing

@testable import OpenPathCore

/// 候補ソースの警告のログ出力（レベルと、info 以上にパスを含めないこと。NFR-05）。
@Suite("CandidateSourceWarningLog")
struct CandidateSourceWarningLogTests {
    static let root = "/Users/me/repos"
    static let limit = 20_000

    @Test("ルートを走査できなかった警告は warning で出し、ルートのパスはメッセージに含めず debugPath に回す", arguments: [
        RootUnavailableReason.notFound, .notDirectory, .unreadable,
    ])
    func rootUnavailableIsWarning(reason: RootUnavailableReason) throws {
        let log = try #require(CandidateSourceWarningLog(warning: .rootUnavailable(root: Self.root, reason: reason)))

        #expect(log.level == .warning)
        #expect(log.detail == Self.root)
        #expect(!log.message.contains("/"))
    }

    @Test("ルートを走査できなかった理由ごとに別のメッセージにする")
    func rootUnavailableReasonsAreDistinguished() {
        let messages = [RootUnavailableReason.notFound, .notDirectory, .unreadable].compactMap {
            CandidateSourceWarningLog(warning: .rootUnavailable(root: Self.root, reason: $0))?.message
        }

        #expect(messages.count == 3)
        #expect(Set(messages).count == messages.count)
    }

    @Test("打ち切りと ghq の失敗は、発生元（RootDirectoryScanner・GhqRepositoryLister）が記録するため重ねて出さない", arguments: [
        CandidateSourceWarning.rootTruncated(root: CandidateSourceWarningLogTests.root, limit: CandidateSourceWarningLogTests.limit),
        .ghqFailed(.notInstalled(searchPath: "/usr/bin:/bin")),
        .ghqFailed(.nonZeroExit(.list, exitCode: 128, standardError: "fatal")),
        .ghqFailed(.timedOut(.root)),
        .ghqFailed(.emptyRoot),
        .ghqFailed(.cancelled),
    ])
    func warningsLoggedAtSourceAreSkipped(warning: CandidateSourceWarning) {
        #expect(CandidateSourceWarningLog(warning: warning) == nil)
    }

    @Test("前回の収集と同じ警告は、5 分ごとに警告を繰り返さないよう debug に落とす")
    func repeatedWarningsAreLoweredToDebug() throws {
        let repeated = CandidateSourceWarning.rootUnavailable(root: Self.root, reason: .notFound)
        let fresh = CandidateSourceWarning.rootUnavailable(root: "/Volumes/External", reason: .notFound)
        let expectedRepeated = try #require(CandidateSourceWarningLog(warning: repeated))
        let expectedFresh = try #require(CandidateSourceWarningLog(warning: fresh))

        let logs = CandidateSourceWarningLog.logs(for: [repeated, fresh], previous: [repeated])

        #expect(logs == [
            CandidateSourceWarningLog(level: .debug, message: expectedRepeated.message, detail: expectedRepeated.detail),
            expectedFresh,
        ])
    }

    @Test("発生元が記録する警告は logs に含めない")
    func logsSkipWarningsLoggedAtSource() {
        let truncated = CandidateSourceWarning.rootTruncated(root: Self.root, limit: Self.limit)
        let ghq = CandidateSourceWarning.ghqFailed(.emptyRoot)

        #expect(CandidateSourceWarningLog.logs(for: [truncated, ghq], previous: []).isEmpty)
    }
}
