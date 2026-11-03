/// フォルダの列挙は入ったときに一度だけ行い、その結果を打鍵ごとの検索で共有する。
/// 保持するのは現在のフォルダだけ。離れる・閉じる際に破棄し、古い結果は世代照合で捨てる。
@MainActor
public final class DirectoryQuerySession {
    public typealias Load = @Sendable (String, Set<String>) async throws -> DirectorySnapshot
    public typealias Apply = @MainActor (DirectorySearchResult, Bool) -> Void

    private struct Key: Equatable {
        let directory: String
        let ignoredNames: Set<String>
    }

    private struct Request {
        let text: String
        let directoriesOnly: Bool
        let keepingSelection: Bool
        let applicationBundleID: String?
    }

    private let load: Load
    private let apply: Apply
    private let history: @MainActor () -> [HistoryEntry]
    private var key: Key?
    private var snapshot: DirectorySnapshot?
    private var pendingRequest: Request?
    private var listing: Task<Void, Never>?
    private var queryTask: Task<Void, Never>?
    private var generation = 0
    private var listingGeneration = 0

    public init(
        load: @escaping Load = DirectorySnapshot.load,
        history: @escaping @MainActor () -> [HistoryEntry] = { [] },
        apply: @escaping Apply
    ) {
        self.load = load
        self.apply = apply
        self.history = history
    }

    /// 指定したフォルダと除外条件に対応する列挙結果があるか。再列挙中・破棄後は false。
    /// 空やアクセス不可の結果も保持するため、通常の打鍵では読み込み表示を繰り返さない。
    public func isListed(directory: String, ignoredNames: Set<String>) -> Bool {
        snapshot != nil && key == Key(directory: directory, ignoredNames: ignoredNames)
    }

    /// 最新の検索語を記録する。同じキーでは列挙を共有し、キー変更または reload 時は取り直す。
    /// 列挙中の要求は最後の一件だけを保持し、取得済みなら新しい検索で前の検索を取り消す。
    public func request(
        directory: String, text: String, ignoredNames: Set<String>, directoriesOnly: Bool,
        keepingSelection: Bool = false, reload: Bool = false, applicationBundleID: String? = nil
    ) {
        let newKey = Key(directory: directory, ignoredNames: ignoredNames)
        if key != newKey || reload {
            cancel()
            key = newKey
            startListing(newKey)
        }
        queryTask?.cancel()
        generation += 1
        pendingRequest = Request(
            text: text, directoriesOnly: directoriesOnly, keepingSelection: keepingSelection,
            applicationBundleID: applicationBundleID
        )
        searchSnapshot()
    }

    /// 列挙を非同期に開始し、この列挙の世代が有効な場合だけ最新の検索要求へ結果を渡す。
    private func startListing(_ key: Key) {
        let currentGeneration = listingGeneration
        listing = Task { [weak self, load] in
            let snapshot: DirectorySnapshot
            do {
                snapshot = try await load(key.directory, key.ignoredNames)
            } catch is CancellationError {
                return
            } catch {
                snapshot = DirectorySnapshot(items: [], message: PaletteText.directoryUnreadable)
            }
            guard let self, currentGeneration == self.listingGeneration else { return }
            self.listing = nil
            self.snapshot = snapshot
            // 列挙中の打鍵では Task を増やさず、最後の要求だけを列挙完了時に検索する。
            self.searchSnapshot()
        }
    }

    /// 保持したスナップショットを検索し、途中で語や検索範囲が変わっていなければ表示に反映する。
    private func searchSnapshot() {
        guard let snapshot, let request = pendingRequest else { return }
        let currentGeneration = generation
        queryTask = Task { [weak self, history] in
            let result: DirectorySearchResult
            do {
                try Task.checkCancellation()
                result = try await snapshot.search(
                    request.text, directoriesOnly: request.directoriesOnly,
                    limit: PaletteQuerySession.resultLimit, history: history(), applicationBundleID: request.applicationBundleID
                )
            } catch is CancellationError {
                return
            } catch {
                result = DirectorySearchResult(rows: [], message: PaletteText.directoryUnreadable)
            }
            guard let self, currentGeneration == self.generation else { return }
            self.queryTask = nil
            self.apply(result, request.keepingSelection)
        }
    }

    /// 列挙・検索の両世代を無効にし、実行中の処理と保持した候補を破棄する。
    public func cancel() {
        generation += 1
        listingGeneration += 1
        listing?.cancel()
        queryTask?.cancel()
        listing = nil
        queryTask = nil
        key = nil
        snapshot = nil
        pendingRequest = nil
    }
}
