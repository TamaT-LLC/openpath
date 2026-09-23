import Foundation
import os

import OpenPathCore

/// CandidateIndex のテストで共有する固定時刻と組み立て。
/// 実行時刻に依存させないため、frecency の計算は常にこの基準時刻で行う。
enum IndexFixtures {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let oneHour: TimeInterval = 60 * 60
    static let oneDay: TimeInterval = 24 * oneHour

    /// 空クエリで返す上限（UX-001 §2）
    static let emptyQueryLimit = 8
    /// パレットのスクロールで辿れる程度の件数。テストでは上限に掛からない値として使う
    static let generousLimit = 50

    static func ago(_ interval: TimeInterval) -> Date {
        now.addingTimeInterval(-interval)
    }

    /// `history` を履歴として持ち、`missingPaths` 以外はすべて存在するとみなす CandidateIndex。
    static func makeIndex(
        history: [HistoryEntry] = [],
        existence: RecordingFileExistenceChecker = RecordingFileExistenceChecker()
    ) -> CandidateIndex {
        CandidateIndex(fileExistence: existence, now: { now }, history: { history })
    }

    static func directory(_ path: String) -> SourceItem {
        SourceItem(path: path, isDirectory: true)
    }

    static func file(_ path: String) -> SourceItem {
        SourceItem(path: path, isDirectory: false)
    }
}

/// 指定したパス以外は存在するとみなし、問い合わせを記録する存在確認のスタブ。
/// クエリはメインスレッドの外で呼ぶため、記録はロックで守る。
final class RecordingFileExistenceChecker: FileExistenceChecking {
    private struct Record: Sendable {
        var checkedPaths: [String] = []
        var checkedOnMainThread = false
    }

    private let missingPaths: Set<String>
    private let record = OSAllocatedUnfairLock(initialState: Record())

    init(missingPaths: Set<String> = []) {
        self.missingPaths = missingPaths
    }

    /// 問い合わせられたパス（呼ばれた順）
    var checkedPaths: [String] {
        record.withLock { $0.checkedPaths }
    }

    /// 一度でもメインスレッドから問い合わせられたか
    var wasCheckedOnMainThread: Bool {
        record.withLock { $0.checkedOnMainThread }
    }

    func fileExists(atPath path: String) -> Bool {
        let isMainThread = pthread_main_np() != 0
        record.withLock { record in
            record.checkedPaths.append(path)
            record.checkedOnMainThread = record.checkedOnMainThread || isMainThread
        }
        return !missingPaths.contains(path)
    }
}
