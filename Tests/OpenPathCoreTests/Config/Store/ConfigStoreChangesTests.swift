import Foundation
import Testing

import OpenPathCore

/// 設定変更の購読（`changes()`）。`stop()` でストリームが終わることを利用し、流れた値を過不足なく確かめる。
@Suite("ConfigStore: 設定変更の購読")
@MainActor
struct ConfigStoreChangesTests {
    private typealias F = ConfigStoreFixtures

    private static let initialContents = "depth = 5\n"
    private static let initialConfig = Config(depth: 5)

    private let temporaryDirectory: ConfigStoreTemporaryDirectory
    private let store: ConfigStore

    init() throws {
        temporaryDirectory = try ConfigStoreTemporaryDirectory()
        store = F.makeStore(directory: temporaryDirectory.url).store
    }

    private func startWithInitialFile() async throws {
        try ConfigFileWriter.create(store.fileURL, with: Self.initialContents)
        await store.start()
    }

    private func rewriteAndReload(_ contents: String) throws {
        try ConfigFileWriter.overwriteInPlace(store.fileURL, with: contents)
        store.reload()
    }

    @Test("設定が変わったら新しい設定を流す")
    func yieldsChangedConfig() async throws {
        try await startWithInitialFile()
        let changes = store.changes()

        try rewriteAndReload("depth = 7\n")
        store.stop()

        #expect(await F.collectAll(changes) == [Config(depth: 7)])
    }

    @Test("内容が同じなら（コメントや書式だけの変更）流さない")
    func doesNotYieldWhenConfigIsEqual() async throws {
        try await startWithInitialFile()
        let changes = store.changes()

        try rewriteAndReload("# コメントを追加\ndepth   =   5\n")
        store.stop()

        #expect(await F.collectAll(changes).isEmpty)
    }

    @Test("読み込みに失敗したときは流さない")
    func doesNotYieldOnFailure() async throws {
        try await startWithInitialFile()
        let changes = store.changes()

        try rewriteAndReload("depth = \n")
        store.stop()

        #expect(store.lastError != nil)
        #expect(await F.collectAll(changes).isEmpty)
    }

    @Test("起動時の読み込みで既定値から変わったら流す")
    func yieldsInitialLoadWhenDifferentFromDefault() async throws {
        let changes = store.changes()

        try await startWithInitialFile()
        store.stop()

        #expect(await F.collectAll(changes) == [Self.initialConfig])
    }

    @Test("購読者それぞれに同じ変更を流す")
    func yieldsToEverySubscriber() async throws {
        try await startWithInitialFile()
        let first = store.changes()
        let second = store.changes()

        try rewriteAndReload("depth = 7\n")
        store.stop()

        #expect(await F.collectAll(first) == [Config(depth: 7)])
        #expect(await F.collectAll(second) == [Config(depth: 7)])
    }

    @Test("購読をやめたストリームがあっても、残りの購読者には最新の設定を流す")
    func keepsYieldingAfterSubscriberTerminates() async throws {
        try await startWithInitialFile()
        // 破棄したストリームは終了扱いになり、次の配信で取り除かれる
        _ = store.changes()
        let active = store.changes()

        try rewriteAndReload("depth = 7\n")
        try rewriteAndReload("depth = 8\n")
        store.stop()

        // 追いつかない間の変更は最新の 1 件だけを残す
        #expect(await F.collectAll(active) == [Config(depth: 8)])
    }

    @Test("stop 後に購読したストリームはすぐに終わる")
    func changesAfterStopFinishesImmediately() async {
        store.stop()

        #expect(await F.collectAll(store.changes()).isEmpty)
    }
}
