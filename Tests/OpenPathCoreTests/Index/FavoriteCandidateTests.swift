import Foundation
import Testing
@testable import OpenPathCore

@Suite("お気に入り: 収集・統合・順位付け", .timeLimit(.minutes(1)))
struct FavoriteCandidateTests {
    private static let favorite = SourceItem(path: "/projects/repository", isDirectory: true, displayName: "仕事")

    @Test("履歴が無くてもお気に入りを先頭にし、別名と実パスの両方で検索できる")
    func prioritizesMatchingFavorites() async throws {
        let normal = "/other/仕事"
        let index = IndexFixtures.makeIndex(history: [.init(path: normal, count: 500, lastUsed: IndexFixtures.now)])
        await index.replace(source: .root("/"), with: [.directory(normal), .directory("/other/unrelated")])
        await index.replace(source: .favorites, with: [Self.favorite])
        #expect(try await index.query("", directoriesOnly: true, limit: 50).first?.candidate.path == Self.favorite.path)
        let alias = try await index.query("仕事", directoriesOnly: true, limit: 50)
        #expect(alias.first?.candidate.name == "仕事")
        #expect(alias.first?.candidate.path == Self.favorite.path)
        #expect(alias.first?.paletteRow.nameHighlights == [0, 1])
        #expect(try await index.query("repository", directoriesOnly: true, limit: 50).map(\.candidate.path) == [Self.favorite.path])
        #expect(try await index.query("unrelated", directoriesOnly: true, limit: 50).map(\.candidate.path) == ["/other/unrelated"])
    }

    /// 複数ソースの同じパスを統合しても、表示名と履歴の参照先を失わないことを確かめる。
    @Test("履歴・roots・ghq と同じパスは一件に統合し、別名と履歴を維持する")
    func mergesSourcesWithoutDuplicateRows() async throws {
        let index = IndexFixtures.makeIndex(history: [.init(path: Self.favorite.path, count: 2, lastUsed: IndexFixtures.now)])
        for source: CandidateSourceKind in [.history, .root("/projects"), .ghq] {
            await index.replace(source: source, with: [.directory(Self.favorite.path)])
        }
        await index.replace(source: .favorites, with: [Self.favorite])
        let result = try await index.query("", directoriesOnly: true, limit: 50)
        #expect(result.count == 1)
        #expect(result[0].candidate.source == .favorites)
        #expect(result[0].candidate.name == "仕事")
        #expect(result[0].candidate.lastUsed == IndexFixtures.now)
    }

    @Test("別名の変更で前処理を更新し、お気に入りを外すと通常の名前に戻る")
    func refreshesAliasesAndRestoresNormalName() async throws {
        let index = IndexFixtures.makeIndex()
        await index.replace(source: .root("/projects"), with: [.directory(Self.favorite.path)])
        await index.replace(source: .favorites, with: [Self.favorite])
        #expect(await index.replace(source: .favorites, with: [.init(path: Self.favorite.path, isDirectory: true, displayName: "請求書")]))
        #expect(try await index.query("仕事", directoriesOnly: true, limit: 50).isEmpty)
        #expect(try await index.query("請求書", directoriesOnly: true, limit: 50).first?.candidate.name == "請求書")
        await index.replace(source: .favorites, with: [])
        #expect(try await index.query("repository", directoriesOnly: true, limit: 50).first?.candidate.name == "repository")
    }

    @Test("前置フィルタでもパスに無い別名の文字を取りこぼさない")
    func prefilterIncludesAliasCharacters() async throws {
        let index = CandidateIndex(
            fileExistence: RecordingFileExistenceChecker(), now: { IndexFixtures.now }, prefilterThreshold: 1, history: { [] }
        )
        await index.replace(source: .favorites, with: [Self.favorite])
        #expect(try await index.query("仕事", directoriesOnly: true, limit: 50).map(\.candidate.path) == [Self.favorite.path])
    }

    @Test("ファイル・パッケージ・不存在を区別し、フォルダ専用パネルではファイルを返さない")
    func sourceChecksKindAndMissingPaths() async throws {
        let tree = try FileTreeFixture()
        try tree.makeDirectories("folder", "Sample.app/Contents")
        try tree.makeFiles("notes.txt")
        let source = FavoriteCandidateSource(favorites: [
            .init(name: "Folder", path: tree.path("folder")), .init(name: "Notes", path: tree.path("notes.txt")),
            .init(name: "App", path: tree.path("Sample.app")), .init(name: "Missing", path: tree.path("missing")),
        ])
        let snapshot = try await source.snapshot()
        #expect(snapshot.items.count == 3)
        #expect(snapshot.items.first { $0.displayName == "App" }?.isDirectory == false)
        let index = CandidateIndex(history: { [] })
        await index.replace(source: .favorites, with: snapshot.items)
        #expect(try await index.query("", directoriesOnly: true, limit: 50).map(\.candidate.name) == ["Folder"])
        try FileManager.default.removeItem(atPath: tree.path("folder"))
        #expect(try await index.query("Folder", directoriesOnly: false, limit: 50).allSatisfy { $0.candidate.path != tree.path("folder") })
    }

    @Test("パスの直接入力でも索引にある別名を表示する")
    func directInputPreservesAlias() throws {
        let tree = try FileTreeFixture()
        let row = PaletteRow(name: "仕事", path: tree.root, lastUsed: nil)
        let rows = DirectPathEntry().merging([row], query: tree.root, directoriesOnly: true, limit: 50)
        #expect(rows == [row])
    }
}

@MainActor
@Suite("お気に入り: 設定の再読み込み", .timeLimit(.minutes(1)))
struct FavoriteRebuildTests {
    @Test("お気に入りを変更・削除すると候補の別名も更新される")
    func applyingConfigRebuildsFavorites() async throws {
        let tree = try FileTreeFixture()
        try tree.makeDirectories("folder")
        let index = CandidateIndex(history: { [] })
        let provider = StandardCandidateSources(history: HistoryCandidateSource { [] }, searchPathProvider: SearchPathProviderSpy(path: "/usr/bin:/bin"))
        let config = Config(ghq: .init(enabled: false), favorites: [.init(name: "仕事", path: tree.path("folder"))])
        let rebuilder = CandidateIndexRebuilder(index: index, config: config, sourceProvider: provider)
        rebuilder.start()
        await rebuilder.waitUntilIdle()
        #expect(try await index.query("仕事", directoriesOnly: true, limit: 50).count == 1)
        rebuilder.apply(config: .init(ghq: .init(enabled: false), favorites: [.init(name: "請求書", path: tree.path("folder"))]))
        await rebuilder.waitUntilIdle()
        #expect(try await index.query("仕事", directoriesOnly: true, limit: 50).isEmpty)
        #expect(try await index.query("請求書", directoriesOnly: true, limit: 50).count == 1)
        rebuilder.apply(config: .init(ghq: .init(enabled: false)))
        await rebuilder.waitUntilIdle()
        #expect(try await index.query("", directoriesOnly: true, limit: 50).isEmpty)
        rebuilder.stop()
    }
}
