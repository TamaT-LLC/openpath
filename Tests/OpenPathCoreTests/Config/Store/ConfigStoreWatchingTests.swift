import Foundation
import Testing

import OpenPathCore

/// 実ファイルを書き換え、監視による自動の読み込み直しを確かめる（FR-CONFIG-01）。
/// イベントの到着は実時間に依存するため、固定時間の sleep ではなく条件が満たされるまでポーリングで待つ。
@Suite("ConfigStore: ファイル監視")
@MainActor
struct ConfigStoreWatchingTests {
    private typealias F = ConfigStoreFixtures

    private let temporaryDirectory: ConfigStoreTemporaryDirectory

    init() throws {
        temporaryDirectory = try ConfigStoreTemporaryDirectory()
    }

    /// `depth` だけを指定した設定ファイルの内容
    private static func contents(depth: Int) -> String {
        "depth = \(depth)\n"
    }

    /// `depth = initialDepth` のファイルを用意して監視を始める
    private func startStore(
        initialDepth: Int = 1,
        timing: ConfigFileWatchTiming = .default
    ) async throws -> ConfigStore {
        let store = F.makeStore(directory: temporaryDirectory.url, timing: timing).store
        try ConfigFileWriter.create(store.fileURL, with: Self.contents(depth: initialDepth))
        await store.start()
        #expect(store.config.depth == initialDepth)
        return store
    }

    private func expectDepth(_ depth: Int, of store: ConfigStore, sourceLocation: SourceLocation = #_sourceLocation) async {
        let isReflected = await F.waitUntil { store.config.depth == depth }
        #expect(isReflected, "depth = \(depth) が反映されなかった（現在: \(store.config.depth)）", sourceLocation: sourceLocation)
    }

    @Test("rename / delete の後は既定で 200ms 待ってから開き直す（DSN-002 §6）")
    func defaultReopenDelayFollowsDesign() {
        #expect(ConfigFileWatchTiming.default.reopenDelay == .milliseconds(200))
        #expect(ConfigFileWatchTiming.default.maxReopenAttempts >= 1)
    }

    @Test("上書き保存（同じ inode への write）で自動的に読み込み直す")
    func reloadsOnInPlaceWrite() async throws {
        let store = try await startStore()
        defer { store.stop() }

        try ConfigFileWriter.overwriteInPlace(store.fileURL, with: Self.contents(depth: 2))

        await expectDepth(2, of: store)
        #expect(store.lastError == nil)
    }

    @Test("アトミック保存（別名で書いて rename）に追従し、置き換わったファイルへの以降の書き込みも検知する")
    func followsAtomicSave() async throws {
        let store = try await startStore()
        defer { store.stop() }

        try ConfigFileWriter.replaceAtomically(store.fileURL, with: Self.contents(depth: 2))
        await expectDepth(2, of: store)

        // 監視が新しいファイルに張り直されていること
        try ConfigFileWriter.overwriteInPlace(store.fileURL, with: Self.contents(depth: 3))
        await expectDepth(3, of: store)
    }

    @Test("アトミック保存を繰り返しても追従し続ける")
    func followsRepeatedAtomicSaves() async throws {
        let store = try await startStore()
        defer { store.stop() }

        for depth in 2...4 {
            try ConfigFileWriter.replaceAtomically(store.fileURL, with: Self.contents(depth: depth))
            await expectDepth(depth, of: store)
        }
    }

    @Test("削除 → 再作成（再オープンの 200ms より後）に追従し、以降の書き込みも検知する")
    func followsDeleteAndRecreate() async throws {
        let store = try await startStore()
        defer { store.stop() }

        try FileManager.default.removeItem(at: store.fileURL)
        try await Task.sleep(for: F.longerThanReopenDelay)
        try ConfigFileWriter.create(store.fileURL, with: Self.contents(depth: 2))
        await expectDepth(2, of: store)
        #expect(store.lastError == nil)

        try ConfigFileWriter.overwriteInPlace(store.fileURL, with: Self.contents(depth: 3))
        await expectDepth(3, of: store)
    }

    @Test("再オープンのリトライを使い切ったら fileNotFound を公開し、その後の再作成にもディレクトリの監視で追従する")
    func followsRecreationAfterRetriesAreExhausted() async throws {
        let store = try await startStore(timing: F.fastTiming)
        defer { store.stop() }
        let filePath = store.fileURL.path(percentEncoded: false)

        try FileManager.default.removeItem(at: store.fileURL)
        let isNotFoundExposed = await F.waitUntil { store.lastError == .fileNotFound(path: filePath) }
        #expect(isNotFoundExposed)
        #expect(store.config.depth == 1)

        try ConfigFileWriter.create(store.fileURL, with: Self.contents(depth: 2))
        await expectDepth(2, of: store)
        #expect(store.lastError == nil)

        try ConfigFileWriter.overwriteInPlace(store.fileURL, with: Self.contents(depth: 3))
        await expectDepth(3, of: store)
    }

    @Test("不正な TOML を保存すると直前の設定を維持して lastError を公開し、直すと解除する")
    func keepsPreviousConfigWhenInvalidFileIsSaved() async throws {
        let store = try await startStore(initialDepth: 4)
        defer { store.stop() }

        try ConfigFileWriter.overwriteInPlace(store.fileURL, with: "depth = \n")
        let isErrorExposed = await F.waitUntil { store.lastError != nil }
        #expect(isErrorExposed)
        #expect(store.config.depth == 4)

        try ConfigFileWriter.replaceAtomically(store.fileURL, with: Self.contents(depth: 5))
        await expectDepth(5, of: store)
        #expect(store.lastError == nil)
    }

    @Test("生成した既定のファイルも監視する")
    func watchesGeneratedFile() async throws {
        let store = F.makeStore(directory: temporaryDirectory.url).store
        defer { store.stop() }
        await store.start()

        try ConfigFileWriter.overwriteInPlace(store.fileURL, with: Self.contents(depth: 6))

        await expectDepth(6, of: store)
    }

    @Test("stop 後は書き換えても読み込み直さない")
    func stopsWatching() async throws {
        let store = try await startStore(timing: F.fastTiming)
        store.stop()

        try ConfigFileWriter.overwriteInPlace(store.fileURL, with: Self.contents(depth: 2))
        // 反映されないことを確かめるため、デバウンスより十分長く待っても変わらないことを見る
        let isReflected = await F.waitUntil(timeout: F.absenceWaitTimeout) { store.config.depth == 2 }

        #expect(!isReflected)
    }
}
