import OpenPathCore

/// パレットの候補検索（`PaletteQuerySession.Search`）の偽物。
/// 呼ばれた検索を保留し、テストが結果を返す順番とタイミングを決める。
/// 取り消されても自分からは戻らず記録だけするため、取り消しを無視して結果を返す検索も再現できる。
@MainActor
final class ScriptedPaletteSearch {
    struct Call: Equatable {
        let text: String
        let directoriesOnly: Bool
        let limit: Int
    }

    /// 呼ばれた検索（呼ばれた順）
    private(set) var calls: [Call] = []
    /// 取り消された呼び出しの添字
    private(set) var cancelledCalls: Set<Int> = []
    private var pending: [Int: CheckedContinuation<[PaletteRow], any Error>] = [:]
    /// 結果を待つ状態になった呼び出しの数
    private var suspendedCount = 0
    private let waiter = ConditionWaiter()

    /// セッションに渡す検索。
    nonisolated var search: PaletteQuerySession.Search {
        { text, directoriesOnly, limit in
            try await self.perform(Call(text: text, directoriesOnly: directoriesOnly, limit: limit))
        }
    }

    /// 検索が `count` 回呼ばれ、それぞれ結果を待つ状態になるまで待つ。
    func waitForCalls(_ count: Int) async {
        await waiter.wait { self.suspendedCount >= count }
    }

    /// `index` 番目の呼び出しが取り消されるまで待つ。
    func waitForCancellation(of index: Int) async {
        await waiter.wait { self.cancelledCalls.contains(index) }
    }

    func respond(to index: Int, with rows: [PaletteRow]) {
        pending.removeValue(forKey: index)?.resume(returning: rows)
    }

    func fail(_ index: Int, with error: any Error) {
        pending.removeValue(forKey: index)?.resume(throwing: error)
    }

    private func perform(_ call: Call) async throws -> [PaletteRow] {
        let index = calls.count
        calls.append(call)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[index] = continuation
                suspendedCount += 1
                waiter.notify()
            }
        } onCancel: {
            Task { @MainActor in self.didCancel(index) }
        }
    }

    private func didCancel(_ index: Int) {
        cancelledCalls.insert(index)
        waiter.notify()
    }
}

/// パレットの行のテスト用の組み立て。
enum PaletteRowFixtures {
    static func rows(_ names: String...) -> [PaletteRow] {
        names.map { PaletteRow(name: $0, path: "/Users/example/repos/\($0)", lastUsed: nil) }
    }
}
