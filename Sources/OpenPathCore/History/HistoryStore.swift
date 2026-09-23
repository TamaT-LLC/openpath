import Foundation

/// 確定したパスの履歴を保持し、`history.json` へ永続化する（DSN-002 §7）。
///
/// AppCoordinator（HistoryRecording）と CandidateIndex から UI スレッドで同期的に読み書きするため MainActor に隔離する。
/// 保存も MainActor 上で直列に行い、デバウンスによる保存と終了時の `flush()` が前後しないようにする
/// （上限 2,000 件で数百 KB 程度のため、500ms に 1 回までの書き込みならメインスレッドへの影響は小さい）。
@MainActor
public final class HistoryStore: HistoryRecording {
    /// 最後の `record` からこの時間だけ次の記録が無ければ保存する。
    public static let saveDebounceInterval: Duration = .milliseconds(500)

    /// 起動時の読み込み結果。破損ファイルを退避した場合の通知等に使う。
    public let loadResult: HistoryLoadResult

    private var list: HistoryList
    private let persistence: any HistoryPersisting
    /// `clock` という名前は Foundation 経由で見える Darwin の `clock()` と衝突し、存在型を開けなくなるため避ける。
    private let debounceClock: any Clock<Duration>
    private let now: @Sendable () -> Date
    private let fileExistence: any FileExistenceChecking
    private var pendingSave: Task<Void, Never>?
    private var hasUnsavedChanges = false

    /// 生成時に `persistence` から履歴を読み込む。
    /// - Parameters:
    ///   - persistence: 読み書き先。アプリでは `HistoryFile(directory: HistoryFile.defaultDirectory)` を渡す。
    ///   - clock: デバウンスの計測に使う。テストでは手動で進める Clock を渡す。
    ///   - now: 記録日時と、保存時の掃除（90 日未使用の判定）に使う。
    ///   - fileExistence: 保存時の掃除で存在確認に使う。
    public init(
        persistence: any HistoryPersisting,
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date() },
        fileExistence: any FileExistenceChecking = LocalFileExistenceChecker()
    ) {
        self.persistence = persistence
        debounceClock = clock
        self.now = now
        self.fileExistence = fileExistence
        loadResult = persistence.load()
        list = HistoryList(entries: loadResult.entries)
    }

    /// 初出順の履歴。
    public var entries: [HistoryEntry] {
        list.entries
    }

    /// frecency 降順の履歴（空入力時の候補表示用）。
    public func sortedByFrecency(now: Date) -> [HistoryEntry] {
        list.sortedByFrecency(now: now)
    }

    /// 確定を記録し、`saveDebounceInterval` 後に保存する。続けて記録された場合は最後の記録から数え直す。
    public func record(path: String) {
        list.record(path: path, now: now())
        hasUnsavedChanges = true
        scheduleSave()
    }

    /// 履歴を空にして即座に保存する。
    /// 利用者が明示的に消した履歴が、直後の異常終了でディスクに残らないようデバウンスしない。
    public func clear() {
        list = HistoryList()
        hasUnsavedChanges = true
        flush()
    }

    /// 保留中の変更があれば即座に保存する。アプリ終了時に呼ぶ。
    /// 保存時に 90 日以上未使用かつ存在しないエントリを取り除く（FR-HISTORY-03）。
    /// 保存に失敗した場合は変更を未保存のまま残し、次の `record` や `flush` で保存し直す。
    public func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasUnsavedChanges else { return }

        list = list.pruned(now: now(), fileExistence: fileExistence)
        do {
            try persistence.save(list.entries)
            hasUnsavedChanges = false
        } catch {
            // TODO(#3): Log.warning で保存の失敗を記録する
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Self.makeDebouncedTask(on: debounceClock) { [weak self] in
            self?.flush()
        }
    }

    /// 期限は呼び出し時点で確定させる。Task の開始が遅れても 500ms の起点がずれないようにするため。
    private static func makeDebouncedTask<C: Clock<Duration>>(
        on clock: C,
        action: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        let deadline = clock.now.advanced(by: saveDebounceInterval)
        return Task {
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
                return
            }
            // 待機が終わってから MainActor に戻るまでの間に次の記録で取り消された場合は保存しない
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
