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

    public func request(
        directory: String, text: String, ignoredNames: Set<String>, directoriesOnly: Bool,
        keepingSelection: Bool = false, reload: Bool = false
    ) {
        let newKey = Key(directory: directory, ignoredNames: ignoredNames)
        if key != newKey || reload {
            cancel()
            key = newKey
            startListing(newKey)
        }
        queryTask?.cancel()
        generation += 1
        pendingRequest = Request(text: text, directoriesOnly: directoriesOnly, keepingSelection: keepingSelection)
        searchSnapshot()
    }

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

    private func searchSnapshot() {
        guard let snapshot, let request = pendingRequest else { return }
        let currentGeneration = generation
        queryTask = Task { [weak self, history] in
            let result: DirectorySearchResult
            do {
                try Task.checkCancellation()
                result = try await snapshot.search(
                    request.text, directoriesOnly: request.directoriesOnly,
                    limit: PaletteQuerySession.resultLimit, history: history()
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
