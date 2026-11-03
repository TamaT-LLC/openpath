import OpenPathCore

/// キャンセルを記録しつつ、テストで指定した順番に列挙を完了させる。
@MainActor
final class ScriptedDirectoryLoad {
    private(set) var paths: [String] = []
    private(set) var ignoredNames: [Set<String>] = []
    private(set) var cancelled: Set<Int> = []
    private var pending: [Int: CheckedContinuation<DirectorySnapshot, Error>] = [:]

    nonisolated var load: DirectoryQuerySession.Load {
        { path, ignoredNames in try await self.perform(path, ignoredNames: ignoredNames) }
    }

    private func perform(_ path: String, ignoredNames: Set<String>) async throws -> DirectorySnapshot {
        let index = paths.count
        paths.append(path)
        self.ignoredNames.append(ignoredNames)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending[index] = $0 }
        } onCancel: {
            Task { @MainActor in self.cancelled.insert(index) }
        }
    }

    func respond(_ index: Int, items: [SourceItem] = [], message: String? = nil) {
        pending.removeValue(forKey: index)?.resume(returning: DirectorySnapshot(items: items, message: message))
    }

    func waitForCalls(_ count: Int) async {
        await MainActorQueue.waitUntil { self.paths.count >= count }
    }
}
