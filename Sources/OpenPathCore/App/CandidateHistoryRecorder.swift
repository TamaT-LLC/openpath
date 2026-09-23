/// AppCoordinator の確定の記録（HistoryRecording）を履歴に残し、候補の履歴を取り直させる。
///
/// 候補インデックスの history ソースは HistoryStore の写しから作るため、記録しただけでは
/// 次に開いたパネルの候補（最終使用日時・frecency の並び、新しく確定したパス）に反映されない（DSN-002 §3「確定のたび」）。
@MainActor
public final class CandidateHistoryRecorder: HistoryRecording {
    private let store: any HistoryRecording
    private let didRecord: @MainActor () -> Void

    /// - Parameters:
    ///   - store: 記録先（HistoryStore）。
    ///   - didRecord: 記録した後に呼ぶ。`CandidateIndexRebuilder.refreshHistory()` をつなぐ。
    public init(store: any HistoryRecording, didRecord: @escaping @MainActor () -> Void) {
        self.store = store
        self.didRecord = didRecord
    }

    public func record(path: String) {
        store.record(path: path)
        didRecord()
    }
}
