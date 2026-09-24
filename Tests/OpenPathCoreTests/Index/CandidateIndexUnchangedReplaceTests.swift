import Testing

import OpenPathCore

/// 候補が前回と同じ差し替えを省く（Issue #78）。周期の再構築では大半のソースが前回と同じ候補を返すため、
/// 統合し直す CPU と一時的なメモリを使わないようにする。
@Suite("CandidateIndex: 変わっていない候補の差し替え")
struct CandidateIndexUnchangedReplaceTests {
    private typealias F = IndexFixtures

    private static let root = CandidateSourceKind.root("/Users/me/repos")
    private static let items = [
        F.directory("/Users/me/repos"),
        F.directory("/Users/me/repos/app"),
        F.file("/Users/me/repos/app/README.md"),
    ]

    private static func allPaths(in index: CandidateIndex) async throws -> [String] {
        try await index.query("", directoriesOnly: false, limit: F.generousLimit).map(\.candidate.path).sorted()
    }

    @Test("前回と同じ候補での差し替えは何もせず false を返し、候補はそのまま")
    func identicalItemsAreNotReplaced() async throws {
        let index = F.makeIndex()
        let first = await index.replace(source: Self.root, with: Self.items)

        let second = await index.replace(source: Self.root, with: Self.items)

        #expect(first)
        #expect(!second)
        #expect(index.count == Self.items.count)
        #expect(try await Self.allPaths(in: index) == Self.items.map(\.path).sorted())
    }

    /// 前回の候補から 1 か所だけ変えた候補
    enum ItemChange: CaseIterable, CustomTestStringConvertible {
        case added
        case removed
        case kindChanged
        case reordered

        var testDescription: String {
            switch self {
            case .added: "追加"
            case .removed: "削除"
            case .kindChanged: "種別の変化"
            case .reordered: "並びの変化"
            }
        }

        func applied(to items: [SourceItem]) -> [SourceItem] {
            switch self {
            case .added:
                items + [F.directory("/Users/me/repos/new")]
            case .removed:
                Array(items.dropLast())
            case .kindChanged:
                items.map { SourceItem(path: $0.path, isDirectory: !$0.isDirectory) }
            case .reordered:
                items.reversed()
            }
        }
    }

    @Test("候補が変わった差し替えは反映して true を返す", arguments: ItemChange.allCases)
    func changedItemsAreReplaced(change: ItemChange) async throws {
        let index = F.makeIndex()
        await index.replace(source: Self.root, with: Self.items)
        let changed = change.applied(to: Self.items)

        let didReplace = await index.replace(source: Self.root, with: changed)

        #expect(didReplace)
        let candidates = try await index.query("", directoriesOnly: false, limit: F.generousLimit).map(\.candidate)
        #expect(Set(candidates.map(\.path)) == Set(changed.map(\.path)))
        #expect(Set(candidates.filter(\.isDirectory).map(\.path)) == Set(changed.filter(\.isDirectory).map(\.path)))
    }

    @Test("候補の無いソースを空で差し替えても何もしない。候補のあるソースを空にするのは反映する")
    func emptyReplacement() async throws {
        let index = F.makeIndex()

        #expect(await !index.replace(source: .ghq, with: []))
        await index.replace(source: .ghq, with: [F.directory("/Users/me/repos/github.com/a/b")])
        #expect(await index.replace(source: .ghq, with: []))
        #expect(index.count == 0)
    }

    @Test("正規化前の表記で渡されても、正規化した候補が前回と同じなら差し替えない")
    func unnormalizedIdenticalItemsAreNotReplaced() async throws {
        let index = F.makeIndex()
        let unnormalized = [F.directory("/Users/me/repos/app/"), F.directory("/Users/me/repos//app/./src")]
        await index.replace(source: Self.root, with: unnormalized)

        let didReplace = await index.replace(source: Self.root, with: unnormalized)

        #expect(!didReplace)
        #expect(try await Self.allPaths(in: index) == ["/Users/me/repos/app", "/Users/me/repos/app/src"])
    }

    @Test("同じ候補の差し替えを省いても、他のソースの候補との統合は変わらない")
    func skippedReplacementKeepsOtherSources() async throws {
        let index = F.makeIndex()
        await index.replace(source: Self.root, with: Self.items)
        await index.replace(source: .ghq, with: [F.directory("/Users/me/repos/app")])
        await index.replace(source: .history, with: [F.directory("/Users/me/Desktop")])

        #expect(await !index.replace(source: Self.root, with: Self.items))

        let sources = try await index.query("", directoriesOnly: false, limit: F.generousLimit)
            .map(\.candidate)
            .reduce(into: [String: CandidateSourceKind]()) { $0[$1.path] = $1.source }
        #expect(sources["/Users/me/repos/app"] == .ghq)
        #expect(sources["/Users/me/Desktop"] == .history)
        #expect(sources.count == Self.items.count + 1)
    }
}
