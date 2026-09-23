import Foundation

/// 履歴の読み書き先（DSN-002 §7）。HistoryStore から保存タイミングの制御を切り離し、テストで差し替えるために抽象化する。
/// HistoryStore と同じく MainActor から呼ぶ。
@MainActor
public protocol HistoryPersisting {
    /// 保存済みの履歴を読み込む。失敗時の後始末（破損ファイルの退避等）も実装側で行い、呼び出し側には結果だけを返す。
    func load() -> HistoryLoadResult

    /// 履歴全体を書き込む。
    func save(_ entries: [HistoryEntry]) throws
}

/// 起動時の読み込み結果。
public enum HistoryLoadResult: Equatable, Sendable {
    /// ファイルが無い（初回起動など）。空の履歴から始める。
    case notFound
    /// 読み込めた。
    case loaded([HistoryEntry])
    /// 読み込めなかったため空の履歴から始める。
    /// `movedTo` は破損ファイルの退避先。退避にも失敗した場合は nil で、ファイルは元の場所に残る。
    case corrupted(movedTo: URL?)

    /// 起動時に使う履歴。読み込めなかった場合は空。
    public var entries: [HistoryEntry] {
        guard case .loaded(let entries) = self else { return [] }
        return entries
    }
}
