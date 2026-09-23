import Foundation
import os

@testable import OpenPathCore

/// テスト専用の一時ディレクトリを作成して `body` に渡し、終了後に削除する。
/// 実ユーザーの `~/Library/Logs/openpath` に書き込まないため、ファイル出力を伴うテストは必ずこれを使う。
func withTemporaryDirectory<Result>(_ body: (URL) throws -> Result) throws -> Result {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "openpath-logging-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

/// ログファイルを行単位で読み出す。
func readLogLines(at url: URL) throws -> [String] {
    try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map(String.init)
}

/// 受け取ったエントリと flush 回数を記録するテスト用シンク。
final class SpyLogSink: LogSink {
    private struct State {
        var entries: [LogEntry] = []
        var flushCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var entries: [LogEntry] { state.withLock { $0.entries } }
    var flushCount: Int { state.withLock { $0.flushCount } }

    func write(_ entry: LogEntry) {
        state.withLock { $0.entries.append(entry) }
    }

    func flush() {
        state.withLock { $0.flushCount += 1 }
    }
}

/// `FileLogSink` の書き込み失敗通知の回数を記録する。
final class FailureRecorder: Sendable {
    private let failureCount = OSAllocatedUnfairLock(initialState: 0)

    var count: Int { failureCount.withLock { $0 } }

    func record(_: any Error) {
        failureCount.withLock { $0 += 1 }
    }
}

/// 期待値を固定するため、小数部が 2 進数で正確に表現できる時刻（.125 秒）を使う。
let fixedDate = Date(timeIntervalSince1970: 1_700_000_000.125)

/// 実行環境のタイムゾーンに依存しない出力を得るため、フォーマットのテストは UTC で行う。
let utcTimeZone = TimeZone.gmt
